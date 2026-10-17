import 'dart:typed_data';

import '../../core/vault/hashing.dart';
import '../../core/vault/vault_path.dart';
import '../../data/vault_storage.dart';
import '../notes/note_history.dart';
import 'git_hash.dart';
import 'github_client.dart';
import 'sync_state_store.dart';

enum SyncActionKind {
  inSync,
  upload,
  download,
  conflict,

  /// Removed on GitHub but unchanged locally: the local note is kept.
  remoteDeletedKept,

  /// Missing locally but unchanged on GitHub: the GitHub copy is kept.
  localMissingKept,

  /// Gone on both sides: forget the base entry.
  forget,
}

class PlannedAction {
  const PlannedAction(
    this.path,
    this.kind, {
    this.local,
    this.remote,
    this.base,
  });
  final String path;
  final SyncActionKind kind;
  final String? local;
  final String? remote;
  final String? base;

  @override
  String toString() => '$kind $path';
}

/// Three-way comparison of local, remote and last-synced Git blob SHAs.
///
/// Policy (docs/SYNC.md): nothing is ever deleted on either side; when both
/// sides changed, GitHub's version is saved as a conflict copy next to the
/// local note.
List<PlannedAction> planSync({
  required Map<String, String> local,
  required Map<String, String> remote,
  required Map<String, String> base,
}) {
  final paths = {...local.keys, ...remote.keys, ...base.keys}.toList()..sort();
  final out = <PlannedAction>[];
  for (final p in paths) {
    final l = local[p], r = remote[p], b = base[p];
    PlannedAction a(SyncActionKind k) =>
        PlannedAction(p, k, local: l, remote: r, base: b);
    if (l == null && r == null) {
      out.add(a(SyncActionKind.forget));
    } else if (l != null && l == r) {
      out.add(a(SyncActionKind.inSync));
    } else if (b == null) {
      out.add(
        a(
          l == null
              ? SyncActionKind.download
              : r == null
              ? SyncActionKind.upload
              : SyncActionKind.conflict,
        ),
      );
    } else if (l == b) {
      out.add(
        a(
          r == null
              ? SyncActionKind.remoteDeletedKept
              : SyncActionKind.download,
        ),
      );
    } else if (r == b) {
      out.add(
        a(l == null ? SyncActionKind.localMissingKept : SyncActionKind.upload),
      );
    } else if (l == null) {
      out.add(
        a(SyncActionKind.download),
      ); // deleted here, edited there: restore
    } else if (r == null) {
      out.add(a(SyncActionKind.upload)); // edited here, deleted there: re-add
    } else {
      out.add(a(SyncActionKind.conflict));
    }
  }
  return out;
}

class SyncConflict {
  const SyncConflict(this.path, this.copyPath);
  final String path;

  /// Where GitHub's version was saved, or null if that failed.
  final String? copyPath;
}

class SyncReport {
  int uploaded = 0;
  int downloaded = 0;
  int unchanged = 0;
  final List<SyncConflict> conflicts = [];
  final List<String> notices = [];
  final List<String> failures = [];
  SyncException? fatal;
  DateTime? finishedAt;

  bool get ok => fatal == null && failures.isEmpty;
  bool get changedLocalFiles => downloaded > 0 || conflicts.isNotEmpty;
}

typedef SyncProgress = void Function(int done, int total, String path);

