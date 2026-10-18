# Vault storage on Android

Sapphire reads and writes your notes **in place**, in a folder you choose. It
does not copy the vault into app storage.

## How access works

- **Choosing a folder** uses Android's system folder picker
  (`Intent.ACTION_OPEN_DOCUMENT_TREE`, the Storage Access Framework). Sapphire
  requests no broad storage permission.
- Sapphire then calls `ContentResolver.takePersistableUriPermission` with read
  and write access so the folder stays available after restarts, and remembers
  the folder in app-private preferences.
- On every launch Sapphire checks `ContentResolver.getPersistedUriPermissions`.
  If the grant is gone (folder moved/deleted, app data cleared, access revoked)
  the app shows **"Vault access was lost"** and asks you to choose the folder
  again. Notes are never touched in that case.
- "Forget vault" in Settings releases the grant
  (`releasePersistableUriPermission`) and forgets the folder. Files are untouched.

Implementation: `android/app/src/main/kotlin/io/github/jazsajonia/sapphire/VaultChannel.kt`
(Kotlin) and `lib/data/saf_vault_storage.dart` (Dart).

## Safety rules

- Paths are vault-relative (`Folder/Note.md`). Both Dart (`VaultPath`) and
  Kotlin reject absolute paths, `..`, `.`, backslashes, control characters and
  hidden names. Kotlin resolves a path by walking child documents of the
  granted tree by name, so a path cannot point outside the vault.
- Hidden entries (names starting with `.`, e.g. `.obsidian`, `.trash`, `.git`)
  are never listed or written. Only `.md` files are shown.
- **Conflict detection:** when you open a note Sapphire records the SHA-256 of
  its bytes. Saving first re-reads the file; if the hash differs (another app
  changed it), nothing is written and you choose: save your version as a copy,
  load the other version, or explicitly overwrite (confirmation required).
- **Verified writes:** content is written with mode `"wt"` (write + truncate;
  plain `"w"` does not truncate on some providers), then read back and
  compared. If verification fails Sapphire tries to restore the previous bytes
  and reports an error.
- **Previous versions:** before each overwrite, the previous bytes are kept in
  app-private storage (last 20 per note, hashed file names, never inside the
  vault). Open a note → ⋮ → *Previous versions* to put an older text back
  into the editor. This history is deleted if the app is uninstalled or its
  data is cleared.
- New notes never overwrite: creating a note whose name exists is refused.
- Encoding: UTF-8 (BOM preserved). Files that use CRLF consistently are
  written back with CRLF. Files with invalid UTF-8 or mixed line endings open
  **read-only** so Sapphire never rewrites bytes you did not edit.
- Files larger than 8 MB are not opened; vaults with more than 20,000 entries
  are rejected with a clear error.
- Logs never contain note contents or folder URIs.

## Known limitations (honest list)

- **Not truly atomic.** SAF has no "write temp file and atomically replace"
  operation that works across providers. Sapphire uses compare-before-write,
  read-back verification and on-device history instead. A crash or power loss
  in the middle of a write could still leave a partially written file; the
  previous version is then available under *Previous versions*.
- **Small race window.** Conflict detection compares the file right before
  writing. An external write landing in the milliseconds between that check
  and the write is not detected.
- **Android 11+ picker restrictions:** the root of internal storage, the root
  of SD cards, and the `Download` folder itself cannot be chosen; choose (or
  create) a subfolder such as `Documents/Vault`.
- **Other editors:** changes are visible to another app only if it reads the
  same folder (for example Obsidian pointed at the same directory). Sapphire
  notices outside changes when you return to the app or try to save, and with
  the Rescan button.
- **Cloud providers** offered in the picker (e.g. Google Drive) may behave
  differently (slower listing, modified times, renaming). Local device storage
  is the tested target.
- Symlinks are not followed specially; Android's external storage provider
  presents what is inside the chosen tree.
- Renaming, moving and deleting notes are not implemented yet.
