import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../config/fingerprint_questions.dart';
import '../state/fingerprint_state.dart';

/// Handles reading and writing fingerprint submissions to Firestore.
class FirestoreFingerprintService {
  static const _kCollection = 'events/zenmo_party/fingerprints';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(_kCollection);

  /// Builds the submission map from the current [FingerprintState].
  /// Public so it can be tested without hitting Firestore.
  Map<String, dynamic> buildSubmission(FingerprintState state) {
    final answers = List.generate(kFingerprintTotalQuestions, (i) {
      final answer = state.getAnswer(i);
      return {
        'questionIndex': i,
        'questionText': kFingerprintQuestions[i],
        'colorInts': answer.colors,
        'hexValues': answer.hexes,
        'titles': answer.swatches.map((s) => s.title).toList(),
        'notes': answer.swatches.map((s) => s.note).toList(),
        'swatchTimestamps':
            answer.swatches.map((s) => s.createdAt.toIso8601String()).toList(),
      };
    });

    return {
      'submittedAt': DateTime.now().toUtc().toIso8601String(),
      'answers': answers,
    };
  }

  /// Appends a new submission to the user's Firestore document.
  /// Attempts anonymous sign-in if no session exists. Throws if sign-in fails or the write fails.
  Future<void> submitFingerprint(FingerprintState state) async {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('User is not signed in');

    final submission = buildSubmission(state);
    final docRef = _col.doc(uid);

    await docRef.set(
      {
        'uid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'submissions': FieldValue.arrayUnion([submission]),
      },
      SetOptions(merge: true),
    );

    debugPrint('FirestoreFingerprintService: submission written for $uid');
  }

  /// Streams all fingerprint documents ordered by updatedAt descending.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamAllSubmissions() {
    return _col.orderBy('updatedAt', descending: true).snapshots();
  }
}
