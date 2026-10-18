import 'package:flutter/material.dart';

/// Emerald visual identity: a quiet ink canvas with crisp, living green accents.
abstract final class EmeraldTheme {
  static const Color emerald = Color(0xFF57E39F);
  static const Color ink = Color(0xFF08110F);
  static const Color surface = Color(0xFF0D1815);
  static const Color surfaceLow = Color(0xFF11211C);
  static const Color surfaceHigh = Color(0xFF1B342B);
  static const Color surfaceHighest = Color(0xFF234238);
  static const Color onSurface = Color(0xFFE4F2EB);
  static const Color onSurfaceVariant = Color(0xFFA7BDB2);
  static const Color outline = Color(0xFF88A89A);
  static const Color outlineVariant = Color(0xFF3C574B);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.dark,
    ).copyWith(
      primary: emerald,
      onPrimary: ink,
      primaryContainer: const Color(0xFF075334),
      onPrimaryContainer: const Color(0xFFA4F6C7),
      secondary: const Color(0xFFA8D9C2),
      onSecondary: const Color(0xFF11372A),
      secondaryContainer: const Color(0xFF254F3D),
      onSecondaryContainer: const Color(0xFFC2F4DC),
      tertiary: const Color(0xFFB8D3C8),
      onTertiary: const Color(0xFF20362D),
      tertiaryContainer: const Color(0xFF385047),
      onTertiaryContainer: const Color(0xFFD4EDE1),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      errorContainer: const Color(0xFF93000A),
      onErrorContainer: const Color(0xFFFFDAD6),
      background: surface,
      surface: surface,
      surfaceDim: ink,
      surfaceBright: surfaceHighest,
      surfaceContainerLowest: ink,
      surfaceContainerLow: surfaceLow,
      surfaceContainer: const Color(0xFF162A23),
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHighest,
      surfaceTint: emerald,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: onSurface,
      onInverseSurface: surface,
      inversePrimary: const Color(0xFF006C46),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: ink,
      cardColor: surfaceLow,
      visualDensity: VisualDensity.standard,
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
      cardTheme: CardTheme(
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
            color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
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

/// A compact geometric Emerald mark shared by in-app chrome and Android assets.
///
/// The faceted silhouette stays legible at small sizes and uses only the app's
/// palette, so it remains crisp without a raster asset or an extra dependency.
class EmeraldMark extends StatelessWidget {
  const EmeraldMark({
    super.key,
    this.size = 40,
    this.semanticsLabel = 'Emerald',
  });

  final double size;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _EmeraldMarkPainter()),
      ),
    );
  }
}

class _EmeraldMarkPainter extends CustomPainter {
  const _EmeraldMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outer = Path()
      ..moveTo(w * 0.5, h * 0.04)
      ..lineTo(w * 0.91, h * 0.29)
      ..lineTo(w * 0.73, h * 0.85)
      ..lineTo(w * 0.5, h * 0.98)
      ..lineTo(w * 0.27, h * 0.85)
      ..lineTo(w * 0.09, h * 0.29)
      ..close();
    canvas.drawPath(outer, Paint()..color = const Color(0xFF12352A));

    final leftFacet = Path()
      ..moveTo(w * 0.5, h * 0.08)
      ..lineTo(w * 0.13, h * 0.3)
      ..lineTo(w * 0.4, h * 0.39)
      ..lineTo(w * 0.5, h * 0.92)
      ..close();
    canvas.drawPath(leftFacet, Paint()..color = EmeraldTheme.emerald);

    final rightFacet = Path()
      ..moveTo(w * 0.5, h * 0.08)
      ..lineTo(w * 0.87, h * 0.3)
      ..lineTo(w * 0.6, h * 0.39)
      ..lineTo(w * 0.5, h * 0.92)
      ..close();
    canvas.drawPath(rightFacet, Paint()..color = const Color(0xFF35BF7B));

    final centerFacet = Path()
      ..moveTo(w * 0.4, h * 0.39)
      ..lineTo(w * 0.6, h * 0.39)
      ..lineTo(w * 0.5, h * 0.92)
      ..close();
    canvas.drawPath(centerFacet, Paint()..color = const Color(0xFF16895B));

    canvas.drawPath(
      outer,
      Paint()
        ..color = const Color(0xFFA4F6C7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.035
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _EmeraldMarkPainter oldDelegate) => false;
}
