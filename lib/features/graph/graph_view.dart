import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import 'graph_layout.dart';
import 'graph_model.dart';

/// Actions for camera controls hosted outside the graph canvas.
class GraphCameraController {
  Object? _owner;
  void Function(double factor)? _zoomAction;
  void Function(Offset distance)? _panAction;
  VoidCallback? _resetAction;

  void _attach(
    Object owner, {
    required void Function(double factor) zoom,
    required void Function(Offset distance) pan,
    required VoidCallback reset,
  }) {
    _owner = owner;
    _zoomAction = zoom;
    _panAction = pan;
    _resetAction = reset;
  }

  void _detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _zoomAction = null;
    _panAction = null;
    _resetAction = null;
  }

  void zoomIn() => _zoomAction?.call(1.25);
  void zoomOut() => _zoomAction?.call(0.8);
  void pan(Offset distance) => _panAction?.call(distance);
  void resetZoom() => _resetAction?.call();
}

/// Interactive knowledge graph with a live force simulation (Obsidian-style).
///
/// - Press a node to grab it: it pops with a springy bounce, its links and
///   neighbours light up and everything else dims.
/// - Drag it and its linked notes follow on elastic springs; release and the
///   graph settles back with a soft wobble.
/// - In 3D every note floats in space; drag the background to orbit (with
///   inertia), pinch to zoom. In 2D drag the background to pan.
/// - Switching 2D ↔ 3D morphs smoothly between a flat map and a 3D cloud.
///
/// One [CustomPainter] draws everything, so it stays smooth with thousands
/// of nodes. With reduced motion, all animation is skipped.
class GraphView extends StatefulWidget {
  const GraphView({
    super.key,
    required this.data,
    required this.layout,
    this.query = '',
    this.pinnedPaths = const {},
    this.changedPaths = const {},
    this.rotating = true,
    this.threeDimensional = true,
    this.cameraYaw = 0,
    this.cameraTilt = 0.18,
    this.cameraController,
    required this.onNodeTap,
    this.onNodeLongPress,
  });

  final GraphData data;
  final GraphLayout layout;
  final String query;
  final Set<String> pinnedPaths;
  /// Notes touched by the most recent successful sync.
  final Set<String> changedPaths;

  /// Slow auto-orbit in 3D while idle.
  final bool rotating;
  final bool threeDimensional;

  /// Extra camera angles from the camera controls (radians).
  final double cameraYaw;
  final double cameraTilt;
  final GraphCameraController? cameraController;
  final ValueChanged<String> onNodeTap;

  /// Exposed as an accessibility action (holding a node grabs it instead).
  final ValueChanged<String>? onNodeLongPress;

  static const canvasKey = Key('graph-canvas');

  /// Base dot radius in logical pixels (small, Obsidian-like dots).
  static double nodeRadius(GraphNode n) =>
      math.min(8.0, 3.2 + math.sqrt(n.degree.toDouble()) * 1.1);

  @override
  State<GraphView> createState() => GraphViewState();
}

/// Critically under-damped spring for bouncy UI values.
class _Spring {
  _Spring(this.value) : target = value;
  double value;
  double target;
  double velocity = 0;

  /// Advances by [dt]; returns true while still moving.
  bool step(double dt, {double stiffness = 340, double damping = 15}) {
    final a = stiffness * (target - value) - damping * velocity;
    velocity += a * dt;
    value += velocity * dt;
    if ((target - value).abs() < 0.0015 && velocity.abs() < 0.0015) {
      value = target;
      velocity = 0;
      return false;
    }
    return true;
  }

  void snap() {
    value = target;
    velocity = 0;
  }
}

enum _Gesture { none, node, camera, pinch }

