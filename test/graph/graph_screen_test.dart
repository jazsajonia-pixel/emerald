import 'package:sapphire/data/memory_vault_storage.dart';
import 'package:sapphire/data/vault_storage.dart';
import 'package:sapphire/features/graph/graph_screen.dart';
import 'package:sapphire/features/graph/graph_view.dart';
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

/// Global screen position of the node with [title], as currently drawn.
Offset _nodePosition(WidgetTester tester, String title) {
  final view = tester.widget<GraphView>(find.byType(GraphView));
  final i = view.data.nodes.indexWhere((n) => n.title == title);
  expect(i, isNot(-1), reason: 'node $title');
  final state = tester.state<GraphViewState>(find.byType(GraphView));
  final box = tester.renderObject<RenderBox>(find.byKey(GraphView.canvasKey));
  return box.localToGlobal(state.nodeOffset(view.data.nodes[i].path)!);
}

void main() {
  testWidgets('global graph shows all notes and explicit links', (
    tester,
  ) async {
    await pumpSapphire(tester, storage: _storage());
    await _graph(tester);
    expect(find.byType(GraphView), findsOneWidget);
    expect(find.text('4 notes · 2 links'), findsOneWidget);
    expect(find.textContaining('Node colors show groups'), findsOneWidget);
    expect(find.textContaining('violet dashes = inferred'), findsOneWidget);
  });

  testWidgets('graph auto-rotation can be paused and resumed', (tester) async {
    await pumpSapphire(tester, storage: _storage());
    await _graph(tester);
    expect(find.byTooltip('Pause graph rotation'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause graph rotation'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Resume graph rotation'), findsOneWidget);
    await tester.tap(find.byTooltip('Resume graph rotation'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause graph rotation'), findsOneWidget);
  });

  testWidgets('graph can switch between perspective 3D and flat 2D', (
    tester,
  ) async {
    await pumpSapphire(tester, storage: _storage());
    await _graph(tester);
    expect(find.text('3D perspective · auto-rotating'), findsOneWidget);
    expect(
      tester.widget<GraphView>(find.byType(GraphView)).threeDimensional,
      isTrue,
    );
    await tester.tap(find.byTooltip('Switch to 2D graph'));
    await tester.pumpAndSettle();
    expect(find.text('2D flat view'), findsOneWidget);
    expect(
      tester.widget<GraphView>(find.byType(GraphView)).threeDimensional,
      isFalse,
    );
    await tester.tap(find.byTooltip('Switch to 3D graph'));
    await tester.pumpAndSettle();
    expect(find.text('3D perspective · auto-rotating'), findsOneWidget);
  });

  testWidgets('graph 3D drag follows the finger and orbits smoothly', (
    tester,
  ) async {
    await pumpSapphire(tester, storage: _storage());
    await _graph(tester);
    final before = tester
        .state<GraphViewState>(find.byType(GraphView))
        .nodeOffset('Alpha.md')!;
    final canvas = find.byKey(GraphView.canvasKey);
    await tester.drag(canvas, const Offset(120, 10));
    await tester.pump(const Duration(milliseconds: 120));
    final after = tester
        .state<GraphViewState>(find.byType(GraphView))
        .nodeOffset('Alpha.md')!;
    expect((after - before).distance, greaterThan(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('camera controls adjust orbit, tilt, zoom, and reset', (
    tester,
  ) async {
    await pumpSapphire(tester, storage: _storage());
    await _graph(tester);
    await tester.tap(find.byTooltip('Camera controls'));
    await tester.pumpAndSettle();

    double scale() =>
        tester.state<GraphViewState>(find.byType(GraphView)).cameraScale;
    final initialScale = scale();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    final zoomedScale = scale();
    expect(zoomedScale, greaterThan(initialScale));
    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pan left'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Camera controls'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('camera-yaw-slider')));
    await tester.drag(
      find.byKey(const Key('camera-yaw-slider')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<GraphView>(find.byType(GraphView)).cameraYaw,
      isNot(0),
    );
    await tester.ensureVisible(find.byKey(const Key('camera-tilt-slider')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('camera-tilt-slider')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<GraphView>(find.byType(GraphView)).cameraTilt,
      isNot(0.18),
    );
  });

  testWidgets('tapping a node offers actions and opens the selected note', (
    tester,
  ) async {
    await pumpSapphire(tester, storage: _storage());
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
    await pumpSapphire(tester, storage: _storage());
    await _graph(tester);
    await tester.tapAt(_nodePosition(tester, 'Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('graph-node-pin')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 pinned'), findsOneWidget);
  });

  testWidgets('holding and dragging a node pulls its linked notes along', (
    tester,
  ) async {
    await pumpSapphire(tester, storage: _storage());
    await _graph(tester);
    final state = tester.state<GraphViewState>(find.byType(GraphView));
    final alpha = _nodePosition(tester, 'Alpha');
    final beta = _nodePosition(tester, 'Beta');
    final lonely = _nodePosition(tester, 'Lonely');
    final g = await tester.startGesture(alpha);
    await tester.pump();
    // Grabbing highlights the node and its links.
    expect(state.highlightedPath, 'Alpha.md');
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(12, 10));
      await tester.pump();
    }
    final betaMoved = _nodePosition(tester, 'Beta') - beta;
    final lonelyMoved = _nodePosition(tester, 'Lonely') - lonely;
    expect((_nodePosition(tester, 'Alpha') - alpha).distance, greaterThan(40));
    expect(betaMoved.distance, greaterThan(lonelyMoved.distance + 10));
    await g.up();
    await tester.pumpAndSettle();
    // Dragging is not a tap: no action sheet; highlight fades.
    expect(find.text('Focus local graph'), findsNothing);
    expect(state.highlightedPath, isNull);
  });

  testWidgets('focus action opens the local graph; back returns to global', (
    tester,
  ) async {
    await pumpSapphire(tester, storage: _storage());
    await _graph(tester);
    await tester.tapAt(_nodePosition(tester, 'Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('graph-node-focus')));
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
    await pumpSapphire(tester, storage: _storage());
    await _graph(tester);
    await tester.tap(find.byTooltip('Graph options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show unlinked notes'));
    await tester.pumpAndSettle();
    expect(find.text('3 notes · 2 links'), findsOneWidget);
  });

  testWidgets('search highlights matching nodes', (tester) async {
    await pumpSapphire(tester, storage: _storage());
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
    await pumpSapphire(tester, storage: _storage());
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
    await pumpSapphire(tester, storage: storage);
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
    await pumpSapphire(
      tester,
      storage: MemoryVaultStorage(vaultToPick: _vault, remembered: _vault),
    );
    await _graph(tester);
    expect(find.text('No notes yet'), findsOneWidget);
  });

  testWidgets('local graph from the note menu', (tester) async {
    await pumpSapphire(tester, storage: _storage());
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
    await pumpSapphire(tester, storage: _storage());
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
