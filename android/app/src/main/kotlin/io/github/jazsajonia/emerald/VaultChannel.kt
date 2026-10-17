package io.github.jazsajonia.emerald

import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Storage Access Framework bridge for Emerald's vault.
 *
 * Design:
 * - The vault is a document tree chosen with ACTION_OPEN_DOCUMENT_TREE. Emerald
 *   takes a persistable read/write grant and remembers the tree URI.
 * - Dart only ever sends vault-relative paths ("Folder/Note.md"). They are
 *   resolved here by walking child documents of the tree by display name, so a
 *   path can never point outside the granted tree. Hidden entries (".name"),
 *   "." / ".." and separators are rejected.
 * - Writes are compare-and-swap: the current bytes are hashed and must match
 *   the hash Dart read earlier, otherwise CONFLICT is returned and nothing is
 *   written. After writing, the file is read back and verified.
 * - No file content or URIs are logged.
 */
class VaultChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "io.github.jazsajonia.emerald/vault"
        private const val REQUEST_PICK = 0x4E4D // "EM"
        private const val PREFS = "emerald_vault"
        private const val KEY_TREE = "tree_uri"
        private const val MAX_FILE_BYTES = 8L * 1024 * 1024
        private const val MAX_ENTRIES = 20000
        private const val MAX_DEPTH = 32
        private const val MD_MIME = "text/markdown"
        private val RW = Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    }

    private class VaultError(val code: String, message: String) : Exception(message)

    private data class Doc(
        val id: String,
        val name: String,
        val mime: String,
        val size: Long,
        val lastModified: Long,
        val flags: Int,
    ) {
        val isDir get() = mime == Document.MIME_TYPE_DIR
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val resolver: ContentResolver get() = activity.contentResolver
    private var pendingPick: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "pickVault") {
            pick(result)
            return
        }
        io.execute {
            try {
                val value = handle(call)
                main.post { result.success(value) }
            } catch (e: VaultError) {
                main.post { result.error(e.code, e.message, null) }
            } catch (e: SecurityException) {
                main.post { result.error("PERMISSION_DENIED", "Access to the vault folder was denied.", null) }
            } catch (e: FileNotFoundException) {
                main.post { result.error("NOT_FOUND", "File or folder not found.", null) }
            } catch (e: NotImplementedError) {
                main.post { result.notImplemented() }
            } catch (e: Exception) {
                // Only the exception type is reported, never paths or content.
                main.post { result.error("IO", "Storage error (${e.javaClass.simpleName}).", null) }
            }
        }
    }

    private fun handle(call: MethodCall): Any? = when (call.method) {
        "restoreVault" -> restore()
        "forgetVault" -> forget(Uri.parse(call.argument<String>("uri")!!))
        "listTree" -> listTree(tree(call))
        "readFile" -> readFile(tree(call), call.argument<String>("path")!!)
        "writeFile" -> writeFile(
            tree(call),
            call.argument<String>("path")!!,
            call.argument<ByteArray>("bytes")!!,
            call.argument<String>("expectedSha256")!!,
        )
        "createFile" -> createFile(
            tree(call),
            call.argument<String>("path")!!,
            call.argument<ByteArray>("bytes")!!,
        )
        "createDirectory" -> {
            ensureDirectory(tree(call), segments(call.argument<String>("path")!!)); null
        }
        "appFilesDir" -> activity.filesDir.absolutePath
        else -> throw NotImplementedError()
    }

    // ---- Picking and persisting the vault --------------------------------

    private fun pick(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("IO", "A folder picker is already open.", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            RW or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        try {
            activity.startActivityForResult(intent, REQUEST_PICK)
        } catch (e: Exception) {
            pendingPick = null
            result.error("IO", "No folder picker is available on this device.", null)
        }
    }

    /** Returns true if the result belonged to this channel. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.error("CANCELLED", "No folder selected.", null)
            return true
        }
        io.execute {
            try {
                resolver.takePersistableUriPermission(uri, RW)
                val previous = prefs().getString(KEY_TREE, null)
                if (previous != null && previous != uri.toString()) {
                    releaseQuietly(Uri.parse(previous))
                }
                prefs().edit().putString(KEY_TREE, uri.toString()).apply()
                val name = rootDoc(uri).name
                main.post { result.success(mapOf("uri" to uri.toString(), "name" to name)) }
            } catch (e: SecurityException) {
                main.post {
                    result.error("PERMISSION_DENIED", "Android did not grant lasting access to this folder.", null)
                }
            } catch (e: Exception) {
                main.post { result.error("IO", "Could not open the folder (${e.javaClass.simpleName}).", null) }
            }
        }
        return true
    }

    private fun prefs() = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun restore(): Map<String, String>? {
        val stored = prefs().getString(KEY_TREE, null) ?: return null
        val uri = Uri.parse(stored)
        val granted = resolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission && it.isWritePermission
        }
        if (!granted) throw VaultError("PERMISSION_DENIED", "Vault access is no longer granted.")
        val name = try {
            rootDoc(uri).name
        } catch (e: VaultError) {
            throw e
        } catch (e: Exception) {
            throw VaultError("PERMISSION_DENIED", "The vault folder can no longer be opened.")
        }
        return mapOf("uri" to stored, "name" to name)
    }

    private fun forget(uri: Uri): Any? {
        releaseQuietly(uri)
        if (prefs().getString(KEY_TREE, null) == uri.toString()) {
            prefs().edit().remove(KEY_TREE).apply()
        }
        return null
    }

    private fun releaseQuietly(uri: Uri) {
        try {
            resolver.releasePersistableUriPermission(uri, RW)
        } catch (_: Exception) {
        }
    }

    /** The tree URI from the call; must be the remembered vault. */
    private fun tree(call: MethodCall): Uri {
        val raw = call.argument<String>("uri")!!
        if (raw != prefs().getString(KEY_TREE, null)) {
            throw VaultError("PERMISSION_DENIED", "Not the selected vault.")
        }
        val uri = Uri.parse(raw)
        if (!DocumentsContract.isTreeUri(uri)) throw VaultError("INVALID_PATH", "Not a folder tree.")
        return uri
    }

    // ---- Path resolution ---------------------------------------------------

    private fun segments(path: String): List<String> {
        if (path.isEmpty()) return emptyList()
        if (path.startsWith("/") || path.contains('\\')) throw VaultError("INVALID_PATH", "Invalid path.")
        val parts = path.split('/')
        for (p in parts) {
            if (p.isEmpty() || p == "." || p == ".." || p.startsWith(".") ||
                p.any { it.code < 0x20 || it.code == 0x7f }
            ) {
                throw VaultError("INVALID_PATH", "Invalid path.")
            }
        }
        return parts
    }

    private val columns = arrayOf(
        Document.COLUMN_DOCUMENT_ID,
        Document.COLUMN_DISPLAY_NAME,
        Document.COLUMN_MIME_TYPE,
        Document.COLUMN_SIZE,
        Document.COLUMN_LAST_MODIFIED,
        Document.COLUMN_FLAGS,
    )

    private fun queryDocs(uri: Uri): List<Doc> {
        val out = ArrayList<Doc>()
        val cursor = resolver.query(uri, columns, null, null, null)
            ?: throw VaultError("PERMISSION_DENIED", "The storage provider returned no data.")
        cursor.use { c ->
            while (c.moveToNext()) {
                out.add(
                    Doc(
                        id = c.getString(0),
                        name = c.getString(1) ?: "",
                        mime = c.getString(2) ?: "",
                        size = if (c.isNull(3)) 0L else c.getLong(3),
                        lastModified = if (c.isNull(4)) 0L else c.getLong(4),
                        flags = if (c.isNull(5)) 0 else c.getInt(5),
                    ),
                )
            }
        }
        return out
    }

    private fun docUri(tree: Uri, id: String) = DocumentsContract.buildDocumentUriUsingTree(tree, id)

    private fun rootDoc(tree: Uri): Doc =
        queryDocs(docUri(tree, DocumentsContract.getTreeDocumentId(tree))).firstOrNull()
            ?: throw VaultError("NOT_FOUND", "Vault folder not found.")

    private fun children(tree: Uri, parentId: String): List<Doc> =
        queryDocs(DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId))

    private fun child(tree: Uri, parentId: String, name: String): Doc? {
        val matches = children(tree, parentId).filter { it.name == name }
        if (matches.size > 1) throw VaultError("IO", "Several entries share the same name.")
        return matches.firstOrNull()
    }

    private fun resolve(tree: Uri, path: String): Doc {
        var doc = rootDoc(tree)
        for (seg in segments(path)) {
            if (!doc.isDir) throw VaultError("NOT_FOUND", "Not found.")
            doc = child(tree, doc.id, seg) ?: throw VaultError("NOT_FOUND", "Not found.")
        }
        return doc
    }

    // ---- Operations --------------------------------------------------------

    private fun listTree(tree: Uri): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        val queue = ArrayDeque<Triple<String, String, Int>>() // docId, path, depth
        queue.add(Triple(rootDoc(tree).id, "", 0))
        while (queue.isNotEmpty()) {
            val (id, prefix, depth) = queue.removeFirst()
            for (d in children(tree, id)) {
                if (d.name.isEmpty() || d.name.startsWith(".") || d.name.contains('/')) continue
                val path = if (prefix.isEmpty()) d.name else "$prefix/${d.name}"
                if (d.isDir) {
                    out.add(mapOf("path" to path, "isDir" to true, "size" to 0L, "lastModified" to d.lastModified))
                    if (depth + 1 < MAX_DEPTH) queue.add(Triple(d.id, path, depth + 1))
                } else if (d.name.lowercase().endsWith(".md")) {
                    out.add(mapOf("path" to path, "isDir" to false, "size" to d.size, "lastModified" to d.lastModified))
                }
                if (out.size >= MAX_ENTRIES) {
                    throw VaultError("TOO_LARGE", "The vault has more than $MAX_ENTRIES entries.")
                }
            }
        }
        return out
    }

    private fun readBytes(uri: Uri): ByteArray {
        val input = resolver.openInputStream(uri) ?: throw VaultError("IO", "Could not open file.")
        input.use { s ->
            val buf = ByteArrayOutputStream()
            val chunk = ByteArray(64 * 1024)
            var total = 0L
            while (true) {
                val n = s.read(chunk)
                if (n < 0) break
                total += n
                if (total > MAX_FILE_BYTES) throw VaultError("TOO_LARGE", "File is larger than 8 MB.")
                buf.write(chunk, 0, n)
            }
            return buf.toByteArray()
        }
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun stamp(tree: Uri, doc: Doc, bytes: ByteArray): Map<String, Any> {
        val fresh = queryDocs(docUri(tree, doc.id)).firstOrNull() ?: doc
        return mapOf(
            "size" to bytes.size.toLong(),
            "lastModified" to fresh.lastModified,
            "sha256" to sha256(bytes),
        )
    }

    private fun readFile(tree: Uri, path: String): Map<String, Any> {
        val doc = resolve(tree, path)
        if (doc.isDir) throw VaultError("NOT_FOUND", "That is a folder.")
        if (doc.size > MAX_FILE_BYTES) throw VaultError("TOO_LARGE", "File is larger than 8 MB.")
        val bytes = readBytes(docUri(tree, doc.id))
        return stamp(tree, doc, bytes) + ("bytes" to bytes)
    }

    private fun writeBytes(uri: Uri, bytes: ByteArray) {
        // "wt" = write + truncate. Plain "w" does not truncate on some
        // providers, which would leave stale bytes after shorter content.
        val out = resolver.openOutputStream(uri, "wt") ?: throw VaultError("IO", "Could not open file for writing.")
        out.use {
            it.write(bytes)
            it.flush()
        }
    }

    private fun writeVerified(tree: Uri, doc: Doc, bytes: ByteArray, previous: ByteArray?) {
        val uri = docUri(tree, doc.id)
        writeBytes(uri, bytes)
        val check = readBytes(uri)
        if (!check.contentEquals(bytes)) {
            if (previous != null) {
                try {
                    writeBytes(uri, previous)
                } catch (_: Exception) {
                }
            }
            throw VaultError("IO", "The saved file could not be verified.")
        }
    }

    private fun writeFile(tree: Uri, path: String, bytes: ByteArray, expected: String): Map<String, Any> {
        if (bytes.size > MAX_FILE_BYTES) throw VaultError("TOO_LARGE", "Note is larger than 8 MB.")
        val doc = resolve(tree, path)
        if (doc.isDir) throw VaultError("NOT_FOUND", "That is a folder.")
        if (doc.flags and Document.FLAG_SUPPORTS_WRITE == 0) {
            throw VaultError("READ_ONLY", "This file cannot be modified.")
        }
        val current = readBytes(docUri(tree, doc.id))
        if (sha256(current) != expected) {
            throw VaultError("CONFLICT", "The file changed since it was opened.")
        }
        writeVerified(tree, doc, bytes, current)
        return stamp(tree, doc, bytes)
    }

    private fun ensureDirectory(tree: Uri, segs: List<String>): Doc {
        var doc = rootDoc(tree)
        for (seg in segs) {
            val existing = child(tree, doc.id, seg)
            doc = when {
                existing == null -> {
                    val created = DocumentsContract.createDocument(
                        resolver, docUri(tree, doc.id), Document.MIME_TYPE_DIR, seg,
                    ) ?: throw VaultError("IO", "Could not create folder.")
                    queryDocs(created).firstOrNull() ?: throw VaultError("IO", "Could not create folder.")
                }
                existing.isDir -> existing
                else -> throw VaultError("ALREADY_EXISTS", "A file with that name exists.")
            }
        }
        return doc
    }

    private fun createFile(tree: Uri, path: String, bytes: ByteArray): Map<String, Any> {
        if (bytes.size > MAX_FILE_BYTES) throw VaultError("TOO_LARGE", "Note is larger than 8 MB.")
        val segs = segments(path)
        if (segs.isEmpty()) throw VaultError("INVALID_PATH", "Invalid path.")
        val name = segs.last()
        val parentSegs = segs.dropLast(1)
        var parent = rootDoc(tree)
        for (seg in parentSegs) {
            parent = child(tree, parent.id, seg)?.takeIf { it.isDir }
                ?: throw VaultError("NOT_FOUND", "Folder not found.")
        }
        if (child(tree, parent.id, name) != null) {
            throw VaultError("ALREADY_EXISTS", "A note with that name already exists.")
        }
        val createdUri = DocumentsContract.createDocument(resolver, docUri(tree, parent.id), MD_MIME, name)
            ?: throw VaultError("IO", "Could not create the note.")
        var created = queryDocs(createdUri).firstOrNull() ?: throw VaultError("IO", "Could not create the note.")
        if (created.name != name) {
            // Some providers adjust the name (e.g. appending an extension).
            // Try to restore the requested name; otherwise report the real one.
            try {
                val renamed = DocumentsContract.renameDocument(resolver, createdUri, name)
                if (renamed != null) {
                    created = queryDocs(renamed).firstOrNull() ?: created
                }
            } catch (_: Exception) {
            }
        }
        writeVerified(tree, created, bytes, null)
        val finalPath = (parentSegs + created.name).joinToString("/")
        return stamp(tree, created, bytes) + ("path" to finalPath)
    }
}
