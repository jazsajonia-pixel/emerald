import 'dart:math' as math;
import 'dart:typed_data';

import 'package:emerald/features/graph/graph_layout.dart';
import 'package:emerald/features/graph/graph_model.dart';
import 'package:emerald/features/search/vault_index.dart';
import 'package:flutter_test/flutter_test.dart';

VaultIndex build(Map<String, String> files) => VaultIndex({
  for (final e in files.entries)
    e.key: IndexedNote(path: e.key, text: e.value, lastModified: 1, size: 1),
});

Set<String> edgeSet(GraphData g) => {
  for (final e in g.edges)
    ([g.nodes[e.source].path, g.nodes[e.target].path]..sort()).join(' — '),
};

void main() {
  final idx = build({
    'A.md': '[[B]] [[C]] [[B]] [[Missing]]',
    'B.md': '[[A]]',
    'C.md': '[[D]]',
    'D.md': '',
    'E.md': 'alone',
    'F.md': '[[G]]',
    'G.md': '',
  });

  test('global graph edges match parsed explicit links (deduplicated)', () {
    final g = GraphData.global(idx);
    expect(g.nodes.map((n) => n.path), [
      'A.md',
      'B.md',
      'C.md',
      'D.md',
      'E.md',
      'F.md',
      'G.md',
    ]);
    expect(edgeSet(g), {
      'A.md — B.md',
      'A.md — C.md',
      'C.md — D.md',
      'F.md — G.md',
    });
    final expected = {
      for (final (s, t) in idx.edges) ([s, t]..sort()).join(' — '),
    };
    expect(edgeSet(g), expected);
    expect(g.edges.every((e) => e.kind == EdgeKind.explicit), isTrue);
  });

  test('degrees and isolated nodes', () {
    final g = GraphData.global(idx);
    GraphNode node(String p) => g.nodes[g.indexOf(p)!];
    expect(node('A.md').degree, 2);
    expect(node('E.md').isolated, isTrue);
    expect(
      GraphData.global(idx, includeIsolated: false).indexOf('E.md'),
      isNull,
    );
  });

  test('local graph depth 1 and 2', () {
    final l1 = GraphData.local(idx, 'C.md');
    expect(l1.nodes.map((n) => n.path).toSet(), {'A.md', 'C.md', 'D.md'});
    expect(l1.center, 'C.md');
    final l2 = GraphData.local(idx, 'C.md', depth: 2);
    expect(l2.nodes.map((n) => n.path).toSet(), {
      'A.md',
      'B.md',
      'C.md',
      'D.md',
    });
    expect(GraphData.local(idx, 'E.md').nodes.single.path, 'E.md');
    expect(GraphData.local(idx, 'Nope.md').isEmpty, isTrue);
  });

  test('empty vault', () {
    final g = GraphData.global(VaultIndex.empty);
    expect(g.isEmpty, isTrue);
    expect(GraphLayouter.compute(LayoutInput(0, Int32List(0))).length, 0);
  });

  test('truncates very large vaults to the most connected notes', () {
    final files = <String, String>{'Hub.md': ''};
    for (var i = 0; i < GraphData.maxGlobalNodes + 10; i++) {
      files['n$i.md'] = i < 50 ? '[[Hub]]' : '';
    }
    final g = GraphData.global(build(files));
    expect(g.nodes.length, GraphData.maxGlobalNodes);
    expect(g.truncated, 11);
    expect(g.indexOf('Hub.md'), isNotNull);
  });

  group('layout', () {
    LayoutInput input(GraphData g) {
      final e = Int32List(g.edges.length * 2);
      for (var i = 0; i < g.edges.length; i++) {
        e[2 * i] = g.edges[i].source;
        e[2 * i + 1] = g.edges[i].target;
      }
      return LayoutInput(g.nodes.length, e);
    }

    test('is deterministic, finite and inside the canvas', () {
      final g = GraphData.global(idx);
      final a = GraphLayouter.compute(input(g));
      final b = GraphLayouter.compute(input(g));
      expect(a.xy, b.xy);
      for (var i = 0; i < a.length; i++) {
        expect(a.x(i).isFinite && a.y(i).isFinite, isTrue);
        expect(a.x(i), inInclusiveRange(0, a.width));
        expect(a.y(i), inInclusiveRange(0, a.height));
      }
    });

    test('linked notes end up closer than unrelated ones', () {
      final g = GraphData.global(idx);
      final l = GraphLayouter.compute(input(g));
      double dist(String p, String q) {
        final i = g.indexOf(p)!, j = g.indexOf(q)!;
        return math.sqrt(
          math.pow(l.x(i) - l.x(j), 2) + math.pow(l.y(i) - l.y(j), 2),
        );
      }

      expect(dist('F.md', 'G.md'), lessThan(dist('F.md', 'D.md')));
      // Nodes do not collapse onto each other.
      for (var i = 0; i < l.length; i++) {
        for (var j = i + 1; j < l.length; j++) {
          final d = math.sqrt(
            math.pow(l.x(i) - l.x(j), 2) + math.pow(l.y(i) - l.y(j), 2),
          );
          expect(d, greaterThan(10));
        }
      }
    });

    test('hitTest finds the nearest node within the radius', () {
      final l = GraphLayout(Float64List.fromList([10, 10, 100, 100]), 200, 200);
      expect(l.hitTest(12, 11, 10), 0);
      expect(l.hitTest(95, 98, 10), 1);
      expect(l.hitTest(50, 50, 10), isNull);
    });

    test(
      '2.5D projection is deterministic, invertible and finite near plane',
      () {
        const projection = GraphProjection();
        const origin = Offset(200, 160);
        const point = Offset(420, 80);
        final a = projection.project(point, origin: origin, depth: 64);
        final b = projection.project(point, origin: origin, depth: 64);
        expect(a, b);
        final roundTrip = projection.unproject(a, origin: origin, depth: 64);
        expect(roundTrip.dx, closeTo(point.dx, 0.0001));
        expect(roundTrip.dy, closeTo(point.dy, 0.0001));
        for (final depth in [0.0, -10.0, double.nan, double.infinity]) {
          final projected = projection.project(
            point,
            origin: origin,
            depth: depth,
          );
          expect(projected.dx.isFinite && projected.dy.isFinite, isTrue);
          expect(projection.scaleForDepth(depth).isFinite, isTrue);
        }
      },
    );

    test('rotating 3D projection moves nodes across the canvas', () {
      const projection = GraphProjection();
      const origin = Offset(300, 240);
      const point = Offset(520, 110);
      final first = projection.projectRotating(
        point,
        origin: origin,
        depth: 106,
        rotation: 0,
      );
      final rotated = projection.projectRotating(
        point,
        origin: origin,
        depth: 106,
        rotation: math.pi / 2,
      );
      expect((rotated - first).distance, greaterThan(20));
      expect(rotated.dx.isFinite && rotated.dy.isFinite, isTrue);
    });

    test('1500-node vault lays out in reasonable time', () {
      final rnd = math.Random(1);
      final edges = Int32List(3000);
      for (var i = 0; i < edges.length; i++) {
        edges[i] = rnd.nextInt(1500);
      }
      final sw = Stopwatch()..start();
      final l = GraphLayouter.compute(LayoutInput(1500, edges));
      sw.stop();
      expect(l.length, 1500);
      // Generous bound for slow CI machines; runs off the UI isolate in-app.
      expect(sw.elapsed.inSeconds, lessThan(20));
      // ignore: avoid_print
      print('layout 1500 nodes / 1500 edges: ${sw.elapsedMilliseconds} ms');
    });

    test('initial positions are reused', () {
      final init = Float64List.fromList([0, 0, 500, 500]);
      final l = GraphLayouter.compute(
        LayoutInput(2, Int32List(0), initial: init),
      );
      expect(l.length, 2);
    });
  });
}
