import 'package:flutter/foundation.dart';
import '../models/fingerprint_answer.dart';
import '../models/color_swatch.dart';
import '../config/fingerprint_questions.dart';
import '../services/persistence_service.dart';

/// Manages the overall fingerprint creation state
class FingerprintState extends ChangeNotifier {
  List<FingerprintAnswer> _answers;
  int _currentQuestionIndex;
  String? _customPrompt;
  final PersistenceService _persistenceService;

  FingerprintState({
    List<FingerprintAnswer>? answers,
    int currentQuestionIndex = 0,
    String? customPrompt,
    PersistenceService? persistenceService,
  })  : _answers = answers ??
            List.generate(
              kFingerprintTotalQuestions + 1, // +1 for custom prompt slot
              (_) => FingerprintAnswer.empty(),
            ),
        _currentQuestionIndex = currentQuestionIndex,
        _customPrompt = customPrompt,
        _persistenceService = persistenceService ?? PersistenceService();

  /// Gets the answer for a specific question index
  FingerprintAnswer getAnswer(int index) {
    if (index < 0) return FingerprintAnswer.empty();
    // Auto-expand for shared prompt indices
    while (index >= _answers.length) {
      _answers.add(FingerprintAnswer.empty());
    }
    return _answers[index];
  }

  /// Updates the answer for a specific question index
  void updateAnswer(int index, FingerprintAnswer answer) {
    if (index < 0) return;
    while (index >= _answers.length) {
      _answers.add(FingerprintAnswer.empty());
    }
    _answers[index] = answer;
    notifyListeners();
  }

  /// Checks if a question is complete (has at least one color with a valid title)
  bool isQuestionComplete(int index) {
    if (index < 0 || index >= _answers.length) {
      return false;
    }
    final answer = _answers[index];
    // A question is complete if it has at least one swatch with a non-empty title
    return answer.swatches.any((swatch) => swatch.title.trim().isNotEmpty);
  }

  /// Checks if all questions are complete
  bool get allQuestionsComplete {
    for (int i = 0; i < kFingerprintTotalQuestions; i++) {
      if (!isQuestionComplete(i)) {
        return false;
      }
    }
    return true;
  }

  /// Checks if at least one question is complete
  bool get anyQuestionComplete {
    for (int i = 0; i < kFingerprintTotalQuestions; i++) {
      if (isQuestionComplete(i)) return true;
    }
    return false;
  }

  /// Gets the current question index
  int get currentQuestionIndex => _currentQuestionIndex;

  /// Sets the current question index
  set currentQuestionIndex(int index) {
    if (index >= 0 && index < kFingerprintTotalQuestions) {
      _currentQuestionIndex = index;
      notifyListeners();
    }
  }

  /// Gets the custom prompt (session-only, index 5)
  String? get customPrompt => _customPrompt;

  /// Sets the custom prompt
  void setCustomPrompt(String prompt) {
    _customPrompt = prompt.trim().isEmpty ? null : prompt.trim();
    notifyListeners();
  }

  /// Resets all answers and custom prompt for a new user session
  void resetAll() {
    _answers = List.generate(
      kFingerprintTotalQuestions + 1,
      (_) => FingerprintAnswer.empty(),
    );
    _currentQuestionIndex = 0;
    _customPrompt = null;
    notifyListeners();
    save();
  }

  /// Adds a color to a specific question
  void addColorToQuestion(int questionIndex, ColorSwatch swatch) {
    if (questionIndex < 0) return;
    while (questionIndex >= _answers.length) {
      _answers.add(FingerprintAnswer.empty());
    }

    final answer = _answers[questionIndex];
    final newSwatches = List<ColorSwatch>.from(answer.swatches);

    // Enforce maximum colors per question
    if (newSwatches.length >= kMaxColorsPerQuestion) {
      return;
    }

    newSwatches.add(swatch);

    // Update colors and hexes lists for backward compatibility
    final newColors = newSwatches.map((s) => s.color.value).toList();
    final newHexes = newSwatches.map((s) => s.hexValue).toList();

    _answers[questionIndex] = answer.copyWith(
      colors: newColors,
      hexes: newHexes,
      swatches: newSwatches,
    );

    notifyListeners();
    save(); // Save state after adding color
  }

  /// Removes a color from a specific question
  void removeColorFromQuestion(int questionIndex, int colorIndex) {
    if (questionIndex < 0 || questionIndex >= _answers.length) {
      return;
    }

    final answer = _answers[questionIndex];
    if (colorIndex < 0 || colorIndex >= answer.swatches.length) {
      return;
    }

    final newSwatches = List<ColorSwatch>.from(answer.swatches);
    newSwatches.removeAt(colorIndex);

    // Update colors and hexes lists for backward compatibility
    final newColors = newSwatches.map((s) => s.color.value).toList();
    final newHexes = newSwatches.map((s) => s.hexValue).toList();

    _answers[questionIndex] = answer.copyWith(
      colors: newColors,
      hexes: newHexes,
      swatches: newSwatches,
    );

    notifyListeners();
    save(); // Save state after removing color
  }

  /// Saves the state to persistent storage
  Future<void> save() async {
    try {
      await _persistenceService.saveState(
        answers: _answers,
        currentQuestionIndex: _currentQuestionIndex,
      );
    } catch (e) {
      // Log error but don't throw - state is still in memory
      debugPrint('Error saving fingerprint state: $e');
    }
  }

  /// Loads the state from persistent storage
  Future<void> load() async {
    try {
      final result = await _persistenceService.loadState();

      if (result != null) {
        _answers = result.answers;
        _currentQuestionIndex = result.currentQuestionIndex;
        notifyListeners();
      }
    } catch (e) {
      // Log error but don't throw - start with empty state
      debugPrint('Error loading fingerprint state: $e');
    }
  }

  /// Converts the state to a Map for persistence
  Map<String, dynamic> toMap() {
    return {
      'answers': _answers.map((a) => a.toMap()).toList(),
      'currentQuestionIndex': _currentQuestionIndex,
    };
  }

  /// Creates a FingerprintState from a Map
  factory FingerprintState.fromMap(Map<String, dynamic> map) {
    final answersRaw =
        (map['answers'] is List) ? (map['answers'] as List) : [];
    final answers = <FingerprintAnswer>[];

    for (final v in answersRaw) {
      if (v is Map<String, dynamic>) {
        answers.add(FingerprintAnswer.fromMap(v));
      }
    }

    // Ensure we have exactly kFingerprintTotalQuestions answers
    while (answers.length < kFingerprintTotalQuestions) {
      answers.add(FingerprintAnswer.empty());
    }

    return FingerprintState(
      answers: answers.take(kFingerprintTotalQuestions).toList(),
      currentQuestionIndex: map['currentQuestionIndex'] as int? ?? 0,
    );
  }
}
