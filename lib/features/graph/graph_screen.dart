import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/state_views.dart';
import '../../core/vault/vault_path.dart';
import '../notes/note_navigation.dart';
import '../search/index_controller.dart';
import '../search/vault_index.dart';
import '../vault/vault_controller.dart';
import '../../app/theme.dart';
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
  bool _rotating = true;
  bool _threeDimensional = true;
  double _cameraYaw = 0;
  double _cameraTilt = 0.18;
  final _query = TextEditingController();
  final _cameraController = GraphCameraController();

  VaultIndex? _builtFrom;
  String? _builtCenter;
  int? _builtDepth;
  bool? _builtIsolated;
  GraphData? _data;
  GraphLayout? _layout;
  int _layoutGeneration = 0;
  final Map<String, Offset> _positions = {};
  Set<String> _pinnedPaths = {};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _showCameraControls() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          void updateCamera({double? yaw, double? tilt}) {
            setSheetState(() {
              if (yaw != null) _cameraYaw = yaw;
              if (tilt != null) _cameraTilt = tilt;
            });
            setState(() {
              if (yaw != null) _cameraYaw = yaw;
              if (tilt != null) _cameraTilt = tilt;
            });
          }

          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Camera controls',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    const Text('Pan and zoom'),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Zoom out',
                          onPressed: _cameraController.zoomOut,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Zoom in',
                          onPressed: _cameraController.zoomIn,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Reset zoom',
                          onPressed: _cameraController.resetZoom,
                          icon: const Icon(Icons.center_focus_weak),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 48),
                        IconButton(
                          tooltip: 'Pan up',
                          onPressed: () =>
                              _cameraController.pan(const Offset(0, -64)),
                          icon: const Icon(Icons.keyboard_arrow_up),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Pan left',
                          onPressed: () =>
                              _cameraController.pan(const Offset(-64, 0)),
                          icon: const Icon(Icons.keyboard_arrow_left),
                        ),
                        const Icon(Icons.open_with, size: 20),
                        IconButton(
                          tooltip: 'Pan right',
                          onPressed: () =>
                              _cameraController.pan(const Offset(64, 0)),
                          icon: const Icon(Icons.keyboard_arrow_right),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 48),
                        IconButton(
                          tooltip: 'Pan down',
                          onPressed: () =>
                              _cameraController.pan(const Offset(0, 64)),
                          icon: const Icon(Icons.keyboard_arrow_down),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const Divider(),
                    Text('Orbit · ${(_cameraYaw * 180 / math.pi).round()}°'),
                    Slider(
                      key: const Key('camera-yaw-slider'),
                      value: _cameraYaw,
                      min: -math.pi,
                      max: math.pi,
                      divisions: 72,
                      label: '${(_cameraYaw * 180 / math.pi).round()}°',
                      onChanged: (value) => updateCamera(yaw: value),
                    ),
                    Text('Tilt · ${(_cameraTilt * 180 / math.pi).round()}°'),
                    Slider(
                      key: const Key('camera-tilt-slider'),
                      value: _cameraTilt,
                      min: -0.55,
                      max: 0.55,
                      divisions: 22,
                      label: '${(_cameraTilt * 180 / math.pi).round()}°',
                      onChanged: (value) => updateCamera(tilt: value),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => updateCamera(yaw: 0, tilt: 0.18),
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset orbit and tilt'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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

  Future<void> _showNodeActions(String path, GraphData data) async {
    GraphNode? node;
    for (final candidate in data.nodes) {
      if (candidate.path == path) {
        node = candidate;
        break;
      }
    }
    final selected = node;
    if (selected == null) return;
    final isPinned = _pinnedPaths.contains(path);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.hub_outlined),
                title: Text(selected.title),
                subtitle: Text(
                  '${selected.path}\n${selected.degree} linked notes',
                ),
                isThreeLine: true,
              ),
              ListTile(
                key: const Key('graph-node-open'),
                leading: const Icon(Icons.description_outlined),
                title: const Text('Open note'),
                onTap: () => Navigator.pop(sheetContext, 'open'),
              ),
              ListTile(
                key: const Key('graph-node-focus'),
                leading: const Icon(Icons.center_focus_strong),
                title: const Text('Focus local graph'),
                onTap: () => Navigator.pop(sheetContext, 'focus'),
              ),
              ListTile(
                key: const Key('graph-node-pin'),
                leading: Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                title: Text(isPinned ? 'Unpin node' : 'Pin node'),
                onTap: () => Navigator.pop(sheetContext, 'pin'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'open') {
      await openNote(context, path);
    } else if (action == 'focus') {
      _openLocal(path);
    } else if (action == 'pin') {
      setState(() {
        _pinnedPaths = {..._pinnedPaths};
        if (!_pinnedPaths.add(path)) _pinnedPaths.remove(path);
      });
    }
  }

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
              tooltip: _threeDimensional
                  ? 'Switch to 2D graph'
                  : 'Switch to 3D graph',
              icon: Icon(_threeDimensional ? Icons.view_in_ar : Icons.grid_on),
              onPressed: () =>
                  setState(() => _threeDimensional = !_threeDimensional),
            ),
            IconButton(
              tooltip: 'Camera controls',
              icon: const Icon(Icons.tune),
              onPressed: _threeDimensional ? _showCameraControls : null,
            ),
            IconButton(
              tooltip: _rotating
                  ? 'Pause graph rotation'
                  : 'Resume graph rotation',
              icon: Icon(
                _rotating
                    ? Icons.motion_photos_auto
                    : Icons.play_circle_outline,
              ),
              onPressed: () => setState(() => _rotating = !_rotating),
            ),
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
                  pinnedPaths: _pinnedPaths,
                  rotating: _rotating,
                  threeDimensional: _threeDimensional,
                  cameraYaw: _cameraYaw,
                  cameraTilt: _cameraTilt,
                  cameraController: _cameraController,
                  onNodeTap: (p) => _showNodeActions(p, data),
                  onNodeLongPress: _openLocal,
                ),
        ),
        _Legend(
          nodes: data.nodes.length,
          edges: data.edges.length,
          matches: matches,
          local: _center != null,
          pinned: _pinnedPaths.length,
          threeDimensional: _threeDimensional,
          rotating: _rotating,
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
    required this.pinned,
    required this.threeDimensional,
    required this.rotating,
  });

  final int nodes;
  final int edges;
  final int? matches;
  final bool local;
  final int pinned;
  final bool threeDimensional;
  final bool rotating;

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
            Text(
              threeDimensional
                  ? '3D perspective${rotating ? ' · auto-rotating' : ' · paused'}'
                  : '2D flat view',
              style: small?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Node colors show groups', style: small),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dot(SapphireTheme.unresolvedNode),
                    const SizedBox(width: 4),
                    Text('Unlinked note', style: small),
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
                  'Solid lines = explicit · violet dashes = inferred',
                  style: small,
                ),
              ],
            ),
            Text(
              (threeDimensional
                      ? 'Tap a note for actions · hold & drag to pull it · '
                            'drag space to orbit · pinch to zoom'
                      : 'Tap a note for actions · hold & drag to pull it · '
                            'drag to pan · pinch to zoom') +
                  (pinned == 0 ? '' : ' · $pinned pinned'),
              style: small?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
