import 'package:sapphire/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dark theme keeps the Sapphire palette anchored to ink surfaces', () {
    final theme = SapphireTheme.dark();

    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, SapphireTheme.sapphire);
    expect(theme.colorScheme.surface, SapphireTheme.surface);
    expect(theme.scaffoldBackgroundColor, SapphireTheme.surface);
    expect(theme.navigationBarTheme.backgroundColor, SapphireTheme.ink);
    expect(theme.navigationRailTheme.backgroundColor, SapphireTheme.ink);
  });

  testWidgets('Sapphire mark exposes an accessible image label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SapphireTheme.dark(),
        home: const Scaffold(body: Center(child: SapphireMark())),
      ),
    );

    expect(find.bySemanticsLabel('Sapphire'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SapphireMark),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });
}