class GraphViewState extends State<GraphView>
    with SingleTickerProviderStateMixin {
  // ---- Simulation state (world space, centred on 0) ----------------------
  int _n = 0;
  int? _orbitCenterIndex;
  Float64List _x = Float64List(0), _y = Float64List(0), _z = Float64List(0);
  Float64List _vx = Float64List(0), _vy = Float64List(0), _vz = Float64List(0);
  List<List<int>> _adj = const [];
  List<Color> _colors = const [];
  bool _colorsByFolder = false;
  double _radius = 200; // world radius of the cloud
  double _alpha = 0; // simulation "temperature"
  int? _dragIndex;
  double _dragX = 0, _dragY = 0, _dragZ = 0;
  double _dragVX = 0, _dragVY = 0;

  // ---- Camera --------------------------------------------------------------
  double _scale = 1;
  Offset _pan = Offset.zero;
  double _yaw = 0.5, _pitch = 0.0;
  double _yawVel = 0, _pitchVel = 0;
  final _flat = _Spring(1); // 1 = 3D, 0 = flat 2D
  Size? _viewport;
  bool _fitted = false;

  // ---- Interaction feedback ------------------------------------------------
  final _grab = _Spring(1); // radius multiplier of the grabbed node
  final _focusAmt = _Spring(0); // 0..1 highlight strength
  int? _focus; // node whose links are highlighted
  double _ripple = 1; // 0..1 progress of the grab ripple
  int? _rippleIndex;

  // ---- Gestures ------------------------------------------------------------
  final _pointers = <int, Offset>{};
  _Gesture _gesture = _Gesture.none;
  Offset _downPos = Offset.zero;
  Duration _downStamp = Duration.zero;
  bool _moved = false;
  double _pinchDist = 1, _pinchScale = 1;
  Offset _pinchFocal = Offset.zero, _pinchPan = Offset.zero;
  Duration _lastMoveStamp = Duration.zero;

  // ---- Frame bookkeeping ---------------------------------------------------
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;
  double _motionSeconds = 0;
  final _frame = ValueNotifier<int>(0);
  final _labels = <int, TextPainter>{};
  final _labelsFocus = <int, TextPainter>{};
  Float64List _sx = Float64List(0), _sy = Float64List(0);
  Float64List _sk = Float64List(0), _sd = Float64List(0);
  Int32List _order = Int32List(0);
  Size _projectedFor = Size.zero;
  int _projectedFrame = -1;
  Set<String> _matches = const {};

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  bool get _threeD => widget.threeDimensional;

  @override
  void initState() {
    super.initState();
    _flat.value = _flat.target = widget.threeDimensional ? 1 : 0;
    _yaw = widget.threeDimensional ? 0.5 : 0;
    _initFrom(widget.data, widget.layout, keep: const {});
  }

  @override
  void didUpdateWidget(GraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.cameraController != widget.cameraController) {
      old.cameraController?._detach(this);
    }
    if (old.data != widget.data || old.layout != widget.layout) {
      final keep = <String, (double, double, double)>{};
      for (var i = 0; i < _n && i < old.data.nodes.length; i++) {
        keep[old.data.nodes[i].path] = (_x[i], _y[i], _z[i]);
      }
      final sameSet =
          old.data.nodes.length == widget.data.nodes.length &&
          old.data.center == widget.data.center;
      _initFrom(widget.data, widget.layout, keep: keep);
      if (!sameSet) {
        _fitted = false;
        _autoFit = true;
      }
    }
    if (old.threeDimensional != widget.threeDimensional) {
      _flat.target = widget.threeDimensional ? 1 : 0;
      _autoFit = true;
      _reheat(0.35);
      if (_reduceMotion) _flat.snap();
    }
    if (old.query != widget.query) _updateMatches();
    _kick();
  }

  @override
  void dispose() {
    widget.cameraController?._detach(this);
    _ticker.dispose();
    _frame.dispose();
    for (final p in [..._labels.values, ..._labelsFocus.values]) {
      p.dispose();
    }
    super.dispose();
  }

  // ---- Setup -----------------------------------------------------------

  static double _hash(int i, int salt) {
    var h = (i * 374761393 + salt * 668265263) & 0x7fffffff;
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
    return (h % 100000) / 50000.0 - 1.0; // -1..1
  }

  void _initFrom(
    GraphData data,
    GraphLayout layout, {
    required Map<String, (double, double, double)> keep,
  }) {
    final n = data.nodes.length;
    _n = n;
    _orbitCenterIndex = data.nodes.indexWhere(
      (node) => node.path == 'Brain/00 - Home.md' || node.path == '00 - Home.md',
    );
    if (_orbitCenterIndex == -1) _orbitCenterIndex = null;
    _x = Float64List(n);
    _y = Float64List(n);
    _z = Float64List(n);
    _vx = Float64List(n);
    _vy = Float64List(n);
    _vz = Float64List(n);
    _sx = Float64List(n);
    _sy = Float64List(n);
    _sk = Float64List(n);
    _sd = Float64List(n);
    _order = Int32List.fromList(List.generate(n, (i) => i));
    _projectedFrame = -1;
    final cx = layout.width / 2, cy = layout.height / 2;
    var r = 1.0;
    for (var i = 0; i < n; i++) {
      final lx = i < layout.length ? layout.x(i) - cx : 0.0;
      final ly = i < layout.length ? layout.y(i) - cy : 0.0;
      r = math.max(r, math.sqrt(lx * lx + ly * ly));
    }
    _radius = math.max(120, r);
    for (var i = 0; i < n; i++) {
      final k = keep[data.nodes[i].path];
      if (k != null) {
        _x[i] = k.$1;
        _y[i] = k.$2;
        _z[i] = k.$3;
      } else {
        _x[i] = i < layout.length ? layout.x(i) - cx : 0;
        _y[i] = i < layout.length ? layout.y(i) - cy : 0;
        // Scatter depth so the 3D view starts as a full cloud.
        _z[i] = _hash(i, 3) * _radius * 0.85;
      }
    }
    _adj = List.generate(n, (_) => <int>[]);
    for (final e in data.edges) {
      if (e.source == e.target) continue;
      _adj[e.source].add(e.target);
      _adj[e.target].add(e.source);
    }
    _assignColors(data);
    for (final p in [..._labels.values, ..._labelsFocus.values]) {
      p.dispose();
    }
    _labels.clear();
    _labelsFocus.clear();
    _focus = null;
    _focusAmt
      ..target = 0
      ..snap();
    _dragIndex = null;
    _updateMatches();
    _alpha = keep.isEmpty ? 0.6 : 0.3;
  }

  void _updateMatches() {
    final q = widget.query.trim().toLowerCase();
    _matches = q.isEmpty
        ? const {}
        : {
            for (final node in widget.data.nodes)
              if (node.title.toLowerCase().contains(q)) node.path,
          };
  }

  /// Solid group colours: by top-level folder when the vault uses folders,
  /// otherwise by clusters of linked notes.
  void _assignColors(GraphData data) {
    final n = data.nodes.length;
    final folder = [
      for (final node in data.nodes)
        node.path.contains('/') ? node.path.split('/').first : '',
    ];
    final folders = folder.toSet();
    final group = List<int>.filled(n, 0);
    if (folders.length >= 2) {
      _colorsByFolder = true;
      final ids = <String, int>{};
      for (var i = 0; i < n; i++) {
        group[i] = ids.putIfAbsent(folder[i], () => ids.length);
      }
    } else {
      _colorsByFolder = false;
      // Label propagation: each note adopts the most common label among
      // its neighbours. Deterministic (fixed order, ties → smallest label).
      final label = List<int>.generate(n, (i) => i);
      for (var round = 0; round < 12; round++) {
        var changed = false;
        for (var i = 0; i < n; i++) {
          if (_adj[i].isEmpty) continue;
          final counts = <int, int>{};
          for (final j in _adj[i]) {
            counts[label[j]] = (counts[label[j]] ?? 0) + 1;
          }
          var best = label[i], bestCount = 0;
          counts.forEach((l, c) {
            if (c > bestCount || (c == bestCount && l < best)) {
              best = l;
              bestCount = c;
            }
          });
          if (best != label[i]) {
            label[i] = best;
            changed = true;
          }
        }
        if (!changed) break;
      }
      for (var i = 0; i < n; i++) {
        group[i] = label[i];
      }
    }
    // Biggest groups get the first (most "sapphire") colours.
    final sizes = <int, int>{};
    for (final g in group) {
      sizes[g] = (sizes[g] ?? 0) + 1;
    }
    final ranked = sizes.keys.toList()
      ..sort((a, b) {
        final c = sizes[b]!.compareTo(sizes[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    final rank = {for (var i = 0; i < ranked.length; i++) ranked[i]: i};
    const palette = SapphireTheme.nodePalette;
    _colors = [
      for (var i = 0; i < n; i++)
        data.nodes[i].isolated && !_colorsByFolder
            ? SapphireTheme.unresolvedNode
            : palette[rank[group[i]]! % palette.length],
    ];
  }

  // ---- Simulation --------------------------------------------------------

  static const _link = 62.0;

  void _reheat(double to) {
    _alpha = math.max(_alpha, to);
    _kick();
  }

  void _simulate() {
    final n = _n;
    if (n == 0) return;
    final three = _threeD;
    final a = _alpha;
    const repulse = _link * _link * 1.15;
    // Repulsion: exact for small graphs, grid-local for large ones.
    if (n <= 260) {
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          _repel(i, j, repulse, a, three);
        }
      }
    } else {
      const cell = _link * 3;
      final grid = <int, List<int>>{};
      int key(int gx, int gy, int gz) =>
          ((gx + 512) << 20) | ((gy + 512) << 10) | (gz + 512);
      for (var i = 0; i < n; i++) {
        final k = key(
          (_x[i] / cell).floor().clamp(-500, 500),
          (_y[i] / cell).floor().clamp(-500, 500),
          three ? (_z[i] / cell).floor().clamp(-500, 500) : 0,
        );
        (grid[k] ??= <int>[]).add(i);
      }
      for (var i = 0; i < n; i++) {
        final gx = (_x[i] / cell).floor().clamp(-500, 500);
        final gy = (_y[i] / cell).floor().clamp(-500, 500);
        final gz = three ? (_z[i] / cell).floor().clamp(-500, 500) : 0;
        for (var dx = -1; dx <= 1; dx++) {
          for (var dy = -1; dy <= 1; dy++) {
            for (var dz = three ? -1 : 0; dz <= (three ? 1 : 0); dz++) {
              final bucket = grid[key(gx + dx, gy + dy, gz + dz)];
              if (bucket == null) continue;
              for (final j in bucket) {
                if (j > i) _repel(i, j, repulse, a, three);
              }
            }
          }
        }
      }
    }
    // Springs along links.
    for (final e in widget.data.edges) {
      final i = e.source, j = e.target;
      if (i == j) continue;
      final dx = _x[j] - _x[i], dy = _y[j] - _y[i];
      final dz = three ? _z[j] - _z[i] : 0.0;
      final d = math.sqrt(dx * dx + dy * dy + dz * dz) + 0.01;
      final degree = math.min(_adj[i].length, _adj[j].length).clamp(1, 99);
      final f = (d - _link) / d * a * 0.32 / degree;
      _vx[i] += dx * f;
      _vy[i] += dy * f;
      _vx[j] -= dx * f;
      _vy[j] -= dy * f;
      if (three) {
        _vz[i] += dz * f;
        _vz[j] -= dz * f;
      }
    }
    // Gentle gravity keeps the cloud centred; integrate with damping.
    final g0 = 0.018 * a;
    for (var i = 0; i < n; i++) {
      // Unlinked notes get extra gravity so they orbit close instead of
      // drifting to the edges.
      final g = _adj[i].isEmpty ? g0 * 3 : g0;
      _vx[i] -= _x[i] * g;
      _vy[i] -= _y[i] * g;
      if (three) _vz[i] -= _z[i] * g;
      _vx[i] *= 0.62;
      _vy[i] *= 0.62;
      _vz[i] *= 0.62;
      final sp = _vx[i] * _vx[i] + _vy[i] * _vy[i] + _vz[i] * _vz[i];
      if (sp > 1600) {
        final s = 40 / math.sqrt(sp);
        _vx[i] *= s;
        _vy[i] *= s;
        _vz[i] *= s;
      }
      if (i == _dragIndex) continue;
      _x[i] += _vx[i];
      _y[i] += _vy[i];
      if (three) _z[i] += _vz[i];
    }
    // The grabbed node sticks to the finger; its neighbours are pulled
    // along elastically so the cluster moves together.
    final di = _dragIndex;
    if (di != null) {
      final mx = _dragX - _x[di], my = _dragY - _y[di];
      final mz = three ? _dragZ - _z[di] : 0.0;
      _dragVX = mx;
      _dragVY = my;
      _x[di] = _dragX;
      _y[di] = _dragY;
      if (three) _z[di] = _dragZ;
      _vx[di] = _vy[di] = _vz[di] = 0;
      for (final j in _adj[di]) {
        _x[j] += mx * 0.42;
        _y[j] += my * 0.42;
        if (three) _z[j] += mz * 0.42;
        for (final k in _adj[j]) {
          if (k == di) continue;
          _x[k] += mx * 0.12;
          _y[k] += my * 0.12;
          if (three) _z[k] += mz * 0.12;
        }
      }
    }
  }

  void _repel(int i, int j, double k, double a, bool three) {
    var dx = _x[j] - _x[i], dy = _y[j] - _y[i];
    final dz = three ? _z[j] - _z[i] : 0.0;
    var d2 = dx * dx + dy * dy + dz * dz;
    if (d2 < 1) {
      dx = _hash(i + j, 1);
      dy = _hash(i - j, 2);
      d2 = 1;
    }
    if (d2 > 250000) return; // beyond ~500 units: negligible
    final f = k * a / d2 / math.sqrt(d2);
    _vx[i] -= dx * f;
    _vy[i] -= dy * f;
    _vx[j] += dx * f;
    _vy[j] += dy * f;
    if (three) {
      _vz[i] -= dz * f;
      _vz[j] += dz * f;
    }
  }

  // ---- Frame loop ----------------------------------------------------------

  void _kick() {
    if (!mounted) return;
    if (_reduceMotion) {
      _settleNow();
      _frame.value++;
      return;
    }
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  /// With reduced motion: finish all animations immediately.
  void _settleNow() {
    _flat.snap();
    _grab.snap();
    _focusAmt.snap();
    _ripple = 1;
    _yawVel = _pitchVel = 0;
    if (_dragIndex != null) _simulate();
  }

  bool get _autoOrbit =>
      widget.rotating &&
      _threeD &&
      _pointers.isEmpty &&
      !_reduceMotion &&
      _n <= 1500;

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    _motionSeconds += dt;
    var active = false;

    // Simulation temperature: hot while dragging, cooling otherwise.
    final target = _dragIndex != null ? 0.3 : 0.0;
    _alpha += (target - _alpha) * (_dragIndex != null ? 0.12 : 0.028);
    if (_alpha > 0.004 || _dragIndex != null) {
      _simulate();
      active = true;
    } else {
      _alpha = 0;
    }

    if (_flat.step(dt, stiffness: 90, damping: 19)) active = true;
    if (_followFit()) active = true;
    if (_grab.step(dt)) active = true;
    if (_focusAmt.step(dt, stiffness: 200, damping: 26)) active = true;
    if (_ripple < 1) {
      _ripple = math.min(1, _ripple + dt / 0.55);
      active = true;
    }
    if (_yawVel.abs() > 0.002 || _pitchVel.abs() > 0.002) {
      _yaw += _yawVel * dt;
      _pitch = (_pitch + _pitchVel * dt).clamp(-1.35, 1.35);
      final decay = math.pow(0.04, dt).toDouble();
      _yawVel *= decay;
      _pitchVel *= decay;
      active = true;
    } else if (_autoOrbit) {
      _yaw += 0.16 * dt;
      active = true;
    }

    _frame.value++;
    if (!active) _ticker.stop();
  }

  // ---- Projection ----------------------------------------------------------

  double get _focal => _radius * 3.2;

  /// Computes screen positions for this frame (cached per frame).
  void _project(Size size) {
    if (_projectedFrame == _frame.value && _projectedFor == size) return;
    _projectedFrame = _frame.value;
    _projectedFor = size;
    final zf = _flat.value.clamp(0.0, 1.2);
    final yaw = (_yaw + widget.cameraYaw) * zf;
    final pitch = (_pitch + widget.cameraTilt) * zf;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final f = _focal;
    final ox = size.width / 2 + _pan.dx, oy = size.height / 2 + _pan.dy;
    final pivot = _orbitCenterIndex;
    final px = pivot == null ? 0.0 : _x[pivot];
    final py = pivot == null ? 0.0 : _y[pivot];
    final pz = pivot == null ? 0.0 : _z[pivot] * zf;
    for (var i = 0; i < _n; i++) {
      final x = _x[i] - px, y = _y[i] - py, z = _z[i] * zf - pz;
      final x1 = x * cy - z * sy;
      final z1 = x * sy + z * cy;
      final y2 = y * cp - z1 * sp;
      final z2 = y * sp + z1 * cp;
      final k = f / (f + math.max(z2, -f * 0.8));
      _sx[i] = ox + (px + x1 * k) * _scale;
      _sy[i] = oy + (py + y2 * k) * _scale;
      _sk[i] = k;
      _sd[i] = z2;
    }
    if (zf > 0.01) {
      final list = _order.toList()..sort((a, b) => _sd[b].compareTo(_sd[a]));
      _order.setAll(0, list);
    }
  }

  /// Inverse of [_project] for node [i]'s current depth.
  (double, double, double) _unproject(Offset p, int i) {
    final size = _projectedFor;
    final zf = _flat.value.clamp(0.0, 1.2);
    final yaw = (_yaw + widget.cameraYaw) * zf;
    final pitch = (_pitch + widget.cameraTilt) * zf;
    final k = _sk[i] == 0 ? 1.0 : _sk[i];
    final pivot = _orbitCenterIndex;
    final px = pivot == null ? 0.0 : _x[pivot];
    final py = pivot == null ? 0.0 : _y[pivot];
    final pz = pivot == null ? 0.0 : _z[pivot] * zf;
    final x1 = ((p.dx - size.width / 2 - _pan.dx) / _scale - px) / k;
    final y2 = ((p.dy - size.height / 2 - _pan.dy) / _scale - py) / k;
    final z2 = _sd[i];
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final y = y2 * cp + z2 * sp;
    final z1 = -y2 * sp + z2 * cp;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final x = x1 * cy + z1 * sy;
    final z = -x1 * sy + z1 * cy;
    return (x + px, y + py, zf > 0.05 ? (z + pz) / zf : _z[i]);
  }

  double _screenRadius(int i) {
    final zoom = math.sqrt(_scale).clamp(0.6, 1.8);
    var r = GraphView.nodeRadius(widget.data.nodes[i]) * _sk[i] * zoom;
    if (i == _dragIndex || (i == _focus && _pointers.isNotEmpty)) {
      r *= _grab.value;
    }
    return r;
  }

  /// Local canvas position of the node at [path] as currently drawn.
  @visibleForTesting
  Offset? nodeOffset(String path) {
    final i = widget.data.indexOf(path);
    if (i == null || _viewport == null) return null;
    _project(_viewport!);
    return Offset(_sx[i], _sy[i]);
  }

  int? _hit(Offset p) {
    if (_viewport == null) return null;
    _project(_viewport!);
    int? best;
    var bestScore = double.infinity;
    for (var i = 0; i < _n; i++) {
      final dx = _sx[i] - p.dx, dy = _sy[i] - p.dy;
      final d = math.sqrt(dx * dx + dy * dy);
      final reach = math.max(_screenRadius(i) + 10, 20.0);
      if (d > reach) continue;
      // Prefer the closest dot; break ties toward the front in 3D.
      final score = d - _sd[i] * 0.002;
      if (score < bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }

  // ---- Camera actions -------------------------------------------------------

  /// Camera (scale, pan) that frames the bulk of the cloud in [size].
  (double, Offset)? _fitTarget(Size size) {
    if (_n == 0) return null;
    final saveScale = _scale, savePan = _pan;
    _scale = 1;
    _pan = Offset.zero;
    _projectedFrame = -1;
    _project(size);
    _scale = saveScale;
    _pan = savePan;
    // Fit the bulk of the cloud; a few far outliers may sit off-screen.
    final xs = List<double>.generate(_n, (i) => _sx[i])..sort();
    final ys = List<double>.generate(_n, (i) => _sy[i])..sort();
    _projectedFrame = -1;
    final cut = _n > 20 ? (_n * 0.04).floor() : 0;
    final minX = xs[cut], maxX = xs[_n - 1 - cut];
    final minY = ys[cut], maxY = ys[_n - 1 - cut];
    final bw = math.max(maxX - minX, 40.0), bh = math.max(maxY - minY, 40.0);
    final sc = math
        .min(size.width * 0.86 / bw, size.height * 0.8 / bh)
        .clamp(0.08, 2.6);
    if (!sc.isFinite) return null;
    final c =
        Offset((minX + maxX) / 2, (minY + maxY) / 2) -
        Offset(size.width / 2, size.height / 2);
    return (sc, -c * sc);
  }

  void _fit(Size size) {
    _viewport = size;
    final t = _fitTarget(size);
    if (t == null) return;
    _scale = t.$1;
    _pan = t.$2;
    _projectedFrame = -1;
    _fitted = true;
  }

  /// While true the camera keeps framing the graph as it settles; any
  /// manual zoom, pan or orbit hands control to the user.
  bool _autoFit = true;
  int _fitTick = 0;
  (double, Offset)? _fitGoal;

  bool _followFit() {
    final size = _viewport;
    if (!_autoFit || size == null || _n == 0) return false;
    if (_fitTick++ % 6 == 0) _fitGoal = _fitTarget(size);
    final g = _fitGoal;
    if (g == null) return false;
    final ds = g.$1 - _scale;
    final dp = g.$2 - _pan;
    if (ds.abs() < 0.002 && dp.distance < 0.5) return false;
    _scale += ds * 0.08;
    _pan += dp * 0.08;
    _projectedFrame = -1;
    return true;
  }

  void _zoomAt(double factor, Offset focal) {
    final size = _viewport;
    if (size == null) return;
    _autoFit = false;
    final next = (_scale * factor).clamp(0.05, 8.0);
    final applied = next / _scale;
    final c = Offset(size.width / 2, size.height / 2);
    _pan = focal - c - (focal - c - _pan) * applied;
    _scale = next;
    _projectedFrame = -1;
    _frame.value++;
  }

  void _attachCamera() {
    widget.cameraController?._attach(
      this,
      zoom: (f) {
        final s = _viewport;
        if (s != null) _zoomAt(f, Offset(s.width / 2, s.height / 2));
      },
      pan: (d) {
        _autoFit = false;
        _pan += d;
        _projectedFrame = -1;
        _frame.value++;
      },
      reset: () {
        final s = _viewport;
        if (s == null) return;
        _yaw = _threeD ? 0.5 : 0;
        _pitch = 0;
        _yawVel = _pitchVel = 0;
        _fit(s);
        _autoFit = true;
        _kick();
        _frame.value++;
      },
    );
  }

  // ---- Gestures ------------------------------------------------------------

  void _setFocus(int? i) {
    if (i != null) _focus = i;
    _focusAmt.target = i == null ? 0 : 1;
    if (_reduceMotion) _focusAmt.snap();
  }

  void _onDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    _yawVel = _pitchVel = 0;
    if (_pointers.length == 1) {
      _downPos = e.localPosition;
      _downStamp = e.timeStamp;
      _lastMoveStamp = e.timeStamp;
      _moved = false;
      final i = _hit(e.localPosition);
      if (i != null) {
        _gesture = _Gesture.node;
        _dragIndex = i;
        _dragX = _x[i];
        _dragY = _y[i];
        _dragZ = _z[i];
        _grab.target = 1.8;
        _setFocus(i);
        _ripple = 0;
        _rippleIndex = i;
        HapticFeedback.selectionClick();
      } else {
        _gesture = _Gesture.camera;
      }
    } else if (_pointers.length == 2) {
      _releaseNode(tapped: false);
      _startPinch();
    }
    _kick();
  }

  void _startPinch() {
    final pts = _pointers.values.toList();
    _gesture = _Gesture.pinch;
    _moved = true;
    _pinchDist = math.max(1, (pts[0] - pts[1]).distance);
    _pinchFocal = (pts[0] + pts[1]) / 2;
    _autoFit = false;
    _pinchScale = _scale;
    _pinchPan = _pan;
  }

  void _onMove(PointerMoveEvent e) {
    final prev = _pointers[e.pointer];
    if (prev == null) return;
    _pointers[e.pointer] = e.localPosition;
    final delta = e.localPosition - prev;
    if ((e.localPosition - _downPos).distance > kTouchSlop * 0.6) {
      _moved = true;
    }
    switch (_gesture) {
      case _Gesture.node:
        final i = _dragIndex;
        if (i == null || !_moved) return;
        final w = _unproject(e.localPosition, i);
        _dragX = w.$1;
        _dragY = w.$2;
        _dragZ = w.$3;
        _reheat(0.3);
      case _Gesture.camera:
        if (!_moved) return;
        if (_flat.target <= 0.5) _autoFit = false;
        final dtMs = math.max(1, (e.timeStamp - _lastMoveStamp).inMilliseconds);
        _lastMoveStamp = e.timeStamp;
        if (_flat.target > 0.5) {
          // Track the finger directly: a full-width swipe is a full orbit.
          // Decaying velocity continues the gesture smoothly on release.
          final yawDelta = delta.dx / math.max(1, _viewport!.width) * math.pi * 2;
          final pitchDelta = -delta.dy / math.max(1, _viewport!.height) * math.pi;
          _yaw += yawDelta;
          _pitch = (_pitch + pitchDelta).clamp(-1.35, 1.35);
          _yawVel = _yawVel * 0.42 + yawDelta / dtMs * 1000 * 0.58;
          _pitchVel = _pitchVel * 0.42 + pitchDelta / dtMs * 1000 * 0.58;
        } else {
          _pan += delta;
        }
        _projectedFrame = -1;
        _frame.value++;
      case _Gesture.pinch:
        final pts = _pointers.values.take(2).toList();
        if (pts.length < 2) return;
        final dist = math.max(1, (pts[0] - pts[1]).distance);
        final focal = (pts[0] + pts[1]) / 2;
        final size = _viewport!;
        final c = Offset(size.width / 2, size.height / 2);
        final next = (_pinchScale * dist / _pinchDist).clamp(0.05, 8.0);
        _pan = focal - c - (_pinchFocal - c - _pinchPan) * (next / _pinchScale);
        _scale = next;
        _projectedFrame = -1;
        _frame.value++;
      case _Gesture.none:
        break;
    }
  }

  void _releaseNode({required bool tapped}) {
    final i = _dragIndex;
    if (i == null) return;
    _dragIndex = null;
    // Fling: keep a bit of the finger's momentum, then settle springily.
    _vx[i] = _dragVX * 0.6;
    _vy[i] = _dragVY * 0.6;
    _grab.target = 1;
    if (tapped) {
      _setFocus(i);
    } else {
      _setFocus(null);
    }
    _reheat(0.22);
  }

  void _onUp(PointerEvent e, {bool cancelled = false}) {
    if (_pointers.remove(e.pointer) == null) return;
    final quick =
        (e.timeStamp - _downStamp) < const Duration(milliseconds: 600);
    switch (_gesture) {
      case _Gesture.node:
        final i = _dragIndex;
        final tapped = !cancelled && !_moved && quick && i != null;
        _releaseNode(tapped: tapped);
        _gesture = _Gesture.none;
        if (tapped) widget.onNodeTap(widget.data.nodes[i].path);
      case _Gesture.camera:
        if (!cancelled && !_moved && quick) {
          _setFocus(null);
          _yawVel = _pitchVel = 0;
        }
        if (_reduceMotion ||
            (e.timeStamp - _lastMoveStamp).inMilliseconds > 80) {
          _yawVel = _pitchVel = 0;
        }
        _gesture = _Gesture.none;
      case _Gesture.pinch:
        if (_pointers.length == 1) {
          // Continue as a one-finger orbit/pan without jumping.
          _gesture = _Gesture.camera;
          _downPos = _pointers.values.first;
          _lastMoveStamp = e.timeStamp;
        } else if (_pointers.isEmpty) {
          _gesture = _Gesture.none;
        }
        _yawVel = _pitchVel = 0;
      case _Gesture.none:
        break;
    }
    _kick();
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      _zoomAt(math.exp(-e.scrollDelta.dy / 400), e.localPosition);
    }
  }

  // ---- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _attachCamera();
    return LayoutBuilder(
      builder: (context, c) {
        final size = c.biggest;
        if (!_fitted || _viewport == null) {
          _fit(size);
          if (_reduceMotion) _settleNow();
          // Start animating after the first frame.
          WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
        } else if (_viewport != size) {
          _viewport = size;
          _projectedFrame = -1;
        }
        final scheme = Theme.of(context).colorScheme;
        _labelBase =
            Theme.of(context).textTheme.labelSmall ?? const TextStyle();
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: (e) => _onUp(e, cancelled: true),
          onPointerSignal: _onSignal,
          child: CustomPaint(
            key: GraphView.canvasKey,
            size: size,
            painter: _GraphPainter(this, scheme, _frame),
          ),
        );
      },
    );
  }

  TextStyle _labelBase = const TextStyle();

  TextPainter _label(int i, {required bool focus}) {
    final cache = focus ? _labelsFocus : _labels;
    return cache[i] ??= (TextPainter(
      text: TextSpan(
        text: widget.data.nodes[i].title,
        style: _labelBase.copyWith(
          color: focus ? SapphireTheme.onSurface : const Color(0xD9C9D3E6),
          fontSize: focus ? 12.5 : 11,
          fontWeight: focus ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: 0.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 170));
  }

  @visibleForTesting
  bool get colorsByFolder => _colorsByFolder;

  @visibleForTesting
  double get cameraScale => _scale;

  /// Path of the note whose links are currently highlighted, if any.
  @visibleForTesting
  String? get highlightedPath => _focus == null || _focusAmt.target == 0
      ? null
      : widget.data.nodes[_focus!].path;
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.s, this.scheme, Listenable frame) : super(repaint: frame);

  final GraphViewState s;
  final ColorScheme scheme;

  static const _bg = SapphireTheme.surface;

  @override
  void paint(Canvas canvas, Size size) {
    s._project(size);
    final data = s.widget.data;
    final n = s._n;
    if (n == 0) return;
    final zf = s._flat.value.clamp(0.0, 1.0);
    final fa = s._focusAmt.value.clamp(0.0, 1.0);
    final focus = s._focus;
    final neighbours = focus == null || fa == 0
        ? const <int>{}
        : s._adj[focus].toSet();
    final searching = s._matches.isNotEmpty;
    final centerIndex = data.center == null ? null : data.indexOf(data.center!);

    // Soft sapphire glow behind the cloud for depth.
    final glowR = size.shortestSide * 0.75;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      glowR,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                SapphireTheme.sapphireDeep.withValues(alpha: 0.10 + 0.06 * zf),
                SapphireTheme.sapphireDeep.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: Offset(size.width / 2, size.height / 2),
                radius: glowR,
              ),
            ),
    );

    // Depth range for fog.
    var dMin = double.infinity, dMax = -double.infinity;
    if (zf > 0.01) {
      for (var i = 0; i < n; i++) {
        dMin = math.min(dMin, s._sd[i]);
        dMax = math.max(dMax, s._sd[i]);
      }
    }
    double far(int i) => zf <= 0.01 || dMax - dMin < 1
        ? 0
        : ((s._sd[i] - dMin) / (dMax - dMin)) * zf;

    // ---- Edges ----
    final zoom = math.sqrt(s._scale).clamp(0.6, 1.8);
    final base = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.0 * zoom;
    const edgeColor = Color(0xFF4A5C82);
    final dash = Paint()
      ..strokeWidth = 1.0 * zoom
      ..color = SapphireTheme.violet.withValues(alpha: 0.55);
    final hiEdges = <GraphEdge>[];
    for (final e in data.edges) {
      final a = e.source, b = e.target;
      final lit = focus != null && fa > 0 && (a == focus || b == focus);
      if (lit) {
        hiEdges.add(e);
        continue;
      }
      final depth = (far(a) + far(b)) / 2;
      var alpha = 0.55 * (1 - depth * 0.6);
      if (fa > 0) alpha *= 1 - 0.8 * fa;
      if (searching &&
          !s._matches.contains(data.nodes[a].path) &&
          !s._matches.contains(data.nodes[b].path)) {
        alpha *= 0.35;
      }
      final pa = Offset(s._sx[a], s._sy[a]), pb = Offset(s._sx[b], s._sy[b]);
      if (e.kind == EdgeKind.explicit) {
        base.color = edgeColor.withValues(alpha: alpha);
        canvas.drawLine(pa, pb, base);
      } else {
        dash.color = SapphireTheme.violet.withValues(alpha: alpha);
        _dashed(canvas, pa, pb, dash, 5 * zoom);
      }
    }
    if (hiEdges.isNotEmpty) {
      final c = s._colors[focus!];
      final glow = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 6 * zoom
        ..color = c.withValues(alpha: 0.22 * fa)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      final line = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (1.0 + 1.4 * fa) * zoom
        ..color = Color.lerp(edgeColor, c, fa)!;
      for (final e in hiEdges) {
        final pa = Offset(s._sx[e.source], s._sy[e.source]);
        final pb = Offset(s._sx[e.target], s._sy[e.target]);
        canvas.drawLine(pa, pb, glow);
        if (e.kind == EdgeKind.explicit) {
          canvas.drawLine(pa, pb, line);
        } else {
          _dashed(canvas, pa, pb, line, 5 * zoom);
        }
      }
    }

    // A quiet signal travels along a small sample of real links, like neural
    // activity. It is based on existing edges and stays off with reduced motion.
    if (s._autoOrbit && !s._reduceMotion && data.edges.isNotEmpty) {
      final stride = math.max(1, (data.edges.length / 48).ceil());
      for (var e = 0; e < data.edges.length; e += stride) {
        final edge = data.edges[e];
        if (edge.kind != EdgeKind.explicit) continue;
        final a = Offset(s._sx[edge.source], s._sy[edge.source]);
        final b = Offset(s._sx[edge.target], s._sy[edge.target]);
        final phase = (s._motionSeconds * 0.42 + e * 0.173) % 1.0;
        final point = Offset.lerp(a, b, phase)!;
        final depthAlpha = 0.34 * (1 - (far(edge.source) + far(edge.target)) * 0.5);
        canvas.drawCircle(point, 2.0 * zoom, Paint()..color = const Color(0xFF9CEBDE).withValues(alpha: depthAlpha));
      }
    }
    // ---- Nodes (back to front) ----
    final fill = Paint();
    final ring = Paint()..style = PaintingStyle.stroke;
    final shine = Paint()..color = const Color(0x40FFFFFF);
    final showAll = n <= 40 || s._scale >= 1.15;
    for (var oi = 0; oi < n; oi++) {
      final i = s._order[oi];
      final node = data.nodes[i];
      final c = Offset(s._sx[i], s._sy[i]);
      if (c.dx < -40 ||
          c.dy < -40 ||
          c.dx > size.width + 40 ||
          c.dy > size.height + 40) {
        continue;
      }
      final isFocus = i == focus && fa > 0;
      final isNeighbour = neighbours.contains(i);
      var r = s._screenRadius(i);
      if (isNeighbour) r *= 1 + 0.28 * fa;
      final hit = s._matches.contains(node.path);

      var color = Color.lerp(s._colors[i], _bg, far(i) * 0.55)!;
      if (fa > 0 && !isFocus && !isNeighbour) {
        color = Color.lerp(color, _bg, 0.72 * fa)!;
      } else if (searching && !hit) {
        color = Color.lerp(color, _bg, 0.7)!;
      }

      if (isFocus) {
        canvas.drawCircle(
          c,
          r * 2.4,
          Paint()
            ..color = s._colors[i].withValues(alpha: 0.28 * fa)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
      if (changed) {
        canvas.drawCircle(
          c,
          r * 2.5,
          Paint()..color = const Color(0xFF69E6C1).withValues(alpha: 0.16),
        );
      }
      fill.color = color;
      canvas.drawCircle(c, r, fill);
      if (zf > 0.2 && r > 3) {
        shine.color = Color.fromRGBO(255, 255, 255, 0.28 * zf);
        canvas.drawCircle(c - Offset(r * 0.32, r * 0.32), r * 0.34, shine);
      }
      if (isFocus) {
        ring
          ..color = Colors.white.withValues(alpha: 0.95 * fa)
          ..strokeWidth = 1.6;
        canvas.drawCircle(c, r + 2.2, ring);
      } else if (isNeighbour) {
        ring
          ..color = s._colors[i].withValues(alpha: 0.9 * fa)
          ..strokeWidth = 1.2;
        canvas.drawCircle(c, r + 2, ring);
      }
      if (hit) {
        ring
          ..color = scheme.secondary
          ..strokeWidth = 2;
        canvas.drawCircle(c, r + 3.5, ring);
      }
      if (i == centerIndex) {
        ring
          ..color = scheme.tertiary
          ..strokeWidth = 2.2;
        canvas.drawCircle(c, r + 4.5, ring);
      }
      if (s.widget.pinnedPaths.contains(node.path)) {
        ring
          ..color = scheme.tertiary
          ..strokeWidth = 1.6;
        canvas.drawCircle(c, r + 7, ring);
        final m = Path()
          ..moveTo(c.dx, c.dy - r - 13)
          ..lineTo(c.dx + 3.5, c.dy - r - 9.5)
          ..lineTo(c.dx, c.dy - r - 6)
          ..lineTo(c.dx - 3.5, c.dy - r - 9.5)
          ..close();
        canvas.drawPath(m, Paint()..color = scheme.tertiary);
      }
      if (i == s._rippleIndex && s._ripple < 1) {
        final t = Curves.easeOutCubic.transform(s._ripple);
        ring
          ..color = s._colors[i].withValues(alpha: (1 - t) * 0.7)
          ..strokeWidth = 2 * (1 - t) + 0.5;
        canvas.drawCircle(c, r + 4 + 26 * t, ring);
      }

      // Labels: all when zoomed in or small; otherwise only the
      // highlighted neighbourhood, search hits and the local centre.
      final highlighted = isFocus || (isNeighbour && fa > 0.3);
      final show =
          highlighted ||
          hit ||
          i == centerIndex ||
          (showAll && fa < 0.5 && far(i) < 0.7);
      if (show) {
        final tp = s._label(i, focus: isFocus);
        final o = Offset(c.dx - tp.width / 2, c.dy + r + 4);
        if (isFocus) {
          final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(o.dx - 7, o.dy - 3, tp.width + 14, tp.height + 6),
            const Radius.circular(8),
          );
          canvas.drawRRect(
            rect,
            Paint()..color = SapphireTheme.surfaceHigh.withValues(alpha: 0.92),
          );
        }
        tp.paint(canvas, o);
      }
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p, double dash) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += dash * 2) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), p);
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (Size size) {
    s._project(size);
    final data = s.widget.data;
    return [
      for (var i = 0; i < s._n; i++)
        CustomPainterSemantics(
          rect: Rect.fromCircle(center: Offset(s._sx[i], s._sy[i]), radius: 22),
          properties: SemanticsProperties(
            label: data.nodes[i].title,
            textDirection: TextDirection.ltr,
            hint: 'Tap for note actions.',
            onTap: () => s.widget.onNodeTap(data.nodes[i].path),
            onLongPress: s.widget.onNodeLongPress == null
                ? null
                : () => s.widget.onNodeLongPress!(data.nodes[i].path),
          ),
        ),
    ];
  };

  @override
  bool shouldRebuildSemantics(_GraphPainter old) =>
      old.s.widget.data != s.widget.data;

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
