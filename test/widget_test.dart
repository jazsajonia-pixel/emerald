import 'package:emerald/app/home_shell.dart';
import 'package:emerald/core/ui/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

Future<void> _pumpAt(
  WidgetTester tester,
  Size size, {
  double textScale = 1.0,
}) => pumpEmerald(tester, size: size, textScale: textScale);

void main() {
  const phone = Size(360, 740);
  const tablet = Size(1000, 800);

  testWidgets('launches on Home with bottom navigation on a phone', (
    tester,
  ) async {
    await _pumpAt(tester, phone);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('No vault selected'), findsWidgets);
  });

  testWidgets('every destination opens without errors', (tester) async {
    await _pumpAt(tester, phone);
    final expectedTitles = {
      AppDestination.notes: 'Brain',
      AppDestination.graph: 'Graph',
      AppDestination.ai: 'AI Hub',
      AppDestination.settings: 'Settings',
      AppDestination.home: 'Emerald',
    };
    for (final entry in expectedTitles.entries) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(entry.key.label),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(entry.value),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('incomplete features are labelled, not faked', (tester) async {
    await _pumpAt(tester, phone);
    await tester.tap(find.text('AI Hub'));
    await tester.pumpAndSettle();
    expect(find.byType(NotYetAvailable), findsOneWidget);
    expect(find.textContaining('not available yet'), findsOneWidget);
  });

  testWidgets('home quick action navigates to Graph', (tester) async {
    await _pumpAt(tester, phone);
    await tester.tap(find.text('Open Graph'));
    await tester.pumpAndSettle();
    expect(find.text('No graph yet'), findsOneWidget);
  });

  testWidgets('wide screens use a navigation rail', (tester) async {
    await _pumpAt(tester, tablet);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy'), findsOneWidget);
  });

  testWidgets('large text scale does not overflow on a narrow phone', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(320, 640), textScale: 2.0);
    for (final d in AppDestination.values) {
      await tester.tap(
        find
            .descendant(
              of: find.byType(NavigationBar),
              matching: find.byIcon(
                d == AppDestination.home ? d.selectedIcon : d.icon,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: d.label);
    }
  });

  group('state views', () {
    Future<void> pumpView(WidgetTester tester, Widget child) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

    testWidgets('error view shows retry and calls back', (tester) async {
      var retried = 0;
      await pumpView(
        tester,
        ErrorView(
          title: 'Could not read note',
          message: 'I/O error',
          onRetry: () => retried++,
        ),
      );
      expect(find.text('Could not read note'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, 1);
    });

    testWidgets('permission denied view offers re-selection', (tester) async {
      var reselected = false;
      await pumpView(
        tester,
        PermissionDeniedView(onReselect: () => reselected = true),
      );
      expect(find.text('Vault access was lost'), findsOneWidget);
      await tester.tap(find.text('Choose folder again'));
      expect(reselected, isTrue);
    });

    testWidgets('loading and empty views render', (tester) async {
      await pumpView(tester, const LoadingView(label: 'Scanning vault…'));
      expect(find.text('Scanning vault…'), findsOneWidget);
      await pumpView(tester, const EmptyView(title: 'No notes'));
      expect(find.text('No notes'), findsOneWidget);
    });
  });
}
