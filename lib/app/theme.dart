import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Sapphire visual identity: a deep navy canvas with crisp sapphire-blue
/// accents, ice-cyan highlights and solid jewel tones for the graph.
abstract final class SapphireTheme {
  /// Primary accent: a luminous sapphire blue that keeps AA contrast on ink.
  static const Color sapphire = Color(0xFF7AA2FF);
  static const Color sapphireDeep = Color(0xFF2F5BEA);
  static const Color ice = Color(0xFF8ED8FF);
  static const Color violet = Color(0xFFB7A6FF);
  static const Color ink = Color(0xFF060A16);
  static const Color surface = Color(0xFF0A1020);
  static const Color surfaceLow = Color(0xFF0F1729);
  static const Color surfaceMid = Color(0xFF131D33);
  static const Color surfaceHigh = Color(0xFF19253F);
  static const Color surfaceHighest = Color(0xFF21304F);
  static const Color onSurface = Color(0xFFE6ECF8);
  static const Color onSurfaceVariant = Color(0xFFA3B0C8);
  static const Color outline = Color(0xFF7D8AA6);
  static const Color outlineVariant = Color(0xFF2C3A57);

  /// Solid, distinct colors for graph nodes (one per folder group).
  static const List<Color> nodePalette = [
    Color(0xFF5B8CFF), // sapphire
    Color(0xFF3CC8F0), // cyan
    Color(0xFF9B7BFF), // violet
    Color(0xFF2FD3B2), // teal
    Color(0xFFFFB547), // amber
    Color(0xFFFF6B8B), // rose
    Color(0xFFA6E35A), // lime
    Color(0xFFFF8A5B), // coral
    Color(0xFF7FC4FF), // sky
    Color(0xFFE07BFF), // orchid
  ];
  static const Color unresolvedNode = Color(0xFF5E6A85);

  /// Soft background glow used behind hero areas.
  static const RadialGradient heroGlow = RadialGradient(
    center: Alignment(-0.6, -0.9),
    radius: 1.3,
    colors: [Color(0x332F5BEA), Color(0x00060A16)],
  );

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: sapphire,
          brightness: Brightness.dark,
        ).copyWith(
          primary: sapphire,
          onPrimary: ink,
          primaryContainer: const Color(0xFF1C3A8A),
          onPrimaryContainer: const Color(0xFFDCE6FF),
          secondary: ice,
          onSecondary: const Color(0xFF00354A),
          secondaryContainer: const Color(0xFF15405A),
          onSecondaryContainer: const Color(0xFFCDEEFF),
          tertiary: violet,
          onTertiary: const Color(0xFF2A1A66),
          tertiaryContainer: const Color(0xFF3B2F7A),
          onTertiaryContainer: const Color(0xFFE6DEFF),
          error: const Color(0xFFFFB4AB),
          onError: const Color(0xFF690005),
          errorContainer: const Color(0xFF93000A),
          onErrorContainer: const Color(0xFFFFDAD6),
          surface: surface,
          surfaceDim: ink,
          surfaceBright: surfaceHighest,
          surfaceContainerLowest: ink,
          surfaceContainerLow: surfaceLow,
          surfaceContainer: surfaceMid,
          surfaceContainerHigh: surfaceHigh,
          surfaceContainerHighest: surfaceHighest,
          surfaceTint: sapphire,
          onSurface: onSurface,
          onSurfaceVariant: onSurfaceVariant,
          outline: outline,
          outlineVariant: outlineVariant,
          shadow: Colors.black,
          scrim: Colors.black,
          inverseSurface: onSurface,
          onInverseSurface: surface,
          inversePrimary: sapphireDeep,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: ink,
      cardColor: surfaceLow,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceLow,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? ink : outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? sapphire : surfaceHigh,
        ),
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.72),
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surfaceLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ink,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: scheme.onSurfaceVariant),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: ink,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHighest,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        actionTextColor: scheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Sapphire's mark: a front-view cut gem (table, crown and pavilion facets)
/// lit from the upper left, with a small sparkle. Drawn with the same
/// geometry as the Android launcher icon, so the brand stays consistent and
/// crisp at any size without raster assets.
class SapphireMark extends StatelessWidget {
  const SapphireMark({
    super.key,
    this.size = 40,
    this.semanticsLabel = 'Sapphire',
    this.sparkle = true,
  });

