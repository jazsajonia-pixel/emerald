import '../../core/vault/vault_path.dart';
import '../search/vault_index.dart';

/// Where an edge comes from. Only [explicit] edges exist today; [inferred]
/// is reserved for future, optional AI/semantic suggestions and is always
/// drawn differently (dashed) so it can never be mistaken for a real link.
enum EdgeKind { explicit, inferred }

class GraphNode {
  const GraphNode({
    required this.path,
    required this.title,
    required this.degree,
  });
  final String path;
  final String title;

  /// Number of distinct neighbours (in either direction).
  final int degree;
  bool get isolated => degree == 0;
}

class GraphEdge {
  const GraphEdge(this.source, this.target, {this.kind = EdgeKind.explicit});

  /// Indices into [GraphData.nodes].
  final int source;
  final int target;
  final EdgeKind kind;
}

class GraphData {
  GraphData(this.nodes, this.edges, {this.center, this.truncated = 0})
    : _indexOf = {for (var i = 0; i < nodes.length; i++) nodes[i].path: i};

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  /// Path of the focus note in a local graph.
  final String? center;

  /// Number of notes left out because of [maxGlobalNodes].
  final int truncated;
  final Map<String, int> _indexOf;

  static const maxGlobalNodes = 2500;

  int? indexOf(String path) => _indexOf[path];
  bool get isEmpty => nodes.isEmpty;

  /// Global graph of all notes and explicit links. Above [maxGlobalNodes]
  /// only the most connected notes are kept (documented limit).
  factory GraphData.global(VaultIndex index, {bool includeIsolated = true}) {
    final neighbours = _neighbours(index);
    var paths =
        index.notes.keys
            .where(
              (p) => includeIsolated || (neighbours[p]?.isNotEmpty ?? false),
            )
            .toList()
          ..sort();
    var truncated = 0;
    if (paths.length > maxGlobalNodes) {
      final byDegree = List.of(paths)
        ..sort((a, b) {
          final c = (neighbours[b]?.length ?? 0).compareTo(
            neighbours[a]?.length ?? 0,
          );
          return c != 0 ? c : a.compareTo(b);
        });
      truncated = paths.length - maxGlobalNodes;
      paths = byDegree.take(maxGlobalNodes).toList()..sort();
    }
    return _build(index, paths.toSet(), neighbours, truncated: truncated);
  }

  /// Notes within [depth] link-steps of [center] (links in either direction).
  factory GraphData.local(VaultIndex index, String center, {int depth = 1}) {
    final neighbours = _neighbours(index);
    if (!index.notes.containsKey(center)) return GraphData(const [], const []);
    final seen = <String>{center};
    var frontier = {center};
    for (var d = 0; d < depth; d++) {
      final next = <String>{};
      for (final p in frontier) {
        for (final n in neighbours[p] ?? const <String>{}) {
          if (seen.add(n)) next.add(n);
        }
      }
      frontier = next;
    }
    return _build(index, seen, neighbours, center: center);
  }

  static Map<String, Set<String>> _neighbours(VaultIndex index) {
    final m = <String, Set<String>>{};
    for (final (s, t) in index.edges) {
      (m[s] ??= {}).add(t);
      (m[t] ??= {}).add(s);
    }
    return m;
  }

  static GraphData _build(
    VaultIndex index,
    Set<String> include,
    Map<String, Set<String>> neighbours, {
    String? center,
    int truncated = 0,
  }) {
    final paths = include.toList()..sort();
    final nodes = [
      for (final p in paths)
        GraphNode(
          path: p,
          title: VaultPath.title(p),
          degree: neighbours[p]?.length ?? 0,
        ),
    ];
    final pos = {for (var i = 0; i < paths.length; i++) paths[i]: i};
    final edges = <GraphEdge>[];
    final seenPairs = <int>{};
    for (final (s, t) in index.edges) {
      final a = pos[s], b = pos[t];
      if (a == null || b == null) continue;
      final key = a < b ? a * paths.length + b : b * paths.length + a;
      if (seenPairs.add(key)) edges.add(GraphEdge(a, b));
    }
    return GraphData(nodes, edges, center: center, truncated: truncated);
  }
}
