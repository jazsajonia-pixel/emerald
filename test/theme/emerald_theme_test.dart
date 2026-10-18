import 'package:emerald/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dark theme keeps the Emerald palette anchored to ink surfaces', () {
    final theme = EmeraldTheme.dark();

    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, EmeraldTheme.emerald);
    expect(theme.colorScheme.surface, EmeraldTheme.surface);
    expect(theme.scaffoldBackgroundColor, EmeraldTheme.surface);
    expect(theme.navigationBarTheme.backgroundColor, EmeraldTheme.ink);
    expect(theme.navigationRailTheme.backgroundColor, EmeraldTheme.ink);
  });

  testWidgets('Emerald mark exposes an accessible image label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: EmeraldTheme.dark(),
        home: const Scaffold(body: Center(child: EmeraldMark())),
      ),
    );

    expect(find.bySemanticsLabel('Emerald'), findsOneWidget);
    expect(find.byType(CustomPaint), findsOneWidget);
  });
}
