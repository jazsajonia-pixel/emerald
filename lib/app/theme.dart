import 'package:flutter/material.dart';

/// Emerald visual identity: dark surfaces with restrained emerald accents.
abstract final class EmeraldTheme {
  static const Color emerald = Color(0xFF2EB67D);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.dark,
    ).copyWith(surface: const Color(0xFF0F1513));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
      ),
    );
  }
}
