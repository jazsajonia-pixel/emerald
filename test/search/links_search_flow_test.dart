import 'package:emerald/data/memory_vault_storage.dart';
import 'package:emerald/data/vault_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

const _vault = VaultHandle(id: 'memory://vault', name: 'Vault');

MemoryVaultStorage _storage() => MemoryVaultStorage(
  files: {
    'Start.md':
        '# Start\n\nBegin at [[Projects/Emerald|the app]]. Also [[Ghost]].',
    'Projects/Emerald.md': 'Emerald is a graph app.',
    'Recipes.md': 'Pancakes with maple syrup.',
  },
  vaultToPick: _vault,
  remembered: _vault,
);

Future<void> _brain(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Brain'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search finds notes by content and opens them', (tester) async {
    await pumpEmerald(tester, storage: _storage());
    await _brain(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), 'maple');
    await tester.pumpAndSettle();
    expect(find.text('Recipes'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
    await tester.tap(find.text('Recipes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pancakes'), findsOneWidget);
  });

  testWidgets('search with no results shows an empty state', (tester) async {
    await pumpEmerald(tester, storage: _storage());
    await _brain(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching notes'), findsOneWidget);
  });

  testWidgets('backlinks sheet lists linking notes and broken links', (
    tester,
  ) async {
    await pumpEmerald(tester, storage: _storage());
    await _brain(tester);
    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emerald'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Note actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Links and backlinks'));
    await tester.pumpAndSettle();
    expect(find.text('Backlinks (1)'), findsOneWidget);
    expect(find.text('Start.md'), findsOneWidget);
    await tester.tap(find.text('Start.md'));
    await tester.pumpAndSettle();
    // Now in Start: its outgoing links include a broken one.
    await tester.tap(find.byTooltip('Note actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Links and backlinks'));
    await tester.pumpAndSettle();
    expect(find.text('Broken link: no such note'), findsOneWidget);
  });

  testWidgets('tapping a wiki link in preview opens the target note', (
    tester,
  ) async {
    await pumpEmerald(tester, storage: _storage());
    await _brain(tester);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();
    final link = find.textContaining('the app', findRichText: true);
    expect(link, findsWidgets);
    await tester.tapOnText(find.textRange.ofSubstring('the app'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Emerald is a graph app.'), findsOneWidget);
  });

  testWidgets('unlinked notes screen lists orphans', (tester) async {
    await pumpEmerald(tester, storage: _storage());
    await _brain(tester);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlinked notes'));
    await tester.pumpAndSettle();
    expect(find.text('Orphan notes (1)'), findsOneWidget);
    expect(find.text('Recipes'), findsOneWidget);
    expect(find.text('Notes with broken links (1)'), findsOneWidget);
  });

  testWidgets('saving a new link updates backlinks without a rescan', (
    tester,
  ) async {
    await pumpEmerald(tester, storage: _storage());
    await _brain(tester);
    await tester.tap(find.text('Recipes'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('note-editor')),
      'Pancakes. See [[Start]].',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Note actions').last);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Links and backlinks'));
    await tester.pumpAndSettle();
    expect(find.text('Backlinks (1)'), findsOneWidget);
    expect(find.text('Recipes.md'), findsOneWidget);
  });
}
