import 'dart:io';
import 'dart:typed_data';

import '../../core/vault/hashing.dart';

class HistoryEntry {
  const HistoryEntry({required this.savedAt, required this.file});
  final DateTime savedAt;
  final File file;
}

/// Keeps recent previous versions of notes in app-private storage so an
/// overwrite can be undone. This is a safety net, not a sync mechanism: it
/// is never written into the vault and is lost if the app is uninstalled.
abstract interface class NoteHistory {
  Future<void> record(String vaultId, String path, Uint8List previous);
  Future<List<HistoryEntry>> list(String vaultId, String path);
}

class NoHistory implements NoteHistory {
  const NoHistory();
  @override
  Future<void> record(String vaultId, String path, Uint8List previous) async {}
  @override
  Future<List<HistoryEntry>> list(String vaultId, String path) async =>
      const [];
}

class FileNoteHistory implements NoteHistory {
  FileNoteHistory(this._baseDir, {this.maxPerNote = 20});

  final Future<Directory> Function() _baseDir;
  final int maxPerNote;

  Future<Directory> _dirFor(String vaultId, String path) async {
    final base = await _baseDir();
    // Hashed names: no note titles or paths appear in the file system.
    final d = Directory(
      '${base.path}/history/${sha256Hex(vaultId.codeUnits).substring(0, 16)}/'
      '${sha256Hex(path.codeUnits).substring(0, 24)}',
    );
    return d.create(recursive: true);
  }

  @override
  Future<void> record(String vaultId, String path, Uint8List previous) async {
    final dir = await _dirFor(vaultId, path);
    final ts = DateTime.now().toUtc().microsecondsSinceEpoch;
    await File('${dir.path}/$ts.md').writeAsBytes(previous, flush: true);
    final entries = await list(vaultId, path);
    for (final old in entries.skip(maxPerNote)) {
      await old.file.delete();
    }
  }

  @override
  Future<List<HistoryEntry>> list(String vaultId, String path) async {
    final dir = await _dirFor(vaultId, path);
    final out = <HistoryEntry>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.md')) continue;
      final name = f.uri.pathSegments.last;
      final ts = int.tryParse(name.substring(0, name.length - 3));
      if (ts == null) continue;
      out.add(
        HistoryEntry(
          savedAt: DateTime.fromMicrosecondsSinceEpoch(ts, isUtc: true),
          file: f,
        ),
      );
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }
}
