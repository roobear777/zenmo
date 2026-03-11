import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zenmo/screens/palette_detail_screen.dart';
import 'package:zenmo/state/fingerprint_state.dart';
import 'package:zenmo/config/fingerprint_questions.dart';

void main() {
  group('PaletteDetailScreen', () {
    testWidgets('displays question text and UI elements', (tester) async {
      // Create a FingerprintState with empty answers
      final fingerprintState = FingerprintState();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: fingerprintState,
            child: const PaletteDetailScreen(questionIndex: 0),
          ),
        ),
      );

      // Verify question text is displayed - Requirement 4.2
      expect(find.text(kFingerprintQuestions[0]), findsOneWidget);

      // Verify "+ Add a color" button is displayed - Requirement 4.4
      expect(find.text('+ Add a color'), findsOneWidget);

      // Verify back button is displayed - Requirement 4.1
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);

      // Verify home button is displayed - Requirement 4.8
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    });

    testWidgets('shows example palettes when no colors added', (tester) async {
      // Create a FingerprintState with empty answers
      final fingerprintState = FingerprintState();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: fingerprintState,
            child: const PaletteDetailScreen(questionIndex: 0),
          ),
        ),
      );

      // Verify example palettes section is shown - Requirement 16.1
      expect(find.text('Example Palettes'), findsOneWidget);

      // Verify some example palette titles are shown
      expect(find.text('Need more sleep'), findsOneWidget);
      expect(find.text('Passsssion'), findsOneWidget);
    });

    testWidgets('add button is enabled when less than 5 colors', (tester) async {
      final fingerprintState = FingerprintState();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: fingerprintState,
            child: const PaletteDetailScreen(questionIndex: 0),
          ),
        ),
      );

      // Find the "+ Add a color" button
      final addButton = find.widgetWithText(ElevatedButton, '+ Add a color');
      expect(addButton, findsOneWidget);

      // Verify button is enabled - Requirement 4.4
      final button = tester.widget<ElevatedButton>(addButton);
      expect(button.onPressed, isNotNull);
    });
  });
}
