import 'package:flutter_test/flutter_test.dart';

import 'package:zenmo/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ZenmoApp());

    // Verify the welcome screen appears
    expect(find.text('Welcome to Zenmo'), findsOneWidget);
    expect(find.text('Create Fingerprint'), findsOneWidget);
  });
}
