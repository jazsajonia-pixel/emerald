import 'dart:typed_data';

import '../../core/vault/vault_path.dart';
import '../../data/vault_storage.dart';
import 'note_codec.dart';
import 'note_history.dart';

/// A note as read from the vault, plus what is needed to save it safely.
class NoteDocument {
  const NoteDocument({
    required this.path,
    required this.decoded,
    required this.stamp,
    required this.bytes,
  });

  final String path;
  final DecodedNote decoded;
  final FileStamp stamp;

  /// Exact bytes read from storage (used for history).
  final Uint8List bytes;

  String get text => decoded.text;
  String get title => VaultPath.title(path);
  bool get readOnly => decoded.readOnly;
}

class NoteRepository {
  NoteRepository(this._storage, this._history, {this.onWrite});

  final VaultStorage _storage;
  final NoteHistory _history;

  /// Called after every successful write (used to trigger auto sync).
  final void Function()? onWrite;

  static NoteDocument _doc(String path, FileContent c) => NoteDocument(
    path: path,
    decoded: NoteCodec.decode(c.bytes),
    stamp: c.stamp,
    bytes: c.bytes,
  );

  Future<NoteDocument> open(VaultHandle vault, String path) async {
    final p = VaultPath.normalize(path);
    if (!VaultPath.isMarkdown(p)) {
      throw VaultException(VaultErrorCode.invalidPath, 'Not a Markdown file');
    }
    return _doc(p, await _storage.readFile(vault, p));
  }

  /// Saves [text] over [doc]. Throws [VaultErrorCode.conflict] if the file
  /// changed since [doc] was read; nothing is written in that case.
  Future<NoteDocument> save(
    VaultHandle vault,
    NoteDocument doc,
    String text,
  ) async {
    if (doc.readOnly) {
      throw VaultException(VaultErrorCode.readOnly, doc.decoded.readOnlyReason);
    }
    final bytes = NoteCodec.encode(
      text,
      hasBom: doc.decoded.hasBom,
      crlf: doc.decoded.crlf,
    );
    await _history.record(vault.id, doc.path, doc.bytes);
    final stamp = await _storage.writeFile(
      vault,
      doc.path,
      bytes,
      expectedSha256: doc.stamp.sha256,
    );
    onWrite?.call();
    return NoteDocument(
      path: doc.path,
      decoded: NoteCodec.decode(bytes),
      stamp: stamp,
      bytes: bytes,
    );
  }

  /// Explicitly replaces whatever is currently in the file (after the user
  /// confirmed overwriting an external change). The current version is kept
  /// in history first.
  Future<NoteDocument> overwrite(
    VaultHandle vault,
    NoteDocument doc,
    String text,
  ) async {
    final current = await open(vault, doc.path);
    return save(vault, current, text);
  }

  Future<NoteDocument> create(
    VaultHandle vault,
    String dir,
    String title, {
    String? content,
  }) async {
    final path = VaultPath.join(dir, VaultPath.fileNameForTitle(title));
    final created = await _storage.createFile(
      vault,
      path,
      NoteCodec.encode(content ?? ''),
    );
    onWrite?.call();
    return open(vault, created.path);
  }

  /// Saves [text] as a new sibling note so neither version is lost.
  Future<NoteDocument> saveCopy(
    VaultHandle vault,
    NoteDocument doc,
    String text, {
    DateTime? now,
  }) async {
    final t = (now ?? DateTime.now()).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}${two(t.minute)}';
    final dir = VaultPath.parent(doc.path);
    for (var i = 1; i < 100; i++) {
      final suffix = i == 1 ? '' : ' $i';
      try {
        return await create(
          vault,
          dir,
          '${doc.title} (conflict $stamp$suffix)',
          content: text,
        );
      } on VaultException catch (e) {
        if (e.code != VaultErrorCode.alreadyExists) rethrow;
      }
    }
    throw VaultException(VaultErrorCode.alreadyExists, 'Too many copies');
  }

  /// Recreates a note that was deleted externally while open.
  Future<NoteDocument> recreate(
    VaultHandle vault,
    String path,
    String text,
  ) async {
    final created = await _storage.createFile(
      vault,
      path,
      NoteCodec.encode(text),
    );
    onWrite?.call();
    return open(vault, created.path);
  }
}
