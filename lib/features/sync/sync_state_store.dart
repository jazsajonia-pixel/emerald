import 'dart:convert';
import 'dart:io';

import '../../core/vault/hashing.dart';

/// What a file looked like at the last successful sync.
class SyncedFile {
  const SyncedFile({
    required this.sha,
    required this.size,
    required this.lastModified,
  });

  /// Git blob SHA of the content both sides had.
  final String sha;

  /// Local size / modification time right after the sync. If both are
  /// unchanged (and the time is known), the file is assumed unchanged and not
  /// re-read. Before any local overwrite the file is always re-read and
  /// verified, so this shortcut can delay an upload but never lose data.
  final int size;
  final int lastModified;

  Map<String, Object?> toJson() => {
    'sha': sha,
    'size': size,
    'mtime': lastModified,
  };

  static SyncedFile? fromJson(Object? j) {
    if (j is! Map || j['sha'] is! String) return null;
    return SyncedFile(
      sha: j['sha'] as String,
      size: (j['size'] as num?)?.toInt() ?? -1,
      lastModified: (j['mtime'] as num?)?.toInt() ?? 0,
    );
  }
}

class SyncBase {
  SyncBase(this.files, {this.lastSync, Set<String>? lastChangedPaths})
    : lastChangedPaths = lastChangedPaths ?? <String>{};
  final Map<String, SyncedFile> files;
  DateTime? lastSync;
  Set<String> lastChangedPaths;

  static SyncBase empty() => SyncBase({});
}

abstract interface class SyncStateStore {
  /// [scope] identifies vault + repository + branch; a different scope starts
  /// from an empty base (first sync is treated conservatively).
  Future<SyncBase> load(String scope);
  Future<void> save(String scope, SyncBase base);
  Future<void> clear(String scope);
}

class MemorySyncStateStore implements SyncStateStore {
  final Map<String, SyncBase> data = {};
  @override
  Future<SyncBase> load(String scope) async => SyncBase(
    Map.of(data[scope]?.files ?? const {}),
    lastSync: data[scope]?.lastSync,
    lastChangedPaths: Set.of(data[scope]?.lastChangedPaths ?? const {}),
  );
  @override
  Future<void> save(String scope, SyncBase base) async =>
      data[scope] = SyncBase(
        Map.of(base.files),
        lastSync: base.lastSync,
        lastChangedPaths: Set.of(base.lastChangedPaths),
      );
  @override
  Future<void> clear(String scope) async => data.remove(scope);
}

/// JSON file in app-private storage (not in the vault, not backed up).
class FileSyncStateStore implements SyncStateStore {
  FileSyncStateStore(this._baseDir);
  final Future<Directory> Function() _baseDir;

  Future<File> _file(String scope) async {
    final d = Directory('${(await _baseDir()).path}/sync');
    await d.create(recursive: true);
    return File(
      '${d.path}/${sha256Hex(utf8.encode(scope)).substring(0, 24)}.json',
    );
  }

  @override
  Future<SyncBase> load(String scope) async {
    final f = await _file(scope);
    if (!await f.exists()) return SyncBase.empty();
    try {
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return SyncBase.empty();
      final files = <String, SyncedFile>{};
      final raw = j['files'];
      if (raw is Map) {
        for (final e in raw.entries) {
          final s = SyncedFile.fromJson(e.value);
          if (e.key is String && s != null) files[e.key as String] = s;
        }
      }
      final last = j['lastSync'];
      return SyncBase(
        files,
        lastSync: last is String ? DateTime.tryParse(last) : null,
        lastChangedPaths: {
          if (j['lastChangedPaths'] is List)
            for (final p in j['lastChangedPaths'] as List)
              if (p is String) p,
        },
      );
    } on FormatException {
      // A damaged state file only makes the next sync more conservative.
      return SyncBase.empty();
    }
  }

  @override
  Future<void> save(String scope, SyncBase base) async {
    final f = await _file(scope);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'files': {for (final e in base.files.entries) e.key: e.value.toJson()},
        'lastSync': base.lastSync?.toUtc().toIso8601String(),
        'lastChangedPaths': base.lastChangedPaths.toList()..sort(),
      }),
      flush: true,
    );
    await tmp.rename(f.path);
  }

  @override
  Future<void> clear(String scope) async {
    final f = await _file(scope);
    if (await f.exists()) await f.delete();
  }
}
