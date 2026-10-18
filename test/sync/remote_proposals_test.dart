import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:emerald/data/memory_vault_storage.dart';
import 'package:emerald/data/vault_storage.dart';
import 'package:emerald/features/ai/proposals.dart';
import 'package:emerald/features/notes/note_repository.dart';
import 'package:emerald/features/sync/git_hash.dart';
import 'package:emerald/features/sync/github_client.dart';
import 'package:emerald/features/sync/remote_proposals.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_github.dart';
import 'sync_engine_test.dart' show RecordingHistory;

const vault = VaultHandle(id: 'memory://vault', name: 'V');

String sha(String s) => gitBlobSha(Uint8List.fromList(utf8.encode(s)));

String proposalJson({
  required String id,
  required String kind,
  required String path,
  required String content,
  String? baseSha,
  String summary = 'Why',
}) => jsonEncode({
  'format': 'emerald-proposal',
  'version': 1,
  'id': id,
  'createdAt': '2026-10-18T09:15:00.000Z',
  'kind': kind,
  'path': path,
  'baseSha': baseSha,
  'content': content,
  'summary': summary,
  'client': null,
});

void main() {
  late FakeGitHub gh;
  late MemoryVaultStorage storage;
  late RecordingHistory history;
  late RemoteProposalInbox inbox;

  setUp(() {
    gh = FakeGitHub(files: {'Garden.md': '# Garden\n', 'Plan.md': 'v1\n'});
    storage = MemoryVaultStorage(
      files: {'Garden.md': '# Garden\n', 'Plan.md': 'v1\n'},
      remembered: vault,
    );
    history = RecordingHistory();
    inbox = RemoteProposalInbox(
      client: gh.client(),
      branch: 'main',
      vault: vault,
      storage: storage,
      repository: NoteRepository(storage, history),
    );
  });

  void propose(String name, String json) =>
      gh.set('.emerald/proposals/$name.json', json);

  Future<String> local(String path) async =>
      utf8.decode((await storage.readFile(vault, path)).bytes);

  group('RemoteProposal.parse', () {
    Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

    test('accepts a valid update and create', () {
      final u = RemoteProposal.parse(
        b(
          proposalJson(
            id: 'a',
            kind: 'update',
            path: 'F/N.md',
            content: 'x',
            baseSha: 'a' * 40,
          ),
        ),
      )!;
      expect(u.kind, ProposalKind.update);
      expect(u.path, 'F/N.md');
      expect(u.createdAt, DateTime.utc(2026, 10, 18, 9, 15));
      expect(
        RemoteProposal.parse(
          b(proposalJson(id: 'b', kind: 'create', path: 'N.md', content: 'x')),
        )!.kind,
        ProposalKind.create,
      );
    });

    test('parses the file the MCP server writes (shared fixture)', () {
      // Same fixture as mcp-server/test/e2e.test.ts asserts the server
      // output against.
      final f = File('mcp-server/test/fixtures/proposal-v1.json');
      final p = RemoteProposal.parse(f.readAsBytesSync())!;
      expect(p.id, '20261018T091500Z-00000000');
      expect(p.kind, ProposalKind.update);
      expect(p.path, 'Projects/Plan.md');
      expect(p.baseSha, '5c2c2d0f1c3c5b6b3e0e6f6e1e8c1d0b5a8f6f9e');
      expect(p.content, '# Plan\n\nSee [[Garden]].\n\n## Next\n- water\n');
      expect(p.summary, 'Add a Next section');
      expect(p.createdAt, DateTime.utc(2026, 10, 18, 9, 15));
      expect(p.client, isNull);
    });

    test('rejects unsafe paths, wrong format and missing base', () {
      for (final path in [
        '../x.md',
        '.obsidian/x.md',
        '/abs.md',
        'x.txt',
        'a//b.md',
        '.emerald/proposals/x.md',
      ]) {
        expect(
          RemoteProposal.parse(
            b(proposalJson(id: 'a', kind: 'create', path: path, content: 'x')),
          ),
          isNull,
          reason: path,
        );
      }
      expect(RemoteProposal.parse(b('not json')), isNull);
      expect(RemoteProposal.parse(b('{"format":"x","version":1}')), isNull);
      expect(
        RemoteProposal.parse(
          b(proposalJson(id: 'a', kind: 'update', path: 'N.md', content: 'x')),
        ),
        isNull,
        reason: 'update without baseSha',
      );
      expect(
        RemoteProposal.parse(
          b(proposalJson(id: 'a', kind: 'delete', path: 'N.md', content: '')),
        ),
        isNull,
        reason: 'no delete kind',
      );
    });
  });

  test('lists only proposal files and classifies them', () async {
    propose(
      '1',
      proposalJson(
        id: '1',
        kind: 'update',
        path: 'Plan.md',
        content: 'v2\n',
        baseSha: sha('v1\n'),
      ),
    );
    propose(
      '2',
      proposalJson(
        id: '2',
        kind: 'update',
        path: 'Garden.md',
        content: 'new\n',
        baseSha: sha('older\n'),
      ),
    );
    propose(
      '3',
      proposalJson(id: '3', kind: 'create', path: 'Ideas/New.md', content: 'i'),
    );
    propose(
      '4',
      proposalJson(id: '4', kind: 'create', path: 'Garden.md', content: 'dup'),
    );
    propose('5', 'garbage');
    gh.set('.emerald/other.json', '{}');
    gh.set('.emerald/proposals/nested/6.json', '{}');

    final items = await inbox.load();
    expect(items.map((i) => i.file.path), [
      '.emerald/proposals/1.json',
      '.emerald/proposals/2.json',
      '.emerald/proposals/3.json',
      '.emerald/proposals/4.json',
      '.emerald/proposals/5.json',
    ]);
    expect(items.map((i) => i.state), [
      InboxItemState.ready,
      InboxItemState.stale,
      InboxItemState.ready,
      InboxItemState.stale,
      InboxItemState.invalid,
    ]);
    expect(items[0].note!.oldText, 'v1\n');
    expect(items[0].note!.newText, 'v2\n');
    expect(items[1].reason, contains('differs from the version the AI read'));
    expect(items[3].reason, contains('already exists'));
    expect(gh.commits, isEmpty, reason: 'loading changes nothing');
  });

  test(
    'approve updates the note with history and removes the proposal',
    () async {
      propose(
        '1',
        proposalJson(
          id: '1',
          kind: 'update',
          path: 'Plan.md',
          content: 'v2\n',
          baseSha: sha('v1\n'),
        ),
      );
      final item = (await inbox.load()).single;
      await inbox.approve(item);
      expect(await local('Plan.md'), 'v2\n');
      expect(history.recorded, ['Plan.md=v1\n']);
      expect(gh.files.containsKey('.emerald/proposals/1.json'), isFalse);
      expect(
        gh.text('Plan.md'),
        'v1\n',
        reason: 'GitHub note changes on next sync',
      );
      expect(gh.commits.single, startsWith('Approved in Emerald: Plan.md'));
    },
  );

  test('approve creates a note in a new folder', () async {
    propose(
      '1',
      proposalJson(id: '1', kind: 'create', path: 'Ideas/New.md', content: 'i'),
    );
    await inbox.approve((await inbox.load()).single);
    expect(await local('Ideas/New.md'), 'i');
    expect(gh.files.containsKey('.emerald/proposals/1.json'), isFalse);
  });

  test('approve refuses if the note changed after loading', () async {
    propose(
      '1',
      proposalJson(
        id: '1',
        kind: 'update',
        path: 'Plan.md',
        content: 'v2\n',
        baseSha: sha('v1\n'),
      ),
    );
    final item = (await inbox.load()).single;
    storage.setFile('Plan.md', 'edited on phone\n');
    await expectLater(
      inbox.approve(item),
      throwsA(
        isA<VaultException>().having(
          (e) => e.code,
          'code',
          VaultErrorCode.conflict,
        ),
      ),
    );
    expect(await local('Plan.md'), 'edited on phone\n');
    expect(gh.files.containsKey('.emerald/proposals/1.json'), isTrue);
  });

  test(
    'stale items cannot be approved; reject removes only the proposal',
    () async {
      propose(
        '1',
        proposalJson(
          id: '1',
          kind: 'update',
          path: 'Garden.md',
          content: 'x',
          baseSha: sha('older'),
        ),
      );
      final item = (await inbox.load()).single;
      expect(() => inbox.approve(item), throwsStateError);
      await inbox.dismiss(item);
      expect(gh.files.containsKey('.emerald/proposals/1.json'), isFalse);
      expect(await local('Garden.md'), '# Garden\n');
      expect(gh.commits.single, startsWith('Rejected in Emerald'));
    },
  );

  test(
    'if removal fails after saving, the item comes back as already applied',
    () async {
      propose(
        '1',
        proposalJson(
          id: '1',
          kind: 'update',
          path: 'Plan.md',
          content: 'v2\n',
          baseSha: sha('v1\n'),
        ),
      );
      final item = (await inbox.load()).single;
      // The remote SHA is checked before the local write, so this race hook
      // changes it only after the note has been safely saved.
      var changed = false;
      gh.beforeDelete = (path) {
        if (!changed && path == '.emerald/proposals/1.json') {
          changed = true;
          final original = gh.text(path)!;
          gh.set(path, '$original ');
        }
      };
      await expectLater(inbox.approve(item), throwsA(anything));
      expect(await local('Plan.md'), 'v2\n', reason: 'note stays saved');
      final again = (await inbox.load()).single;
      expect(again.state, InboxItemState.alreadyApplied);
      await inbox.dismiss(again);
      expect(gh.files.containsKey('.emerald/proposals/1.json'), isFalse);
    },
  );

  test('changed remote proposal is rejected before writing locally', () async {
    propose(
      '1',
      proposalJson(
        id: '1',
        kind: 'update',
        path: 'Plan.md',
        content: 'v2\n',
        baseSha: sha('v1\n'),
      ),
    );
    final item = (await inbox.load()).single;
    gh.set(
      '.emerald/proposals/1.json',
      proposalJson(
        id: '1',
        kind: 'update',
        path: 'Plan.md',
        content: 'changed remotely\n',
        baseSha: sha('v1\n'),
      ),
    );
    await expectLater(
      inbox.approve(item),
      throwsA(
        isA<SyncException>().having(
          (e) => e.code,
          'code',
          SyncErrorCode.remoteChanged,
        ),
      ),
    );
    expect(await local('Plan.md'), 'v1\n');
  });

  test(
    'batch approves ready items sequentially and reports partial failure',
    () async {
      propose(
        '1',
        proposalJson(
          id: '1',
          kind: 'update',
          path: 'Plan.md',
          content: 'v2\n',
          baseSha: sha('v1\n'),
        ),
      );
      propose(
        '2',
        proposalJson(
          id: '2',
          kind: 'update',
          path: 'Garden.md',
          content: 'garden v2\n',
          baseSha: sha('# Garden\n'),
        ),
      );
      final items = await inbox.load();
      gh.beforeDelete = (path) {
        if (path == '.emerald/proposals/2.json') {
          gh.set(path, '${gh.text(path)!} ');
        }
      };

      final result = await inbox.approveAllReady(items);

      expect(result.attempted, 2);
      expect(result.approved, ['Plan.md']);
      expect(result.written, ['Plan.md', 'Garden.md']);
      expect(result.failures.single.path, 'Garden.md');
      expect(await local('Plan.md'), 'v2\n');
      expect(await local('Garden.md'), 'garden v2\n');
      expect(history.recorded, ['Plan.md=v1\n', 'Garden.md=# Garden\n']);
    },
  );

  test('a GitHub note never changes from the inbox (no note writes)', () async {
    propose(
      '1',
      proposalJson(id: '1', kind: 'create', path: 'N.md', content: 'n'),
    );
    await inbox.approve((await inbox.load()).single);
    final notePuts = gh.requests.where(
      (r) =>
          (r.method == 'PUT' || r.method == 'DELETE') &&
          !r.url.path.contains('/contents/.emerald/proposals/'),
    );
    expect(notePuts, isEmpty);
  });
}
