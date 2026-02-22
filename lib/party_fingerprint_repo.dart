// lib/party_fingerprint_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PartyFingerprintRepo {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static String _uidOrThrow() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    return uid;
  }

  /// Party Fingerprint is stored privately here:
  /// /users/{uid}/private/partyFingerprint
  static DocumentReference<Map<String, dynamic>> _doc() {
    final uid = _uidOrThrow();
    return _db
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('partyFingerprint');
  }

  static String _pathString() {
    final uid = _uidOrThrow();
    return 'users/$uid/private/partyFingerprint';
  }

  /// Used by AccountScreen
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watch() {
    return _doc().snapshots();
  }

  /// Handy for loading a parsed list (used by flows / resume)
  static Future<List<Map<String, dynamic>>> getDraftOnce() async {
    final path = _pathString();
    debugPrint('PF READ once <- $path');
    final snap = await _doc().get();
    final data = snap.data();
    if (data == null) return const <Map<String, dynamic>>[];

    final raw = data['answers'];
    if (raw is! List) return const <Map<String, dynamic>>[];

    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  /// IMPORTANT:
  /// Your Firestore rules require timestamps (createdAt/updatedAt/completedAt)
  /// to be literal timestamps. FieldValue.serverTimestamp() will FAIL `is timestamp`.
  /// So we do NOT write those fields from the client.
  static Future<void> _writeExact({required Map<String, dynamic> data}) async {
    final path = _pathString();
    debugPrint('PF WRITE -> $path keys=${data.keys.toList()}');

    final ref = _doc();
    try {
      // Overwrite the doc so old stray fields can't linger and break keys().hasOnly(...)
      await ref.set(data, SetOptions(merge: false));
      debugPrint('PF WRITE ok -> $path');
    } catch (e) {
      debugPrint('PF WRITE error -> $path :: $e');
      rethrow;
    }
  }

  static Future<void> saveDraft({
    required List<Map<String, dynamic>> answers,
    required int total,
  }) async {
    await _writeExact(
      data: <String, dynamic>{
        'answers': answers,
        'total': total,
        'completed': false,
        'version': 2,
      },
    );
  }

  static Future<void> saveCompleted({
    required List<Map<String, dynamic>> answers,
    required int total,
  }) async {
    await _writeExact(
      data: <String, dynamic>{
        'answers': answers,
        'total': total,
        'completed': true,
        'version': 2,
      },
    );
  }
}
