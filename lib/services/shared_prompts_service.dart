import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Reads and writes the shared prompt list stored at a single Firestore document.
/// All users see the same list in real time.
class SharedPromptsService {
  static const _kDoc = 'events/zenmo_party/meta/shared_prompts';

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.doc(_kDoc);

  /// Stream of prompt strings, newest first.
  Stream<List<String>> stream() {
    return _ref.snapshots().map((snap) {
      if (!snap.exists) return [];
      final raw = snap.data()?['prompts'];
      if (raw is! List) return [];
      return List<String>.from(raw.reversed);
    });
  }

  /// Appends a new prompt to the shared list.
  Future<void> addPrompt(String prompt) async {
    try {
      await _ref.set(
        {'prompts': FieldValue.arrayUnion([prompt.trim()])},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('SharedPromptsService: failed to add prompt: $e');
      rethrow;
    }
  }
}