/// Runs one sync. Operations are sequential (GitHub requires serial content
/// writes). Each local overwrite re-reads and verifies the file and keeps the
/// previous version in note history.
class SyncEngine {
  SyncEngine({
    required this.vault,
    required this.storage,
    required this.history,
    required this.client,
    required this.branch,
    this.maxFileBytes = 8 * 1024 * 1024,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final VaultHandle vault;
  final VaultStorage storage;
  final NoteHistory history;
  final GitHubClient client;
  final String branch;
  final int maxFileBytes;
  final DateTime Function() _now;

  static bool _syncablePath(String p) {
    if (!VaultPath.isMarkdown(p)) return false;
    try {
      if (VaultPath.normalize(p) != p) return false;
    } on InvalidVaultPath {
      return false;
    }
    return !VaultPath.segments(p).any(VaultPath.isIgnoredName);
  }

  Future<SyncReport> run(SyncBase base, {SyncProgress? onProgress}) async {
    final report = SyncReport();
    try {
      await _run(base, report, onProgress);
    } on SyncException catch (e) {
      report.fatal = e;
    } on VaultException catch (e) {
      report.fatal = SyncException(
        SyncErrorCode.invalidResponse,
        'storage: ${e.code.name}',
      );
      if (e.code == VaultErrorCode.permissionDenied) {
        report.failures.add('Lost access to the vault folder.');
      }
    }
    report.finishedAt = _now();
    if (report.fatal == null) base.lastSync = report.finishedAt;
    return report;
  }

  Future<void> _run(
    SyncBase base,
    SyncReport report,
    SyncProgress? onProgress,
  ) async {
    // Remote first: fail fast on auth/network problems before reading files.
    final remote = <String, String>{};
    for (final f in await client.listFiles(branch)) {
      if (!_syncablePath(f.path)) continue;
      if (f.size > maxFileBytes) {
        report.notices.add('${f.path}: skipped (larger than 8 MB on GitHub)');
        continue;
      }
      remote[f.path] = f.sha;
    }

    final entries = <String, VaultEntry>{
      for (final e in await storage.listTree(vault))
        if (!e.isDirectory && _syncablePath(e.path)) e.path: e,
    };
    final local = <String, String>{};
    for (final e in entries.values) {
      if (e.size > maxFileBytes) {
        report.notices.add('${e.path}: skipped (larger than 8 MB)');
        continue;
      }
      final known = base.files[e.path];
      if (known != null &&
          e.lastModified > 0 &&
          known.lastModified == e.lastModified &&
          known.size == e.size) {
        local[e.path] = known.sha;
      } else {
        local[e.path] = gitBlobSha(
          (await storage.readFile(vault, e.path)).bytes,
        );
      }
    }

    final plan = planSync(
      local: local,
      remote: remote,
      base: {for (final e in base.files.entries) e.key: e.value.sha},
    );
    final work = plan.where((a) => a.kind != SyncActionKind.inSync).length;
    var done = 0;
    for (final a in plan) {
      if (a.kind != SyncActionKind.inSync) {
        onProgress?.call(done++, work, a.path);
      }
      try {
        await _apply(a, entries[a.path], base, report);
      } on SyncException catch (e) {
        if (e.fatal) rethrow;
        report.failures.add('${a.path}: ${e.userMessage}');
      } on VaultException catch (e) {
        if (e.code == VaultErrorCode.permissionDenied) rethrow;
        report.failures.add('${a.path}: ${_vaultMessage(e)}');
      }
    }
    onProgress?.call(work, work, '');
  }

  static String _vaultMessage(VaultException e) => switch (e.code) {
    VaultErrorCode.conflict => 'changed during sync; will retry next time',
    VaultErrorCode.alreadyExists => 'a file with that name already exists',
    VaultErrorCode.tooLarge => 'too large',
    _ => 'could not be written (${e.code.name})',
  };

  Future<void> _apply(
    PlannedAction a,
    VaultEntry? entry,
    SyncBase base,
    SyncReport report,
  ) async {
    switch (a.kind) {
      case SyncActionKind.inSync:
        report.unchanged++;
        base.files[a.path] = SyncedFile(
          sha: a.local!,
          size: entry?.size ?? -1,
          lastModified: entry?.lastModified ?? 0,
        );
      case SyncActionKind.forget:
        base.files.remove(a.path);
      case SyncActionKind.remoteDeletedKept:
        report.notices.add(
          '${a.path}: removed on GitHub; kept on this phone (not re-uploaded)',
        );
      case SyncActionKind.localMissingKept:
        report.notices.add('${a.path}: missing on this phone; kept on GitHub');
      case SyncActionKind.upload:
        await _upload(a, entry!, base, report);
      case SyncActionKind.download:
        await _download(a, base, report);
      case SyncActionKind.conflict:
        await _conflict(a, base, report);
    }
  }

  Future<void> _upload(
    PlannedAction a,
    VaultEntry entry,
    SyncBase base,
    SyncReport report,
  ) async {
    final c = await storage.readFile(vault, a.path);
    final sha = gitBlobSha(c.bytes);
    if (sha != a.local) {
      _invalidate(base, a.path);
      throw VaultException(VaultErrorCode.conflict);
    }
    await client.putFile(
      path: a.path,
      bytes: c.bytes,
      branch: branch,
      message:
          '${a.remote == null ? 'Add' : 'Update'} ${a.path} (Emerald sync)',
      previousSha: a.remote,
    );
    base.files[a.path] = SyncedFile(
      sha: sha,
      size: c.stamp.size,
      lastModified: c.stamp.lastModified,
    );
    report.uploaded++;
  }

  /// Forces the next sync to re-read [path] instead of trusting its stat.
  static void _invalidate(SyncBase base, String path) {
    final b = base.files[path];
    if (b != null) {
      base.files[path] = SyncedFile(sha: b.sha, size: -1, lastModified: 0);
    }
  }

  Future<Uint8List> _fetch(String sha) async {
    final bytes = await client.getBlob(sha);
    if (gitBlobSha(bytes) != sha) {
      throw SyncException(SyncErrorCode.invalidResponse, 'blob hash mismatch');
    }
    return bytes;
  }

  Future<void> _download(
    PlannedAction a,
    SyncBase base,
    SyncReport report,
  ) async {
    final bytes = await _fetch(a.remote!);
    FileStamp stamp;
    if (a.local != null) {
      // Re-read and verify the local file is still what we compared.
      final current = await storage.readFile(vault, a.path);
      if (gitBlobSha(current.bytes) != a.local) {
        _invalidate(base, a.path);
        throw VaultException(VaultErrorCode.conflict);
      }
      await history.record(vault.id, a.path, current.bytes);
      stamp = await storage.writeFile(
        vault,
        a.path,
        bytes,
        expectedSha256: current.stamp.sha256,
      );
    } else {
      final parent = VaultPath.parent(a.path);
      if (parent.isNotEmpty) await storage.createDirectory(vault, parent);
      final created = await storage.createFile(vault, a.path, bytes);
      if (created.path != a.path) {
        report.notices.add(
          '${a.path}: saved as ${created.path} (name was taken)',
        );
        report.downloaded++;
        return;
      }
      stamp = created.stamp;
    }
    assert(stamp.sha256 == sha256Hex(bytes));
    base.files[a.path] = SyncedFile(
      sha: a.remote!,
      size: stamp.size,
      lastModified: stamp.lastModified,
    );
    report.downloaded++;
  }

  Future<void> _conflict(
    PlannedAction a,
    SyncBase base,
    SyncReport report,
  ) async {
    final bytes = await _fetch(a.remote!);
    final t = _now().toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final when =
        '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}${two(t.minute)}';
    final dir = VaultPath.parent(a.path);
    final title = VaultPath.title(a.path);
    for (var i = 1; i < 100; i++) {
      final name = VaultPath.fileNameForTitle(
        '$title (GitHub conflict $when${i == 1 ? '' : ' $i'})',
      );
      try {
        final created = await storage.createFile(
          vault,
          VaultPath.join(dir, name),
          bytes,
        );
        // GitHub's version is now safe locally; the local note stays as is
        // and is uploaded on the next sync (after the user has reviewed).
        base.files[a.path] = SyncedFile(
          sha: a.remote!,
          size: -1,
          lastModified: 0,
        );
        report.conflicts.add(SyncConflict(a.path, created.path));
        return;
      } on VaultException catch (e) {
        if (e.code != VaultErrorCode.alreadyExists) rethrow;
      }
    }
    report.conflicts.add(SyncConflict(a.path, null));
  }
}
