import 'package:emerald/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Emerald app launches and shows its name', (tester) async {
    await tester.pumpWidget(const EmeraldApp());
    expect(find.text('Emerald'), findsOneWidget);
  });
}
