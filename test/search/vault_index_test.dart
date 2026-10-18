import 'package:sapphire/features/search/vault_index.dart';
import 'package:flutter_test/flutter_test.dart';

VaultIndex build(Map<String, String> files) => VaultIndex({
  for (final e in files.entries)
    e.key: IndexedNote(
      path: e.key,
      text: e.value,
      lastModified: 1,
      size: e.value.length,
    ),
});

void main() {
  final idx = build({
    'Home.md':
        'Welcome. See [[Sapphire]] and [plan](Projects/Plan.md). [[Ghost]]',
    'Projects/Sapphire.md': 'Graph app. Back to [[Home]]. Self [[Sapphire]].',
    'Projects/Plan.md': 'Phases and milestones for the graph.',
    'Lonely.md': 'Nobody links here. Café crème.',
    'Ideen/Grüße.md': '日本語のメモ and [[Lonely Typo]]',
  });

  test('backlinks are consistent with links', () {
    expect(idx.backlinks('Projects/Sapphire.md'), ['Home.md']);
    expect(idx.backlinks('Home.md'), ['Projects/Sapphire.md']);
    expect(idx.backlinks('Projects/Plan.md'), ['Home.md']);
    expect(idx.backlinks('Lonely.md'), isEmpty);
    for (final (s, t) in idx.edges) {
      expect(idx.backlinks(t), contains(s));
    }
  });

  test('self-links are not edges or backlinks', () {
    expect(idx.linkedTargets('Projects/Sapphire.md'), {'Home.md'});
  });

  test('broken links are reported', () {
    expect(idx.brokenLinks('Home.md').map((r) => r.link.target), ['Ghost']);
    expect(idx.brokenLinks('Ideen/Grüße.md').map((r) => r.link.target), [
      'Lonely Typo',
    ]);
  });

  test('orphans have no links in or out', () {
    expect(idx.orphans, ['Ideen/Grüße.md', 'Lonely.md']);
  });

  test('search: title beats content, all terms must match', () {
    final hits = idx.search('graph');
    expect(hits.map((h) => h.path).toSet(), {
      'Projects/Sapphire.md',
      'Projects/Plan.md',
    });
    expect(idx.search('sapphire').first.path, 'Projects/Sapphire.md');
    expect(idx.search('graph milestones').single.path, 'Projects/Plan.md');
    expect(idx.search('graph nonexistentword'), isEmpty);
    expect(idx.search('   '), isEmpty);
  });

  test('search is case-insensitive and Unicode-aware', () {
    expect(idx.search('CAFÉ').single.path, 'Lonely.md');
    expect(idx.search('日本語').single.path, 'Ideen/Grüße.md');
    expect(idx.search('grüße').single.path, 'Ideen/Grüße.md');
  });

  test('search matches folder names and provides snippets', () {
    expect(idx.search('ideen').single.path, 'Ideen/Grüße.md');
    expect(idx.search('milestones').single.snippet, contains('milestones'));
  });

  test('duplicate note names both index and resolve deterministically', () {
    final dup = build({
      'A/Note.md': 'a',
      'B/Note.md': 'b',
      'A/Src.md': '[[Note]]',
    });
    expect(dup.linkedTargets('A/Src.md'), {'A/Note.md'});
    expect(dup.backlinks('B/Note.md'), isEmpty);
    expect(dup.search('note'), hasLength(3));
  });

  test('empty index', () {
    expect(VaultIndex.empty.search('x'), isEmpty);
    expect(VaultIndex.empty.orphans, isEmpty);
    expect(VaultIndex.empty.edges, isEmpty);
  });
}
