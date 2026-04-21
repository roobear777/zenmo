import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/shared_prompts_service.dart';

/// Holds the live list of shared prompts from Firestore.
class SharedPromptsState extends ChangeNotifier {
  final SharedPromptsService _service;
  List<String> _prompts = [];
  StreamSubscription<List<String>>? _sub;

  SharedPromptsState(this._service) {
    _sub = _service.stream().listen((prompts) {
      _prompts = prompts;
      notifyListeners();
    });
  }

  List<String> get prompts => _prompts;

  Future<void> addPrompt(String prompt) => _service.addPrompt(prompt);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
