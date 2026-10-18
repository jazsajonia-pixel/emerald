import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

/// Result of a layout: node centres (x0, y0, x1, y1, …) inside a canvas of
/// [width] × [height].
class GraphLayout {
  const GraphLayout(this.xy, this.width, this.height);
  final Float64List xy;
  final double width;
  final double height;

  int get length => xy.length ~/ 2;
  double x(int i) => xy[2 * i];
  double y(int i) => xy[2 * i + 1];

  /// Index of the node closest to ([px], [py]) within [radius], or null.
  int? hitTest(double px, double py, double radius) {
    int? best;
    var bestD = radius * radius;
    for (var i = 0; i < length; i++) {
      final dx = x(i) - px, dy = y(i) - py;
      final d = dx * dx + dy * dy;
      if (d <= bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }
}

/// Perspective projection helpers for Emerald's animated 3D graph view.
///
/// The force layout stays deterministic and inexpensive in 2D. The graph view
/// lifts its nodes into a shallow 3D volume and rotates that volume before
/// projecting it onto the canvas, including perspective foreshortening.
class GraphProjection {
  const GraphProjection({this.focalLength = 2200, this.nearPlane = 0.25});

  /// Distance at which the perspective scale would become unstable.
  final double nearPlane;

  /// Larger values keep the graph readable while still giving depth cues.
  final double focalLength;

  /// Stable pseudo-depth in logical pixels for a node.
  ///
  /// It depends only on the node index and degree, so layout refreshes and
  /// rebuilds do not make the graph appear to jump between depth layers.
  double depthFor(int index, int degree) {
    final seed = (index * 37 + degree * 17) & 0x7fffffff;
    return 18 + (seed % 120).toDouble();
  }

  double scaleForDepth(double depth) {
    final safeNear = nearPlane.isFinite && nearPlane > 0 ? nearPlane : 0.25;
    final safeDepth = depth.isFinite ? math.max(safeNear, depth) : safeNear;
    final safeFocal = focalLength.isFinite && focalLength > safeNear
        ? focalLength
        : 1;
    final scale = safeFocal / (safeFocal + safeDepth);
    return scale.isFinite && scale > 0 ? scale : 1;
  }

  /// Projects a layout point around [origin] onto the graph's 2D canvas.
  Offset project(Offset point, {required Offset origin, double depth = 0}) {
    final s = scaleForDepth(depth);
    final projected = origin + (point - origin) * s;
    return _finite(projected, fallback: origin);
  }

  /// Rotates a node around the vertical axis, tilts the resulting 3D point,
  /// then projects it using perspective. [rotation] is in radians.
  Offset projectRotating(
    Offset point, {
    required Offset origin,
    required double depth,
    required double rotation,
    double tilt = 0.18,
  }) {
    final dx = point.dx - origin.dx;
    final dy = point.dy - origin.dy;
    final z = depth - 78;
    final yawX = dx * math.cos(rotation) + z * math.sin(rotation);
    final yawZ = -dx * math.sin(rotation) + z * math.cos(rotation);
    final screenY = dy * math.cos(tilt) - yawZ * math.sin(tilt);
    final cameraZ = dy * math.sin(tilt) + yawZ * math.cos(tilt);
    final perspective = (focalLength / (focalLength + cameraZ)).clamp(
      0.45,
      1.65,
    );
    final projected =
        origin + Offset(yawX * perspective, screenY * perspective);
    return _finite(projected, fallback: origin);
  }

  /// Reverses [project] for hit testing at a known node depth.
  Offset unproject(Offset point, {required Offset origin, double depth = 0}) {
    final s = scaleForDepth(depth);
    final unprojected = origin + (point - origin) / s;
    return _finite(unprojected, fallback: origin);
  }

  static Offset _finite(Offset value, {required Offset fallback}) {
    if (value.dx.isFinite && value.dy.isFinite) return value;
    return fallback;
  }
}

class LayoutInput {
  const LayoutInput(this.nodeCount, this.edges, {this.initial, this.seed = 7});

  final int nodeCount;

  /// Flat list of undirected edges (a0, b0, a1, b1, …).
  final Int32List edges;

  /// Optional starting positions (NaN = unknown) so the picture stays stable
  /// after small changes.
  final Float64List? initial;
  final int seed;
}

/// Force-directed (Fruchterman–Reingold) layout with grid-based repulsion so
/// cost grows roughly linearly with the number of nodes.
abstract final class GraphLayouter {
  static const double idealEdge = 70;
  static const double padding = 60;

  /// Graphs at or below this size are laid out synchronously.
  static const int syncLimit = 150;

  static Future<GraphLayout> layout(LayoutInput input) {
    if (input.nodeCount <= syncLimit) return Future.value(compute(input));
    return Isolate.run(() => compute(input));
  }

  static GraphLayout compute(LayoutInput input) {
    final n = input.nodeCount;
    if (n == 0) return GraphLayout(Float64List(0), padding * 2, padding * 2);
    final rnd = math.Random(input.seed);
    final k = idealEdge;
    final spread = k * math.sqrt(n) * 0.8 + k;
    final px = Float64List(n), py = Float64List(n);
    for (var i = 0; i < n; i++) {
      final ix = input.initial != null && 2 * i + 1 < input.initial!.length
          ? input.initial![2 * i]
          : double.nan;
      final iy = input.initial != null && 2 * i + 1 < input.initial!.length
          ? input.initial![2 * i + 1]
          : double.nan;
      if (ix.isFinite && iy.isFinite) {
        px[i] = ix;
        py[i] = iy;
      } else {
        final a = rnd.nextDouble() * math.pi * 2;
        final r = spread * math.sqrt(rnd.nextDouble());
        px[i] = r * math.cos(a);
        py[i] = r * math.sin(a);
      }
    }
    if (n == 1) return _finish(px, py);

    final dx = Float64List(n), dy = Float64List(n);
    final edges = input.edges;
    final iterations = n <= 200 ? 300 : (n <= 1000 ? 200 : 120);
    final cell = k * 2;
    var temp = spread / 4;
    final cooling = temp / (iterations + 1);
    final grid = <int, List<int>>{};

    for (var it = 0; it < iterations; it++) {
      dx.fillRange(0, n, 0);
      dy.fillRange(0, n, 0);
      grid.clear();
      for (var i = 0; i < n; i++) {
        final key = _cellKey((px[i] / cell).floor(), (py[i] / cell).floor());
        (grid[key] ??= <int>[]).add(i);
      }
      // Repulsion between nodes in neighbouring cells.
      for (var i = 0; i < n; i++) {
        final cx = (px[i] / cell).floor(), cy = (py[i] / cell).floor();
        for (var gx = cx - 1; gx <= cx + 1; gx++) {
          for (var gy = cy - 1; gy <= cy + 1; gy++) {
            final bucket = grid[_cellKey(gx, gy)];
            if (bucket == null) continue;
            for (final j in bucket) {
              if (j <= i) continue;
              var ddx = px[i] - px[j], ddy = py[i] - py[j];
              var d2 = ddx * ddx + ddy * ddy;
              if (d2 < 0.01) {
                ddx = rnd.nextDouble() - 0.5;
                ddy = rnd.nextDouble() - 0.5;
                d2 = 0.01;
              }
              final d = math.sqrt(d2);
              if (d > cell * 1.5) continue;
              final f = k * k / d;
              final fx = ddx / d * f, fy = ddy / d * f;
              dx[i] += fx;
              dy[i] += fy;
              dx[j] -= fx;
              dy[j] -= fy;
            }
          }
        }
      }
      // Attraction along edges.
      for (var e = 0; e + 1 < edges.length; e += 2) {
        final a = edges[e], b = edges[e + 1];
        final ddx = px[a] - px[b], ddy = py[a] - py[b];
        final d = math.sqrt(ddx * ddx + ddy * ddy) + 0.01;
        final f = d * d / k;
        final fx = ddx / d * f, fy = ddy / d * f;
        dx[a] -= fx;
        dy[a] -= fy;
        dx[b] += fx;
        dy[b] += fy;
      }
      // Gentle gravity keeps disconnected parts and isolated notes nearby.
      for (var i = 0; i < n; i++) {
        dx[i] -= px[i] * 0.03;
        dy[i] -= py[i] * 0.03;
        final d = math.sqrt(dx[i] * dx[i] + dy[i] * dy[i]);
        if (d > 0) {
          final lim = math.min(d, temp);
          px[i] += dx[i] / d * lim;
          py[i] += dy[i] / d * lim;
        }
      }
      temp = math.max(temp - cooling, 1);
    }
    return _finish(px, py);
  }

  static int _cellKey(int x, int y) => (x + 0x8000) * 0x10000 + (y + 0x8000);

  static GraphLayout _finish(Float64List px, Float64List py) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < px.length; i++) {
      minX = math.min(minX, px[i]);
      minY = math.min(minY, py[i]);
      maxX = math.max(maxX, px[i]);
      maxY = math.max(maxY, py[i]);
    }
    final xy = Float64List(px.length * 2);
    for (var i = 0; i < px.length; i++) {
      xy[2 * i] = px[i] - minX + padding;
      xy[2 * i + 1] = py[i] - minY + padding;
    }
    return GraphLayout(
      xy,
      maxX - minX + padding * 2,
      maxY - minY + padding * 2,
    );
  }
}
