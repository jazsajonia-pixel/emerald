import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import 'graph_layout.dart';
import 'graph_model.dart';

/// Pan/zoom graph canvas. One [CustomPainter] draws all nodes and edges, so
/// it stays smooth with thousands of nodes; interaction uses Flutter's
/// [InteractiveViewer].
class GraphView extends StatefulWidget {
  const GraphView({
    super.key,
    required this.data,
    required this.layout,
    this.query = '',
    this.pinnedPaths = const {},
    required this.onNodeTap,
    this.onNodeLongPress,
  });

  final GraphData data;
  final GraphLayout layout;
  final String query;
  final Set<String> pinnedPaths;
  final ValueChanged<String> onNodeTap;
  final ValueChanged<String>? onNodeLongPress;

  static const canvasKey = Key('graph-canvas');

  static double nodeRadius(GraphNode n) =>
      math.min(16, 6 + math.sqrt(n.degree.toDouble()) * 2);

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  final _projection = const GraphProjection();
  AnimationController? _motion;
  Size? _fittedFor;
  GraphLayout? _fittedLayout;
  final _labels = <int, TextPainter>{};
  int? _emphasized;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    final shouldAnimate =
        !MediaQuery.of(context).disableAnimations &&
        widget.data.nodes.length <= 600;
    if (shouldAnimate && _motion == null) {
      _motion = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 18),
      )..repeat();
    } else if (!shouldAnimate && _motion != null) {
      _motion!.dispose();
      _motion = null;
    }
  }

  @override
  void didUpdateWidget(GraphView old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) _clearLabels();
    _syncMotion();
  }

  void _clearLabels() {
    for (final p in _labels.values) {
      p.dispose();
    }
    _labels.clear();
  }

  @override
  void dispose() {
    _clearLabels();
    _motion?.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _fit(Size viewport) {
    final l = widget.layout;
    final scale = math
        .min(viewport.width / l.width, viewport.height / l.height)
        .clamp(0.05, 1.5);
    final dx = (viewport.width - l.width * scale) / 2;
    final dy = (viewport.height - l.height * scale) / 2;
    _transform.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    _fittedFor = viewport;
    _fittedLayout = l;
  }

  int? _hit(Offset local) {
    final scale = _transform.value.getMaxScaleOnAxis();
    // GestureDetector reports coordinates in the InteractiveViewer child.
    // Invert each node's perspective projection before testing its layout
    // position. The raw-position pass is a forgiving fallback for a 48 dp
    // target during a zoom/pan transition.
    final origin = Offset(widget.layout.width / 2, widget.layout.height / 2);
    final radius = math.max(18, 24 / scale).toDouble();
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < widget.data.nodes.length; i++) {
      final depth = _projection.depthFor(i, widget.data.nodes[i].degree);
      final projected = _projection.project(
        Offset(widget.layout.x(i), widget.layout.y(i)),
        origin: origin,
        depth: depth,
      );
      final inverse = _projection.unproject(
        local,
        origin: origin,
        depth: depth,
      );
      final projectedDistance = (projected - local).distance;
      final layoutDistance =
          (Offset(widget.layout.x(i), widget.layout.y(i)) - inverse).distance;
      final distance = math.min(projectedDistance, layoutDistance);
      if (distance <= radius && distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best ?? widget.layout.hitTest(local.dx, local.dy, radius);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final viewport = c.biggest;
        // Fit to screen initially and whenever the set of nodes changes;
        // keep the user's zoom/pan when only positions are refined.
        if (_fittedFor == null ||
            _fittedLayout == null ||
            _fittedLayout!.length != widget.layout.length) {
          _fit(viewport);
        } else {
          _fittedLayout = widget.layout;
        }
        return InteractiveViewer(
          transformationController: _transform,
          constrained: false,
          minScale: 0.05,
          maxScale: 5,
          boundaryMargin: EdgeInsets.all(math.max(viewport.longestSide, 400)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final i = _hit(d.localPosition);
              if (i != null) {
                setState(() => _emphasized = i);
                widget.onNodeTap(widget.data.nodes[i].path);
              }
            },
            onLongPressStart: widget.onNodeLongPress == null
                ? null
                : (d) {
                    final i = _hit(d.localPosition);
                    if (i != null) {
                      setState(() => _emphasized = i);
                      widget.onNodeLongPress!(widget.data.nodes[i].path);
                    }
                  },
            child: CustomPaint(
              key: GraphView.canvasKey,
              size: Size(widget.layout.width, widget.layout.height),
              painter: _GraphPainter(
                data: widget.data,
                layout: widget.layout,
                query: widget.query.trim().toLowerCase(),
                pinnedPaths: widget.pinnedPaths,
                scheme: Theme.of(context).colorScheme,
                transform: _transform,
                labels: _labels,
                projection: _projection,
                emphasized: _emphasized,
                motion: _motion,
                onNodeTap: widget.onNodeTap,
                onNodeLongPress: widget.onNodeLongPress,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.data,
    required this.layout,
    required this.query,
    required this.pinnedPaths,
    required this.scheme,
    required this.transform,
    required this.labels,
    required this.projection,
    required this.emphasized,
    required this.motion,
    required this.onNodeTap,
    required this.onNodeLongPress,
  }) : super(
         repaint: motion == null
             ? transform
             : Listenable.merge([transform, motion]),
       );

  final GraphData data;
  final GraphLayout layout;
  final String query;
  final Set<String> pinnedPaths;
  final ColorScheme scheme;
  final TransformationController transform;
  final Map<int, TextPainter> labels;
  final GraphProjection projection;
  final int? emphasized;
  final Animation<double>? motion;
  final ValueChanged<String> onNodeTap;
  final ValueChanged<String>? onNodeLongPress;

  bool _matches(GraphNode n) =>
      query.isNotEmpty && n.title.toLowerCase().contains(query);

  Offset _origin() => Offset(layout.width / 2, layout.height / 2);

  double _depth(int i) => projection.depthFor(i, data.nodes[i].degree);

  Offset _point(int i) => projection.project(
    Offset(layout.x(i), layout.y(i)),
    origin: _origin(),
    depth: _depth(i),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final scale = transform.value.getMaxScaleOnAxis();
    final searching = query.isNotEmpty;
    final centerIndex = data.center == null ? null : data.indexOf(data.center!);
    final stroke = 1.2 / scale.clamp(0.4, 2);
    final pulse = motion?.value ?? 0;

    final edgePaint = Paint()
      ..color = scheme.primary.withValues(alpha: searching ? 0.15 : 0.45)
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke;
    final inferredPaint = Paint()
      ..color = scheme.tertiary.withValues(alpha: 0.6)
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke;
    final explicitPath = Path();
    for (final e in data.edges) {
      final a = _point(e.source);
      final b = _point(e.target);
      if (e.kind == EdgeKind.explicit) {
        explicitPath
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      } else {
        _dashed(canvas, a, b, inferredPaint, 6 / scale.clamp(0.4, 2));
      }
    }
    canvas.drawPath(explicitPath, edgePaint);

    final isolatedFill = Paint()..color = scheme.surfaceContainerHighest;
    final isolatedRing = Paint()
      ..color = scheme.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final hiRing = Paint()
      ..color = scheme.secondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final centerRing = Paint()
      ..color = scheme.tertiary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final emphasisRing = Paint()
      ..color = scheme.onSurface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    final pinnedRing = Paint()
      ..color = scheme.tertiary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    final pinnedMarker = Paint()..color = scheme.tertiary;

    final showAllLabels = data.nodes.length <= 40 || scale >= 0.9;
    for (var i = 0; i < data.nodes.length; i++) {
      final n = data.nodes[i];
      final c = _point(i);
      final depth = _depth(i);
      final depthScale = projection.scaleForDepth(depth);
      final r = GraphView.nodeRadius(n) * depthScale;
      final hit = _matches(n);
      final isEmphasized = i == emphasized;
      final isPinned = pinnedPaths.contains(n.path);
      final shimmer = motion == null
          ? 0.0
          : (math.sin(pulse * math.pi * 2 + i * 0.37) + 1) / 2;
      final depthMix = (depth / 140).clamp(0.0, 1.0);
      final linkedFill = Color.lerp(scheme.primary, scheme.tertiary, depthMix)!;
      final nodeFill = searching && !hit
          ? linkedFill.withValues(alpha: 0.25)
          : linkedFill.withValues(alpha: 0.82 + shimmer * 0.12);
      final shadow = Paint()
        ..color = scheme.shadow.withValues(alpha: 0.14 + depthMix * 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(
        c + Offset(1.5 + depthMix * 2, 2.5 + depthMix * 2),
        r,
        shadow,
      );
      if (n.isolated) {
        final diamond = Path()
          ..moveTo(c.dx, c.dy - r)
          ..lineTo(c.dx + r, c.dy)
          ..lineTo(c.dx, c.dy + r)
          ..lineTo(c.dx - r, c.dy)
          ..close();
        canvas.drawPath(diamond, isolatedFill);
        canvas.drawPath(diamond, isolatedRing);
      } else {
        canvas.drawCircle(c, r, Paint()..color = nodeFill);
      }
      if (hit) canvas.drawCircle(c, r + 4, hiRing);
      if (i == centerIndex) canvas.drawCircle(c, r + 5, centerRing);
      if (isPinned) {
        canvas.drawCircle(c, r + 10, pinnedRing);
        final marker = Path()
          ..moveTo(c.dx, c.dy - r - 15)
          ..lineTo(c.dx + 4, c.dy - r - 11)
          ..lineTo(c.dx, c.dy - r - 7)
          ..lineTo(c.dx - 4, c.dy - r - 11)
          ..close();
        canvas.drawPath(marker, pinnedMarker);
      }
      if (isEmphasized) {
        canvas.drawCircle(c, r + 8 + shimmer * 2, emphasisRing);
        canvas.drawLine(
          c - const Offset(12, 0),
          c + const Offset(12, 0),
          emphasisRing,
        );
        canvas.drawLine(
          c - const Offset(0, 12),
          c + const Offset(0, 12),
          emphasisRing,
        );
      }
      if (showAllLabels || hit || i == centerIndex) {
        final tp = labels[i] ??= (TextPainter(
          text: TextSpan(
            text: n.title,
            style: TextStyle(color: scheme.onSurface, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 160));
        final labelScale = 1 / scale.clamp(0.6, 1.6);
        canvas.save();
        canvas.translate(c.dx, c.dy + r + 3);
        canvas.scale(labelScale);
        tp.paint(canvas, Offset(-tp.width / 2, 0));
        canvas.restore();
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
    return [
      for (var i = 0; i < data.nodes.length; i++)
        CustomPainterSemantics(
          rect: Rect.fromCircle(
            center: _point(i),
            radius: math
                .max(24, GraphView.nodeRadius(data.nodes[i]))
                .toDouble(),
          ),
          properties: SemanticsProperties(
            label: data.nodes[i].title,
            textDirection: TextDirection.ltr,
            hint: 'Tap for note actions. Long press to focus its local graph.',
            onTap: () => onNodeTap(data.nodes[i].path),
            onLongPress: onNodeLongPress == null
                ? null
                : () => onNodeLongPress!(data.nodes[i].path),
          ),
        ),
    ];
  };

  @override
  bool shouldRebuildSemantics(_GraphPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.layout != layout ||
      oldDelegate.emphasized != emphasized;

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.data != data ||
      old.layout != layout ||
      old.query != query ||
      old.scheme != scheme ||
      old.pinnedPaths != pinnedPaths ||
      old.emphasized != emphasized ||
      old.motion != motion;
}
