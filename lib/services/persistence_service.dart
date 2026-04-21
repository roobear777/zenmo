import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/fingerprint_answer.dart';
import '../config/fingerprint_questions.dart';

/// Service for persisting fingerprint state to local storage
/// Isolates platform-specific persistence logic from state management
class PersistenceService {
  static const String _stateKey = 'fingerprint_state';

  /// Saves fingerprint state to persistent storage
  Future<void> saveState({
    required List<FingerprintAnswer> answers,
    required int currentQuestionIndex,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateMap = {
        'answers': answers.map((a) => a.toMap()).toList(),
        'currentQuestionIndex': currentQuestionIndex,
      };
      final stateJson = jsonEncode(stateMap);
      await prefs.setString(_stateKey, stateJson);
    } catch (e) {
      // Log error but don't throw - state is still in memory
      debugPrint('Error saving state: $e');
    }
  }

  /// Loads fingerprint state from persistent storage
  /// Returns null if no saved state exists
  Future<({List<FingerprintAnswer> answers, int currentQuestionIndex})?> loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = prefs.getString(_stateKey);

      if (stateJson == null) {
        return null;
      }

      final stateMap = jsonDecode(stateJson) as Map<String, dynamic>;
      final answersRaw = (stateMap['answers'] is List) ? (stateMap['answers'] as List) : [];
      final answers = <FingerprintAnswer>[];

      for (final v in answersRaw) {
        if (v is Map<String, dynamic>) {
          answers.add(FingerprintAnswer.fromMap(v));
        }
      }

      // Ensure we have exactly kFingerprintTotalQuestions + 1 answers (5 questions + 1 custom slot)
      while (answers.length < kFingerprintTotalQuestions + 1) {
        answers.add(FingerprintAnswer.empty());
      }

      return (
        answers: answers.take(kFingerprintTotalQuestions + 1).toList(),
        currentQuestionIndex: stateMap['currentQuestionIndex'] as int? ?? 0,
      );
    } catch (e) {
      // Return null so caller starts with fresh state
      return null;
    }
  }

  /// Clears all saved state
  Future<void> clearState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_stateKey);
    } catch (e) {
      debugPrint('Error clearing state: $e');
    }
  }
}
