import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zenmo/state/fingerprint_state.dart';
import 'package:zenmo/models/color_swatch.dart' as models;
import 'package:flutter/material.dart';

void main() {
  group('FingerprintState Persistence', () {
    setUp(() async {
      // Clear shared preferences before each test
      SharedPreferences.setMockInitialValues({});
    });

    test('save() and load() preserve state across sessions', () async {
      // Create a state with some data
      final state1 = FingerprintState();
      
      // Add a color to question 0
      final swatch = models.ColorSwatch(
        title: 'Test Color',
        color: Colors.blue,
        note: 'Test note',
        createdAt: DateTime(2024, 1, 1),
        creator: 'Test User',
      );
      
      state1.addColorToQuestion(0, swatch);
      state1.currentQuestionIndex = 1;
      
      // Wait for save to complete
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Create a new state and load
      final state2 = FingerprintState();
      await state2.load();
      
      // Verify the data was preserved
      expect(state2.getAnswer(0).swatches.length, 1);
      expect(state2.getAnswer(0).swatches[0].title, 'Test Color');
      expect(state2.getAnswer(0).swatches[0].note, 'Test note');
      expect(state2.currentQuestionIndex, 1);
    });

    test('addColorToQuestion automatically saves state', () async {
      final state = FingerprintState();
      
      final swatch = models.ColorSwatch(
        title: 'Auto Save Test',
        color: Colors.red,
        note: null,
        createdAt: DateTime.now(),
        creator: 'User',
      );
      
      state.addColorToQuestion(0, swatch);
      
      // Wait for save to complete
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Load in a new state
      final newState = FingerprintState();
      await newState.load();
      
      expect(newState.getAnswer(0).swatches.length, 1);
      expect(newState.getAnswer(0).swatches[0].title, 'Auto Save Test');
    });

    test('removeColorFromQuestion automatically saves state', () async {
      final state = FingerprintState();
      
      // Add two colors
      final swatch1 = models.ColorSwatch(
        title: 'Color 1',
        color: Colors.blue,
        note: null,
        createdAt: DateTime.now(),
        creator: 'User',
      );
      
      final swatch2 = models.ColorSwatch(
        title: 'Color 2',
        color: Colors.green,
        note: null,
        createdAt: DateTime.now(),
        creator: 'User',
      );
      
      state.addColorToQuestion(0, swatch1);
      state.addColorToQuestion(0, swatch2);
      
      // Wait for saves to complete
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Remove the first color
      state.removeColorFromQuestion(0, 0);
      
      // Wait for save to complete
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Load in a new state
      final newState = FingerprintState();
      await newState.load();
      
      expect(newState.getAnswer(0).swatches.length, 1);
      expect(newState.getAnswer(0).swatches[0].title, 'Color 2');
    });

    test('load() handles missing data gracefully', () async {
      final state = FingerprintState();
      
      // Load without any saved data
      await state.load();
      
      // Should have empty answers
      expect(state.getAnswer(0).swatches.length, 0);
      expect(state.currentQuestionIndex, 0);
    });

    test('save() handles errors gracefully', () async {
      final state = FingerprintState();
      
      // This should not throw even if save fails
      await state.save();
      
      // State should still be in memory
      expect(state.getAnswer(0).swatches.length, 0);
    });
  });
}
