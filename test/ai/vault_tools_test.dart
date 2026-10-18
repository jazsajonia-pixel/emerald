import 'dart:convert';

import 'package:sapphire/data/memory_vault_storage.dart';
import 'package:sapphire/data/vault_storage.dart';
import 'package:sapphire/features/ai/ai_types.dart';
import 'package:sapphire/features/ai/proposals.dart';
import 'package:sapphire/features/ai/tools/vault_tools.dart';
import 'package:sapphire/features/notes/note_history.dart';
import 'package:sapphire/features/notes/note_repository.dart';
import 'package:sapphire/features/search/vault_index.dart';
import 'package:flutter_test/flutter_test.dart';

const vault = VaultHandle(id: 'memory://vault', name: 'V');

void main() {
  late MemoryVaultStorage storage;
  late NoteRepository repo;
  late VaultTools tools;
  var ids = 0;

  final files = {
    'Home.md': 'Start [[Sapphire]] and [[Plan]].',
    'Projects/Sapphire.md': 'Graph app. [[Plan]]',
    'Projects/Plan.md': 'Milestones.',
    'Other.md': 'Links [[Plan]] too.',
  };

  setUp(() {
    storage = MemoryVaultStorage(files: files, remembered: vault);
    storage.setFile('notes.txt', 'not markdown');
    repo = NoteRepository(storage, const NoHistory());
    tools = VaultTools(
      vault: vault,
      index: VaultIndex({
        for (final e in files.entries)
          e.key: IndexedNote(
            path: e.key,
            text: e.value,
            lastModified: 1,
            size: 1,
          ),
      }),
      repository: repo,
      nextProposalId: () => ++ids,
    );
  });

  Future<JsonMap> run(String name, JsonMap args) =>
      tools.execute(ToolCall(id: 'x', name: name, args: args));

  test('specs have unique names and object schemas', () {
    final names = VaultTools.specs.map((s) => s.name).toList();
    expect(names.toSet().length, names.length);
    expect(
      names,
      containsAll([
        'search_notes',
        'list_notes',
        'read_note',
        'find_backlinks',
        'find_related_notes',
        'create_note',
        'update_note',
      ]),
    );
    expect(names.any((n) => n.contains('delete')), isFalse);
    for (final s in VaultTools.specs) {
      expect(s.parameters['type'], 'object');
    }
  });

  test('search and list', () async {
    final r = await run('search_notes', {'query': 'milestones'});
    expect((r['results'] as List).single['path'], 'Projects/Plan.md');
    final l = await run('list_notes', {'folder': 'Projects'});
    expect(l['notes'], ['Projects/Plan.md', 'Projects/Sapphire.md']);
    expect(tools.sharedNotes, isEmpty); // titles/paths only, no content
  });

  test('read_note returns content and records what was shared', () async {
    final r = await run('read_note', {'path': 'Projects/Plan.md'});
    expect(r['content'], 'Milestones.');
    expect(tools.sharedNotes, {'Projects/Plan.md'});
    // Bare title and missing extension are accepted when unambiguous.
    expect(
      (await run('read_note', {'path': 'Sapphire'}))['path'],
      'Projects/Sapphire.md',
    );
    expect(
      (await run('read_note', {'path': 'Projects/Plan'}))['path'],
      'Projects/Plan.md',
    );
  });

  test('read_note truncates very long notes', () async {
    final t = VaultTools(
      vault: vault,
      index: VaultIndex({
        'Long.md': IndexedNote(
          path: 'Long.md',
          text: '',
          lastModified: 1,
          size: 1,
        ),
      }),
      repository: repo,
      nextProposalId: () => 1,
      maxReadChars: 10,
    );
    storage.setFile('Long.md', 'x' * 50);
    final r = await t.execute(
      const ToolCall(id: 'a', name: 'read_note', args: {'path': 'Long.md'}),
    );
    expect((r['content'] as String).length, 10);
    expect(r['truncated'], isTrue);
  });

  test('cannot escape the vault or read non-notes', () async {
    for (final bad in [
      '../secret.md',
      '/etc/passwd',
      '.obsidian/app.json',
      'notes.txt',
      'Missing.md',
      'Projects/../../x.md',
    ]) {
      final r = await run('read_note', {'path': bad});
      expect(r['error'], isNotNull, reason: bad);
    }
    expect((await run('list_notes', {'folder': '../'}))['error'], isNotNull);
    expect(tools.sharedNotes, isEmpty);
  });

  test('backlinks and related notes are based on explicit links', () async {
    expect(
      (await run('find_backlinks', {'path': 'Projects/Plan.md'}))['backlinks'],
      ['Home.md', 'Other.md', 'Projects/Sapphire.md'],
    );
    final rel = await run('find_related_notes', {'path': 'Other.md'});
    expect(rel['links_to'], ['Projects/Plan.md']);
    expect(
      rel['shares_links_with'],
      containsAll(['Home.md', 'Projects/Sapphire.md']),
    );
  });

  test('create_note and update_note only record proposals', () async {
    final before = {
      for (final p in files.keys) p: utf8.decode(storage.bytesOf(p)!),
    };
    final c = await run('create_note', {
      'folder': 'Projects',
      'title': 'Ideas',
      'content': '# Ideas',
    });
    expect(c['status'], 'pending_user_approval');
    final u = await run('update_note', {
      'path': 'Projects/Plan.md',
      'new_content': 'Milestones.\n- M1',
    });
    expect(u['status'], 'pending_user_approval');
    expect(storage.bytesOf('Projects/Ideas.md'), isNull);
    for (final e in before.entries) {
      expect(utf8.decode(storage.bytesOf(e.key)!), e.value);
    }
    expect(tools.proposals.map((p) => p.kind), [
      ProposalKind.create,
      ProposalKind.update,
    ]);
    expect(tools.proposals.last.oldText, 'Milestones.');
    expect(tools.proposals.last.baseSha256, isNotNull);
  });

  test('create_note refuses existing notes and unsafe titles', () async {
    expect(
      (await run('create_note', {'title': 'Home', 'content': 'x'}))['error'],
      contains('already exists'),
    );
    expect(
      (await run('create_note', {'title': '   ', 'content': 'x'}))['error'],
      isNotNull,
    );
    expect(
      (await run('create_note', {
        'folder': '../up',
        'title': 'x',
        'content': 'x',
      }))['error'],
      isNotNull,
    );
  });

  test('update with identical content is a no-op', () async {
    final r = await run('update_note', {
      'path': 'Projects/Plan.md',
      'new_content': 'Milestones.',
    });
    expect(r['status'], 'no_change');
    expect(tools.proposals, isEmpty);
  });

  test('proposal limit', () async {
    for (var i = 0; i < 10; i++) {
      await run('create_note', {'title': 'N$i', 'content': ''});
    }
    expect(
      (await run('create_note', {'title': 'Eleven', 'content': ''}))['error'],
      contains('Too many'),
    );
  });

  test(
    'bad arguments and unknown tools return errors instead of throwing',
    () async {
      expect((await run('read_note', {}))['error'], isNotNull);
      expect((await run('search_notes', {'query': 5}))['error'], isNotNull);
      expect(
        (await run('delete_note', {'path': 'Home.md'}))['error'],
        contains('Unknown tool'),
      );
    },
  );

  group('ProposalApplier', () {
    test('applies update, refuses if the note changed since', () async {
      await run('update_note', {
        'path': 'Projects/Plan.md',
        'new_content': 'v2',
      });
      final p = tools.proposals.single;
      storage.setFile('Projects/Plan.md', 'edited elsewhere');
      await expectLater(
        ProposalApplier(repo).apply(vault, p),
        throwsA(
          isA<VaultException>().having(
            (e) => e.code,
            'code',
            VaultErrorCode.conflict,
          ),
        ),
      );
      expect(
        utf8.decode(storage.bytesOf('Projects/Plan.md')!),
        'edited elsewhere',
      );
    });

    test('applies update and create', () async {
      await run('update_note', {
        'path': 'Projects/Plan.md',
        'new_content': 'v2',
      });
      await run('create_note', {'title': 'Fresh', 'content': 'hello'});
      for (final p in tools.proposals) {
        await ProposalApplier(repo).apply(vault, p);
      }
      expect(utf8.decode(storage.bytesOf('Projects/Plan.md')!), 'v2');
      expect(utf8.decode(storage.bytesOf('Fresh.md')!), 'hello');
    });

    test('create never overwrites a note created meanwhile', () async {
      await run('create_note', {'title': 'Race', 'content': 'ai'});
      storage.setFile('Race.md', 'user');
      await expectLater(
        ProposalApplier(repo).apply(vault, tools.proposals.single),
        throwsA(isA<VaultException>()),
      );
      expect(utf8.decode(storage.bytesOf('Race.md')!), 'user');
    });
  });
}
