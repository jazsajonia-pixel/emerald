import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/state_views.dart';
import '../../core/vault/vault_path.dart';
import '../notes/note_navigation.dart';
import '../search/index_controller.dart';
import '../search/vault_index.dart';
import '../vault/vault_controller.dart';
import 'graph_layout.dart';
import 'graph_model.dart';
import 'graph_view.dart';

/// Global graph (all notes) or local graph (around [center]).
class GraphScreen extends ConsumerStatefulWidget {
  const GraphScreen({super.key, this.center});

  /// When set, the screen starts as a local graph around this note.
  final String? center;

  @override
  ConsumerState<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends ConsumerState<GraphScreen> {
  late String? _center = widget.center;
  int _depth = 1;
  bool _showIsolated = true;
  bool _searching = false;
  final _query = TextEditingController();

  VaultIndex? _builtFrom;
  String? _builtCenter;
  int? _builtDepth;
  bool? _builtIsolated;
  GraphData? _data;
  GraphLayout? _layout;
  int _layoutGeneration = 0;
  final Map<String, Offset> _positions = {};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _ensureGraph(VaultIndex index) {
    if (identical(index, _builtFrom) &&
        _builtCenter == _center &&
        _builtDepth == _depth &&
        _builtIsolated == _showIsolated) {
      return;
    }
    _builtFrom = index;
    _builtCenter = _center;
    _builtDepth = _depth;
    _builtIsolated = _showIsolated;
    final data = _center != null && index.notes.containsKey(_center)
        ? GraphData.local(index, _center!, depth: _depth)
        : GraphData.global(index, includeIsolated: _showIsolated);
    if (_center != null && !index.notes.containsKey(_center)) _center = null;
    _data = data;
    final edges = Int32List(data.edges.length * 2);
    for (var i = 0; i < data.edges.length; i++) {
      edges[2 * i] = data.edges[i].source;
      edges[2 * i + 1] = data.edges[i].target;
    }
    final initial = Float64List(data.nodes.length * 2)
      ..fillRange(0, data.nodes.length * 2, double.nan);
    for (var i = 0; i < data.nodes.length; i++) {
      final p = _positions[data.nodes[i].path];
      if (p != null) {
        initial[2 * i] = p.dx;
        initial[2 * i + 1] = p.dy;
      }
    }
    final gen = ++_layoutGeneration;
    GraphLayouter.layout(
      LayoutInput(data.nodes.length, edges, initial: initial),
    ).then((layout) {
      if (!mounted || gen != _layoutGeneration) return;
      for (var i = 0; i < data.nodes.length; i++) {
        _positions[data.nodes[i].path] = Offset(layout.x(i), layout.y(i));
      }
      setState(() => _layout = layout);
    });
  }

  void _openLocal(String path) => setState(() {
    _center = path;
    _layout = null;
  });

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultControllerProvider);
    final idx = ref.watch(indexControllerProvider);
    final isLocal = _center != null;
    final title = isLocal ? 'Local: ${VaultPath.title(_center!)}' : 'Graph';
    return PopScope(
      canPop: !isLocal || widget.center != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _center = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  key: const Key('graph-search'),
                  controller: _query,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Highlight notes…',
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => setState(() {}),
                )
              : Text(title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: _searching ? 'Stop highlighting' : 'Highlight notes',
              icon: Icon(_searching ? Icons.close : Icons.search),
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) _query.clear();
              }),
            ),
            if (isLocal && widget.center == null)
              IconButton(
                tooltip: 'Global graph',
                icon: const Icon(Icons.public),
                onPressed: () => setState(() => _center = null),
              ),
            PopupMenuButton<String>(
              tooltip: 'Graph options',
              onSelected: (v) => setState(() {
                if (v == 'isolated') _showIsolated = !_showIsolated;
                if (v == 'depth1') _depth = 1;
                if (v == 'depth2') _depth = 2;
              }),
              itemBuilder: (_) => [
                if (!isLocal)
                  CheckedPopupMenuItem(
                    value: 'isolated',
                    checked: _showIsolated,
                    child: const Text('Show unlinked notes'),
                  ),
                if (isLocal) ...[
                  CheckedPopupMenuItem(
                    value: 'depth1',
                    checked: _depth == 1,
                    child: const Text('Direct links only'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'depth2',
                    checked: _depth == 2,
                    child: const Text('Links of links'),
                  ),
                ],
              ],
            ),
          ],
        ),
        body: _body(vault, idx),
      ),
    );
  }

  Widget _body(VaultState vault, IndexState idx) {
    if (vault is VaultLoading) {
      return const LoadingView(label: 'Opening vault…');
    }
    if (vault is VaultAccessLost) {
      return PermissionDeniedView(
        onReselect: ref.read(vaultControllerProvider.notifier).pick,
      );
    }
    if (vault is! VaultReady) {
      return const EmptyView(
        icon: Icons.hub_outlined,
        title: 'No vault selected',
        message:
            'Choose a vault folder in Brain to see how your notes connect.',
      );
    }
    if (idx.index.notes.isEmpty) {
      return idx.building
          ? LoadingView(label: 'Indexing notes (${idx.done}/${idx.total})…')
          : const EmptyView(
              icon: Icons.hub_outlined,
              title: 'No notes yet',
              message: 'Notes and the links between them will appear here.',
            );
    }
    _ensureGraph(idx.index);
    final data = _data!;
    final layout = _layout;
    if (data.isEmpty) {
      return EmptyView(
        icon: Icons.hub_outlined,
        title: 'Nothing to show',
        message: _showIsolated
            ? null
            : 'All notes are unlinked. Turn on "Show unlinked notes".',
      );
    }
    final matches = _query.text.trim().isEmpty
        ? null
        : data.nodes
              .where(
                (n) => n.title.toLowerCase().contains(
                  _query.text.trim().toLowerCase(),
                ),
              )
              .length;
    return Column(
      children: [
        if (data.truncated > 0)
          MaterialBanner(
            content: Text(
              'Showing the ${GraphData.maxGlobalNodes} most connected notes; '
              '${data.truncated} more are hidden to keep the graph responsive.',
            ),
            actions: const [SizedBox.shrink()],
          ),
        Expanded(
          child: layout == null || layout.length != data.nodes.length
              ? const LoadingView(label: 'Arranging graph…')
              : GraphView(
                  data: data,
                  layout: layout,
                  query: _query.text,
                  onNodeTap: (p) => openNote(context, p),
                  onNodeLongPress: _openLocal,
                ),
        ),
        _Legend(
          nodes: data.nodes.length,
          edges: data.edges.length,
          matches: matches,
          local: _center != null,
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.nodes,
    required this.edges,
    required this.matches,
    required this.local,
  });

  final int nodes;
  final int edges;
  final int? matches;
  final bool local;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    Widget dot(Color fill, {Color? ring}) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: ring == null ? null : Border.all(color: ring, width: 1.5),
      ),
    );
    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$nodes notes · $edges links'
              '${matches == null ? '' : ' · $matches highlighted'}',
              style: small,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dot(scheme.primary),
                    const SizedBox(width: 4),
                    Text('Linked', style: small),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dot(scheme.surfaceContainerHighest, ring: scheme.outline),
                    const SizedBox(width: 4),
                    Text('Unlinked', style: small),
                  ],
                ),
                if (local)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      dot(Colors.transparent, ring: scheme.tertiary),
                      const SizedBox(width: 4),
                      Text('Focus note', style: small),
                    ],
                  ),
                Text(
                  'Lines = your explicit links. AI-suggested links: off.',
                  style: small,
                ),
              ],
            ),
            Text(
              'Tap a note to open it · long-press for its local graph',
              style: small?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
