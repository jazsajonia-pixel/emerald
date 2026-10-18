import 'package:emerald/data/memory_vault_storage.dart';
import 'package:emerald/data/vault_storage.dart';
import 'package:emerald/features/graph/graph_screen.dart';
import 'package:emerald/features/graph/graph_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

const _vault = VaultHandle(id: 'memory://vault', name: 'Vault');

MemoryVaultStorage _storage() => MemoryVaultStorage(
  files: {
    'Alpha.md': 'Links to [[Beta]] and [[Gamma]].',
    'Beta.md': 'Back to [[Alpha]].',
    'Gamma.md': 'Gamma text.',
    'Lonely.md': 'No links.',
  },
  vaultToPick: _vault,
  remembered: _vault,
);

Future<void> _graph(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Graph'),
    ),
  );
  await tester.pumpAndSettle();
}

/// Global screen position of the node with [title], using the painter's
/// layout through the GraphView widget.
Offset _nodePosition(WidgetTester tester, String title) {
  final view = tester.widget<GraphView>(find.byType(GraphView));
  final i = view.data.nodes.indexWhere((n) => n.title == title);
  expect(i, isNot(-1), reason: 'node $title');
  final box = tester.renderObject<RenderBox>(find.byKey(GraphView.canvasKey));
  return box.localToGlobal(Offset(view.layout.x(i), view.layout.y(i)));
}

void main() {
  testWidgets('global graph shows all notes and explicit links', (
    tester,
  ) async {
    await pumpEmerald(tester, storage: _storage());
    await _graph(tester);
    expect(find.byType(GraphView), findsOneWidget);
    expect(find.text('4 notes · 2 links'), findsOneWidget);
    expect(find.textContaining('AI-suggested links: off'), findsOneWidget);
  });

  testWidgets('tapping a node offers actions and opens the selected note', (tester) async {
    await pumpEmerald(tester, storage: _storage());
    await _graph(tester);
    await tester.tapAt(_nodePosition(tester, 'Gamma'));
    await tester.pumpAndSettle();
    expect(find.text('Focus local graph'), findsOneWidget);
    expect(find.text('Pin node'), findsOneWidget);
    await tester.tap(find.byKey(const Key('graph-node-open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Gamma text.'), findsOneWidget);
  });

  testWidgets('pin action marks a node in the graph legend', (tester) async {
    await pumpEmerald(tester, storage: _storage());
    await _graph(tester);
    await tester.tapAt(_nodePosition(tester, 'Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('graph-node-pin')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 pinned'), findsOneWidget);
  });

  testWidgets('long-press opens the local graph; back returns to global', (
    tester,
  ) async {
    await pumpEmerald(tester, storage: _storage());
    await _graph(tester);
    await tester.longPressAt(_nodePosition(tester, 'Beta'));
    await tester.pumpAndSettle();
    expect(find.text('Local: Beta'), findsOneWidget);
    expect(find.text('2 notes · 1 links'), findsOneWidget);
    await tester.tap(find.byTooltip('Graph options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Links of links'));
    await tester.pumpAndSettle();
    expect(find.text('3 notes · 2 links'), findsOneWidget);
    await tester.tap(find.byTooltip('Global graph'));
    await tester.pumpAndSettle();
    expect(find.text('4 notes · 2 links'), findsOneWidget);
  });

  testWidgets('hide unlinked notes filter', (tester) async {
    await pumpEmerald(tester, storage: _storage());
    await _graph(tester);
    await tester.tap(find.byTooltip('Graph options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show unlinked notes'));
    await tester.pumpAndSettle();
    expect(find.text('3 notes · 2 links'), findsOneWidget);
  });

  testWidgets('search highlights matching nodes', (tester) async {
    await pumpEmerald(tester, storage: _storage());
    await _graph(tester);
    await tester.tap(find.byTooltip('Highlight notes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('graph-search')), 'a');
    await tester.pumpAndSettle();
    expect(find.text('4 notes · 2 links · 3 highlighted'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('graph-search')), 'gam');
    await tester.pumpAndSettle();
    expect(find.text('4 notes · 2 links · 1 highlighted'), findsOneWidget);
  });

  testWidgets('graph updates after a note gains a link', (tester) async {
    await pumpEmerald(tester, storage: _storage());
    await _graph(tester);
    expect(find.text('4 notes · 2 links'), findsOneWidget);
    await tester.tapAt(_nodePosition(tester, 'Lonely'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('graph-node-open')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('note-editor')),
      'Now [[Gamma]]',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('4 notes · 3 links'), findsOneWidget);
  });

  testWidgets('graph updates after an external edit and rescan', (
    tester,
  ) async {
    final storage = _storage();
    await pumpEmerald(tester, storage: storage);
    storage.setFile('Gamma.md', 'Now links [[Lonely]] and [[Delta]]');
    storage.setFile('Delta.md', 'new');
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Brain'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rescan vault'));
    await tester.pumpAndSettle();
    await _graph(tester);
    expect(find.text('5 notes · 4 links'), findsOneWidget);
  });

  testWidgets('empty vault shows an empty state', (tester) async {
    await pumpEmerald(
      tester,
      storage: MemoryVaultStorage(vaultToPick: _vault, remembered: _vault),
    );
    await _graph(tester);
    expect(find.text('No notes yet'), findsOneWidget);
  });

  testWidgets('local graph from the note menu', (tester) async {
    await pumpEmerald(tester, storage: _storage());
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Brain'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Note actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local graph'));
    await tester.pumpAndSettle();
    expect(find.byType(GraphScreen), findsWidgets);
    expect(find.text('Local: Alpha'), findsOneWidget);
    expect(find.text('3 notes · 2 links'), findsOneWidget);
  });

  testWidgets('pinch-zoom/pan does not throw', (tester) async {
    await pumpEmerald(tester, storage: _storage());
    await _graph(tester);
    final center = tester.getCenter(find.byType(GraphView));
    final g1 = await tester.startGesture(center - const Offset(20, 0));
    final g2 = await tester.startGesture(center + const Offset(20, 0));
    await g1.moveBy(const Offset(-40, 0));
    await g2.moveBy(const Offset(40, 0));
    await g1.up();
    await g2.up();
    await tester.drag(find.byType(GraphView), const Offset(60, 30));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
