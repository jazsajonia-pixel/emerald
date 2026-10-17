import 'dart:convert';
import 'dart:typed_data';

import 'package:emerald/data/memory_vault_storage.dart';
import 'package:emerald/data/vault_storage.dart';
import 'package:emerald/features/notes/note_history.dart';
import 'package:emerald/features/sync/github_client.dart';
import 'package:emerald/features/sync/sync_engine.dart';
import 'package:emerald/features/sync/sync_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_github.dart';

const vault = VaultHandle(id: 'memory://vault', name: 'V');

class RecordingHistory implements NoteHistory {
  final List<String> recorded = [];
  @override
  Future<void> record(String vaultId, String path, Uint8List previous) async =>
      recorded.add('$path=${utf8.decode(previous)}');
  @override
  Future<List<HistoryEntry>> list(String vaultId, String path) async =>
      const [];
}

void main() {
  group('planSync', () {
    SyncActionKind k(String? l, String? r, String? b) => planSync(
      local: {'p': ?l},
      remote: {'p': ?r},
      base: {'p': ?b},
    ).single.kind;

    test('decision table', () {
      expect(k('a', 'a', null), SyncActionKind.inSync);
      expect(k('a', 'a', 'z'), SyncActionKind.inSync);
      expect(k('a', null, null), SyncActionKind.upload);
      expect(k(null, 'a', null), SyncActionKind.download);
      expect(k('a', 'b', null), SyncActionKind.conflict);
      expect(k('a', 'b', 'a'), SyncActionKind.download);
      expect(k('b', 'a', 'a'), SyncActionKind.upload);
      expect(k('a', null, 'a'), SyncActionKind.remoteDeletedKept);
      expect(k(null, 'a', 'a'), SyncActionKind.localMissingKept);
      expect(k(null, 'b', 'a'), SyncActionKind.download);
      expect(k('b', null, 'a'), SyncActionKind.upload);
      expect(k('b', 'c', 'a'), SyncActionKind.conflict);
      expect(k(null, null, 'a'), SyncActionKind.forget);
    });

    test('never plans a deletion', () {
      // There is no delete action kind at all.
      expect(
        SyncActionKind.values
            .map((e) => e.name)
            .any((n) => n.contains('delete') && !n.contains('Kept')),
        isFalse,
      );
    });
  });

  late MemoryVaultStorage storage;
  late FakeGitHub gh;
  late RecordingHistory history;
  late SyncBase base;
  var now = DateTime(2026, 10, 18, 9, 5);

  SyncEngine engine() => SyncEngine(
    vault: vault,
    storage: storage,
    history: history,
    client: gh.client(),
    branch: 'main',
    clock: () => now,
  );
  String? local(String p) =>
      storage.bytesOf(p) == null ? null : utf8.decode(storage.bytesOf(p)!);

  setUp(() {
    history = RecordingHistory();
    base = SyncBase.empty();
  });

  test('first sync: upload, download, identical, conflict copy', () async {
    storage = MemoryVaultStorage(
      files: {
        'Only here.md': 'L',
        'Same.md': 'same',
        'Both.md': 'phone version',
      },
      remembered: vault,
    );
    gh = FakeGitHub(
      files: {
        'Projects/Only there.md': 'R',
        'Same.md': 'same',
        'Both.md': 'github version',
        'README': 'not markdown',
        '.obsidian/workspace.md': 'hidden',
        'image.png': 'binary',
      },
    );
    final r = await engine().run(base);
    expect(r.fatal, isNull);
    expect(r.failures, isEmpty);
    expect(gh.text('Only here.md'), 'L');
    expect(local('Projects/Only there.md'), 'R');
    expect(r.unchanged, 1);
    expect(local('Both.md'), 'phone version'); // never overwritten
    expect(gh.text('Both.md'), 'github version');
    expect(
      r.conflicts.single.copyPath,
      'Both (GitHub conflict 2026-10-18 0905).md',
    );
    expect(
      local('Both (GitHub conflict 2026-10-18 0905).md'),
      'github version',
    );
    // Hidden and non-Markdown remote files are ignored.
    expect(local('.obsidian/workspace.md'), isNull);
    expect(local('image.png'), isNull);
    expect(base.lastSync, now);

    // Second sync: the user's version and the conflict copy are uploaded.
    final r2 = await engine().run(base);
    expect(r2.conflicts, isEmpty);
    expect(r2.uploaded, 2);
    expect(gh.text('Both.md'), 'phone version');
    expect(
      gh.text('Both (GitHub conflict 2026-10-18 0905).md'),
      'github version',
    );

    // Third sync: nothing to do.
    final commits = gh.commits.length;
    final r3 = await engine().run(base);
    expect(r3.uploaded + r3.downloaded, 0);
    expect(gh.commits.length, commits);
  });

  test('one-sided edits flow both ways; overwrites keep history', () async {
    storage = MemoryVaultStorage(
      files: {'A.md': 'a1', 'B.md': 'b1'},
      remembered: vault,
    );
    gh = FakeGitHub(files: {'A.md': 'a1', 'B.md': 'b1'});
    await engine().run(base);

    storage.setFile('A.md', 'a2 from phone');
    gh.set('B.md', 'b2 from github');
    final r = await engine().run(base);
    expect(r.uploaded, 1);
    expect(r.downloaded, 1);
    expect(gh.text('A.md'), 'a2 from phone');
    expect(local('B.md'), 'b2 from github');
    expect(history.recorded, ['B.md=b1']);
    expect(gh.commits.last, 'Update A.md (Emerald sync)');
  });

  test('deletions are never propagated', () async {
    storage = MemoryVaultStorage(
      files: {'Gone remote.md': 'x', 'Gone local.md': 'y'},
      remembered: vault,
    );
    gh = FakeGitHub(files: {'Gone remote.md': 'x', 'Gone local.md': 'y'});
    await engine().run(base);
    gh.files.remove('Gone remote.md');
    storage.deleteExternally('Gone local.md');
    final r = await engine().run(base);
    expect(local('Gone remote.md'), 'x'); // local kept
    expect(gh.text('Gone local.md'), 'y'); // remote kept
    expect(gh.text('Gone remote.md'), isNull); // not re-uploaded either
    expect(r.notices, hasLength(2));
    expect(r.uploaded + r.downloaded, 0);

    // Editing the kept local note later uploads it again.
    storage.setFile('Gone remote.md', 'x2');
    await engine().run(base);
    expect(gh.text('Gone remote.md'), 'x2');
  });

  test('remote change during upload is not overwritten', () async {
    storage = MemoryVaultStorage(files: {'A.md': 'v1'}, remembered: vault);
    gh = FakeGitHub(files: {'A.md': 'v1'});
    await engine().run(base);
    storage.setFile('A.md', 'phone v2');
    gh.beforePut = (p) => gh.set(p, 'github v2 (concurrent)');
    final r = await engine().run(base);
    expect(r.failures.single, contains('changed on GitHub'));
    expect(gh.text('A.md'), 'github v2 (concurrent)');
    expect(local('A.md'), 'phone v2');
    gh.beforePut = null;
    // Next sync sees both changed → conflict copy, nothing lost.
    final r2 = await engine().run(base);
    expect(r2.conflicts.single.path, 'A.md');
    expect(local('A.md'), 'phone v2');
  });

  test('corrupted download is rejected and nothing is written', () async {
    storage = MemoryVaultStorage(files: {'A.md': 'v1'}, remembered: vault);
    gh = FakeGitHub(files: {'A.md': 'v1'});
    await engine().run(base);
    gh.set('A.md', 'v2');
    gh.corruptBlob = base.files.isEmpty
        ? null
        : (await gh.client().listFiles('main')).single.sha;
    final r = await engine().run(base);
    expect(r.failures.single, contains('unexpected'));
    expect(local('A.md'), 'v1');
  });

  test('fatal errors stop the sync and leave notes unchanged', () async {
    storage = MemoryVaultStorage(files: {'A.md': 'v1'}, remembered: vault);
    gh = FakeGitHub()..failStatus = 401;
    final r = await engine().run(base);
    expect(r.fatal!.code, SyncErrorCode.unauthorized);
    expect(base.lastSync, isNull);
    expect(local('A.md'), 'v1');
  });

  test(
    'empty repository is reported, not treated as "delete everything"',
    () async {
      storage = MemoryVaultStorage(files: {'A.md': 'v1'}, remembered: vault);
      gh = FakeGitHub()..empty = true;
      final r = await engine().run(base);
      expect(r.fatal!.code, SyncErrorCode.emptyRepository);
      expect(local('A.md'), 'v1');
    },
  );

  test(
    'local file edited between compare and write is not overwritten',
    () async {
      storage = MemoryVaultStorage(files: {'A.md': 'v1'}, remembered: vault);
      gh = FakeGitHub(files: {'A.md': 'v1'});
      await engine().run(base);
      gh.set('A.md', 'v2');
      // Simulate an edit landing right after the comparison: the stat cache
      // sees no change, but the write path re-reads and verifies.
      final cached = base.files['A.md']!;
      storage.setFile('A.md', 'edited meanwhile');
      final e = storage.bytesOf('A.md')!;
      base.files['A.md'] = SyncedFile(
        sha: cached.sha,
        size: e.length,
        lastModified: (await storage.listTree(vault)).single.lastModified,
      );
      final r = await engine().run(base);
      expect(local('A.md'), 'edited meanwhile');
      expect(r.failures.single, contains('changed during sync'));
    },
  );

  test('state store round trip', () async {
    final s = MemorySyncStateStore();
    await s.save(
      'x',
      SyncBase({
        'a.md': const SyncedFile(sha: 's', size: 1, lastModified: 2),
      }, lastSync: now),
    );
    final b = await s.load('x');
    expect(b.files['a.md']!.sha, 's');
    expect(b.lastSync, now);
    expect((await s.load('other')).files, isEmpty);
  });
}
