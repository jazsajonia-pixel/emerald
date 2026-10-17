// On-device smoke test. Runs on an Android emulator in CI (see
// .github/workflows/android.yml, job "emulator-smoke"). It uses the real
// Storage Access Framework channel, so it verifies the Kotlin bridge is wired
// up, but it cannot drive the system folder picker itself.
import 'package:emerald/app/app.dart';
import 'package:emerald/app/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches, restores (no) vault via SAF, navigates', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: EmeraldApp()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Fresh install: the Kotlin channel reports no remembered vault.
    expect(find.text('No vault selected'), findsWidgets);

    for (final d in AppDestination.values) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(d.label),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: d.label);
    }

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Brain'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose vault folder'), findsOneWidget);
  });
}
