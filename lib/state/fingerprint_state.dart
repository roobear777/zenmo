import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/fingerprint_answer.dart';
import '../models/color_swatch.dart';
import '../config/fingerprint_questions.dart';

/// Manages the overall fingerprint creation state
class FingerprintState extends ChangeNotifier {
  List<FingerprintAnswer> _answers;
  int _currentQuestionIndex;

  FingerprintState({
    List<FingerprintAnswer>? answers,
    int currentQuestionIndex = 0,
  })  : _answers = answers ??
            List.generate(
              kFingerprintTotalQuestions,
              (_) => FingerprintAnswer.empty(),
            ),
        _currentQuestionIndex = currentQuestionIndex;

  /// Gets the answer for a specific question index
  FingerprintAnswer getAnswer(int index) {
    if (index < 0 || index >= kFingerprintTotalQuestions) {
      return FingerprintAnswer.empty();
    }
    return _answers[index];
  }

  /// Updates the answer for a specific question index
  void updateAnswer(int index, FingerprintAnswer answer) {
    if (index < 0 || index >= kFingerprintTotalQuestions) {
      return;
    }
    _answers[index] = answer;
    notifyListeners();
  }

  /// Checks if a question is complete (has at least one color with a valid title)
  bool isQuestionComplete(int index) {
    if (index < 0 || index >= kFingerprintTotalQuestions) {
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

  /// Gets the current question index
  int get currentQuestionIndex => _currentQuestionIndex;

  /// Sets the current question index
  set currentQuestionIndex(int index) {
    if (index >= 0 && index < kFingerprintTotalQuestions) {
      _currentQuestionIndex = index;
      notifyListeners();
    }
  }

  /// Adds a color to a specific question
  void addColorToQuestion(int questionIndex, ColorSwatch swatch) {
    if (questionIndex < 0 || questionIndex >= kFingerprintTotalQuestions) {
      return;
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
    if (questionIndex < 0 || questionIndex >= kFingerprintTotalQuestions) {
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
      final prefs = await SharedPreferences.getInstance();
      final stateJson = jsonEncode(toMap());
      await prefs.setString('fingerprint_state', stateJson);
    } catch (e) {
      // Log error but don't throw - state is still in memory
      debugPrint('Error saving fingerprint state: $e');
    }
  }

  /// Loads the state from persistent storage
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = prefs.getString('fingerprint_state');
      
      if (stateJson != null) {
        final stateMap = jsonDecode(stateJson) as Map<String, dynamic>;
        final loadedState = FingerprintState.fromMap(stateMap);
        
        _answers = loadedState._answers;
        _currentQuestionIndex = loadedState._currentQuestionIndex;
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
