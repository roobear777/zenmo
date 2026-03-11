import 'package:flutter_test/flutter_test.dart';

import 'package:zenmo/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ZenmoApp());

    // Verify the initial logo screen appears with new UI
    expect(find.text('zenmo'), findsOneWidget);
    expect(find.text('Test Questions'), findsOneWidget);
  });
}
