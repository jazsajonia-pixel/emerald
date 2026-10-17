import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    required this.onNodeTap,
    this.onNodeLongPress,
  });

  final GraphData data;
  final GraphLayout layout;
  final String query;
  final ValueChanged<String> onNodeTap;
  final ValueChanged<String>? onNodeLongPress;

  static const canvasKey = Key('graph-canvas');

  static double nodeRadius(GraphNode n) =>
      math.min(16, 6 + math.sqrt(n.degree.toDouble()) * 2);

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView> {
  final _transform = TransformationController();
  Size? _fittedFor;
  GraphLayout? _fittedLayout;
  final _labels = <int, TextPainter>{};

  @override
  void didUpdateWidget(GraphView old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) _clearLabels();
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
    // At least a 48 dp touch target regardless of zoom.
    return widget.layout.hitTest(local.dx, local.dy, math.max(18, 24 / scale));
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
              if (i != null) widget.onNodeTap(widget.data.nodes[i].path);
            },
            onLongPressStart: widget.onNodeLongPress == null
                ? null
                : (d) {
                    final i = _hit(d.localPosition);
                    if (i != null) {
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
                scheme: Theme.of(context).colorScheme,
                transform: _transform,
                labels: _labels,
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
    required this.scheme,
    required this.transform,
    required this.labels,
  }) : super(repaint: transform);

  final GraphData data;
  final GraphLayout layout;
  final String query;
  final ColorScheme scheme;
  final TransformationController transform;
  final Map<int, TextPainter> labels;

  bool _matches(GraphNode n) =>
      query.isNotEmpty && n.title.toLowerCase().contains(query);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = transform.value.getMaxScaleOnAxis();
    final searching = query.isNotEmpty;
    final centerIndex = data.center == null ? null : data.indexOf(data.center!);
    final stroke = 1.2 / scale.clamp(0.4, 2);

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
      final a = Offset(layout.x(e.source), layout.y(e.source));
      final b = Offset(layout.x(e.target), layout.y(e.target));
      if (e.kind == EdgeKind.explicit) {
        explicitPath
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      } else {
        _dashed(canvas, a, b, inferredPaint, 6 / scale.clamp(0.4, 2));
      }
    }
    canvas.drawPath(explicitPath, edgePaint);

    final linked = Paint()..color = scheme.primary;
    final dim = Paint()..color = scheme.primary.withValues(alpha: 0.25);
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

    final showAllLabels = data.nodes.length <= 40 || scale >= 0.9;
    for (var i = 0; i < data.nodes.length; i++) {
      final n = data.nodes[i];
      final c = Offset(layout.x(i), layout.y(i));
      final r = GraphView.nodeRadius(n);
      final hit = _matches(n);
      if (n.isolated) {
        canvas.drawCircle(c, r, isolatedFill);
        canvas.drawCircle(c, r, isolatedRing);
      } else {
        canvas.drawCircle(c, r, searching && !hit ? dim : linked);
      }
      if (hit) canvas.drawCircle(c, r + 4, hiRing);
      if (i == centerIndex) canvas.drawCircle(c, r + 5, centerRing);
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
  bool shouldRepaint(_GraphPainter old) =>
      old.data != data ||
      old.layout != layout ||
      old.query != query ||
      old.scheme != scheme;
}