  final double size;
  final String semanticsLabel;
  final bool sparkle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: SapphireMarkPainter(sparkle: sparkle)),
      ),
    );
  }
}

class SapphireMarkPainter extends CustomPainter {
  const SapphireMarkPainter({this.sparkle = true, this.glint = 0});

  final bool sparkle;

  /// 0..1 position of a moving light glint across the gem (0 = none).
  final double glint;

  /// Facets in unit coordinates with their solid fill colors.
  static const facets = <(List<Offset>, Color)>[
    // Crown (upper) facets.
    ([Offset(.28, .16), Offset(.06, .40), Offset(.30, .40)], Color(0xFF6E9CFF)),
    ([Offset(.28, .16), Offset(.50, .16), Offset(.30, .40)], Color(0xFFA9CBFF)),
    ([Offset(.50, .16), Offset(.30, .40), Offset(.70, .40)], Color(0xFFD3E6FF)),
    ([Offset(.50, .16), Offset(.72, .16), Offset(.70, .40)], Color(0xFF7FA9FF)),
    ([Offset(.72, .16), Offset(.94, .40), Offset(.70, .40)], Color(0xFF3D6CF0)),
    // Pavilion (lower) facets.
    ([Offset(.06, .40), Offset(.30, .40), Offset(.50, .90)], Color(0xFF2F62E6)),
    ([Offset(.30, .40), Offset(.70, .40), Offset(.50, .90)], Color(0xFF1D46BE)),
    ([Offset(.70, .40), Offset(.94, .40), Offset(.50, .90)], Color(0xFF12318E)),
  ];

  static const outline = [
    Offset(.28, .16),
    Offset(.72, .16),
    Offset(.94, .40),
    Offset(.50, .90),
    Offset(.06, .40),
  ];

  static Path _path(List<Offset> pts, Size size) {
    final p = Path()..moveTo(pts[0].dx * size.width, pts[0].dy * size.height);
    for (final o in pts.skip(1)) {
      p.lineTo(o.dx * size.width, o.dy * size.height);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final gem = _path(outline, size);
    for (final (pts, color) in facets) {
      canvas.drawPath(_path(pts, size), Paint()..color = color);
    }
    if (glint > 0 && glint < 1) {
      canvas.save();
      canvas.clipPath(gem);
      final x = (glint * 1.6 - 0.3) * w;
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: const [
              Color(0x00FFFFFF),
              Color(0x66FFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: const [0, 0.5, 1],
          ).createShader(Rect.fromLTWH(x - w * 0.25, 0, w * 0.5, size.height)),
      );
      canvas.restore();
    }
    // Hairline facet edges keep the cut readable at small sizes.
    final edge = Paint()
      ..color = const Color(0xFF17389A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.012
      ..strokeJoin = StrokeJoin.round;
    for (final (pts, _) in facets) {
      canvas.drawPath(_path(pts, size), edge);
    }
    canvas.drawPath(
      gem,
      Paint()
        ..color = const Color(0xFFE3EEFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.03
        ..strokeJoin = StrokeJoin.round,
    );
    if (sparkle) {
      final c = Offset(w * 0.84, size.height * 0.13);
      final r = w * 0.09;
      final star = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
        ..close();
      canvas.drawPath(star, Paint()..color = const Color(0xFFF2F7FF));
    }
  }

  @override
  bool shouldRepaint(covariant SapphireMarkPainter old) =>
      old.sparkle != sparkle || old.glint != glint;
}

/// The mark with a slow light glint passing over it (static under reduced
/// motion).
class AnimatedSapphireMark extends StatefulWidget {
  const AnimatedSapphireMark({super.key, this.size = 40});
  final double size;

  @override
  State<AnimatedSapphireMark> createState() => _AnimatedSapphireMarkState();
}

class _AnimatedSapphireMarkState extends State<AnimatedSapphireMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sapphire',
    image: true,
    child: SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: SapphireMarkPainter(
            // Glint passes during the first 30% of each cycle.
            glint: _c.value < 0.3 ? _c.value / 0.3 : 0,
          ),
        ),
      ),
    ),
  );
}
