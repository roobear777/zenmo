import 'fingerprint_state.dart';
import '../config/fingerprint_questions.dart';

/// Tracks question progress and enforces sequential access
class QuestionProgressTracker {
  final FingerprintState fingerprintState;

  QuestionProgressTracker(this.fingerprintState);

  /// Checks if a question can be accessed based on sequential access rules
  /// Question 0 is always accessible
  /// Question N can only be accessed if question N-1 is complete
  bool canAccessQuestion(int index) {
    if (index < 0 || index >= kFingerprintTotalQuestions) {
      return false;
    }

    // First question is always accessible
    if (index == 0) {
      return true;
    }

    // Other questions require the previous question to be complete
    return fingerprintState.isQuestionComplete(index - 1);
  }

  /// Gets the next available question that can be accessed
  /// Returns kFingerprintTotalQuestions if all questions are complete
  int getNextAvailableQuestion() {
    for (int i = 0; i < kFingerprintTotalQuestions; i++) {
      if (!fingerprintState.isQuestionComplete(i)) {
        return i;
      }
    }
    return kFingerprintTotalQuestions; // All complete
  }
}
