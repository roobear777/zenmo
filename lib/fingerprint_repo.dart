import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Avatar publisher (client-side): writes /users/{uid}/public/avatar
import 'package:color_wallet/services/avatar_helper.dart';

class FingerprintRepo {
  // ---------- plumbing ----------
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static String _uidOrThrow() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    return uid;
  }

  static DocumentReference<Map<String, dynamic>> _draftDoc() {
    final uid = _uidOrThrow();
    return _db
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('fingerprint');
  }

  static CollectionReference<Map<String, dynamic>> _versionsCol() {
    final uid = _uidOrThrow();
    return _db.collection('users').doc(uid).collection('fingerprints');
  }

  // ---------- month helpers: single source of truth ----------
  /// YYYY-MM for *local* calendar month.
  static String currentMonthKeyLocal([DateTime? now]) {
    final d = (now ?? DateTime.now()).toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  /// Canonical doc ref: /fingerprints/{uid}/months/{monthId}
  static DocumentReference<Map<String, dynamic>> monthDocRefFor({
    required FirebaseFirestore db,
    required String uid,
    required String monthId, // YYYY-MM
  }) {
    return db
        .collection('fingerprints')
        .doc(uid)
        .collection('months')
        .doc(monthId);
  }

  /// Convenience: current-month ref (still used by eligibility checks).
  static DocumentReference<Map<String, dynamic>> monthDocRef({
    required FirebaseFirestore db,
    required String uid,
    DateTime? now,
  }) {
    final key = currentMonthKeyLocal(now);
    return monthDocRefFor(db: db, uid: uid, monthId: key);
  }

  // ---------- hex helpers ----------
  /// Convert ARGB int (0xAARRGGBB) to #RRGGBB (alpha dropped).
  static String _toHexRgb(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = (argb) & 0xFF;
    String two(int v) => v.toRadixString(16).padLeft(2, '0');
    return '#${two(r)}${two(g)}${two(b)}'.toUpperCase();
  }

  static List<String> _hexListFromAnswers(List<int> answers) =>
      answers.map(_toHexRgb).toList(growable: false);

  /// Normalise answers stored in a fingerprint doc into a List<int>.
  /// Supports:
  ///   • answers: [int, int, ...]
  ///   • or fields "0","1",...,"24" each holding an int.
  static List<int> _extractAnswersFromDoc(Map<String, dynamic> data) {
    // Preferred: explicit answers list.
    final rawAnswers = data['answers'];
    if (rawAnswers is List) {
      return rawAnswers.whereType<int>().toList(growable: false);
    }

    // Fallback: numeric keys "0","1",...,"N" with int values.
    final numericKeys = <int, int>{}; // index -> value
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is! int) continue;
      if (RegExp(r'^\d+$').hasMatch(key)) {
        final idx = int.parse(key);
        numericKeys[idx] = value;
      }
    }

    if (numericKeys.isEmpty) {
      return const <int>[];
    }

    final sortedIndexes = numericKeys.keys.toList()..sort();
    return [for (final i in sortedIndexes) numericKeys[i]!];
  }

  /// Load from canonical monthly doc, then latest legacy version, else {}.
  static Future<Map<String, dynamic>> _loadCanonicalOrLegacy({
    required FirebaseFirestore db,
    required String uid,
  }) async {
    // 1) Canonical month doc
    try {
      final monthSnap = await monthDocRef(db: db, uid: uid).get();
      final monthData = monthSnap.data();
      if (monthData != null && monthData.isNotEmpty) {
        return monthData;
      }
    } catch (_) {
      // ignore and fall through
    }

    // 2) Latest legacy version under /users/{uid}/fingerprints
    try {
      final qs =
          await db
              .collection('users')
              .doc(uid)
              .collection('fingerprints')
              .orderBy('createdAt', descending: true)
              .limit(1)
              .get();
      if (qs.docs.isNotEmpty) {
        return qs.docs.first.data();
      }
    } catch (_) {
      // ignore and fall through
    }

    return const <String, dynamic>{};
  }

  // ---------- writes ----------
  /// Save/overwrite draft progress. Also writes answersHex for merch.
  /// Guardrail: set createdAt/monthId once and never change them.
  static Future<void> saveDraft({
    required List<int> answers,
    required int total,
  }) async {
    final draftRef = _draftDoc();
    final snap = await draftRef.get();
    final existing = snap.data();

    final bool hasMonthId =
        existing != null &&
        existing['monthId'] is String &&
        (existing['monthId'] as String).length >= 7;

    final bool hasCreatedAt =
        existing != null &&
        (existing['createdAt'] is Timestamp ||
            existing['createdAt'] is DateTime);

    final payload = <String, dynamic>{
      'answers': answers,
      'answersHex': _hexListFromAnswers(answers),
      'total': total,
      'completed': false,
      // Only include createdAt if it's missing; updatedAt always moves.
      if (!hasCreatedAt) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      // Only include monthId if absent, so later merges never overwrite it.
      if (!hasMonthId) 'monthId': currentMonthKeyLocal(),
    };

    await draftRef.set(payload, SetOptions(merge: true));

    // Keep the public avatar roughly in sync with the current draft.
    if (answers.isNotEmpty) {
      final denseHex = _hexListFromAnswers(answers).take(25).toList();
      await upsertPublicAvatar(db: _db, uid: _uidOrThrow(), denseHex: denseHex);
    }
  }

  /// DEPRECATED: Use the monthly writer. Keeps public API stable.
  @Deprecated('Use saveCurrentMonthFromAnswers(...) instead.')
  static Future<void> finish({
    required List<int> answers,
    required int total,
    DateTime? now, // kept for backward compatibility; ignored
  }) async {
    if (answers.length != 25) {
      throw ArgumentError(
        'Fingerprint requires exactly 25 answers, got ${answers.length}.',
      );
    }
    await saveCurrentMonthFromAnswers(
      db: _db,
      uid: _uidOrThrow(),
      answers: answers,
      total: 25,
    );
  }

  // ---------- monthly save to /fingerprints/{uid}/months/{YYYY-MM} ----------
  /// New canonical writer (explicit db + uid). Minimal schema; forward-compatible via merge.
  /// Guardrail: copy monthId from draft if present; otherwise compute once locally.
  /// Also mirrors to legacy /users/{uid}/fingerprints for existing history views.
  static Future<void> saveCurrentMonthFromAnswers({
    required FirebaseFirestore db,
    required String uid,
    required List<int> answers,
    int total = 25,
  }) async {
    if (answers.length != total) {
      throw ArgumentError(
        'Fingerprint requires exactly $total answers, got ${answers.length}.',
      );
    }

    // Derive monthId (prefer draft’s write-once monthId; else compute).
    final draftRef = db
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('fingerprint');
    final draftSnap = await draftRef.get();
    final draftData = draftSnap.data() ?? const <String, dynamic>{};
    final String monthId =
        (draftData['monthId'] is String &&
                (draftData['monthId'] as String).length >= 7)
            ? (draftData['monthId'] as String).substring(0, 7)
            : currentMonthKeyLocal();

    // --- Canonical monthly doc (/fingerprints/{uid}/months/{YYYY-MM}) ---
    await monthDocRefFor(db: db, uid: uid, monthId: monthId).set(
      <String, dynamic>{
        'monthId': monthId, // store explicitly for readers that prefer fields
        'completed': true,
        'answers': answers,
        'answersCount': answers.length,
        'total': total,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'version': 1,
      },
      SetOptions(merge: true),
    );

    // --- Legacy mirror (/users/{uid}/fingerprints/{autoId}) to keep history views working ---
    await db.collection('users').doc(uid).collection('fingerprints').add({
      'monthId': monthId,
      'answers': answers,
      'answersHex': _hexListFromAnswers(answers),
      'total': total,
      'createdAt': FieldValue.serverTimestamp(),
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'shuffleSeed': draftData['shuffleSeed'],
      'version': 1,
    });

    // --- Reflect completion back into the draft so Account UI shows "Complete" immediately ---
    final nextSeed =
        (draftData['shuffleSeed'] is int) ? draftData['shuffleSeed'] : 0;

    await draftRef.set({
      'answers': answers,
      'total': total,
      'completed': true,
      'shuffleSeed': nextSeed,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Update the public avatar from the completed fingerprint (flat 25-item grid).
    final denseHex = _hexListFromAnswers(answers).take(25).toList();
    await upsertPublicAvatar(db: db, uid: uid, denseHex: denseHex);
  }

  /// Back-compat overload so older call sites can keep calling without db/uid.
  static Future<void> saveCurrentMonthFromAnswersLegacy({
    required List<int> answers,
    int total = 25,
  }) async {
    await saveCurrentMonthFromAnswers(
      db: _db,
      uid: _uidOrThrow(),
      answers: answers,
      total: total,
    );
  }

  // ---------- eligibility (only the canonical doc can block redo) ----------
  /// Parameterized, fail-open: if read fails, allow redo.
  static Future<bool> canRedoThisMonth({
    required FirebaseFirestore db,
    required String uid,
    int total = 25,
  }) async {
    try {
      final snap = await monthDocRef(db: db, uid: uid).get();
      if (!snap.exists) return true; // No month doc → can redo
      final data = snap.data() ?? const <String, dynamic>{};
      final completed = (data['completed'] == true);
      final answersCount =
          (data['answersCount'] is int) ? data['answersCount'] as int : 0;
      // Block only if clearly completed or full.
      return !(completed || answersCount >= total);
    } catch (_) {
      return true; // fail-open
    }
  }

  /// Wrapper used by widgets that don't pass db/uid. Not signed-in → allow (fail-open).
  static Future<bool> canRedoThisMonthUnsafe() async {
    try {
      final uid = _uidOrThrow();
      return await canRedoThisMonth(db: _db, uid: uid);
    } catch (_) {
      return true; // fail-OPEN same as the parameterized version
    }
  }

  // ---------- streams / reads ----------
  /// Live stream of answers as ARGB ints (draft only; used for in-progress flows).
  static Stream<List<int>> answersStream() {
    return _draftDoc().snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return <int>[];
      return _extractAnswersFromDoc(data);
    });
  }

  /// Full stream for Account screen.
  /// Prefers the draft; if the draft is missing or empty, falls back to:
  ///   1) canonical monthly doc, then
  ///   2) latest legacy /users/{uid}/fingerprints doc.
  static Stream<Map<String, dynamic>> fingerprintStream() {
    final db = _db;
    final uid = _uidOrThrow();

    return _draftDoc().snapshots().asyncMap((snap) async {
      Map<String, dynamic> data = snap.data() ?? const <String, dynamic>{};
      var answers = _extractAnswersFromDoc(data);

      if (answers.isEmpty) {
        try {
          final fb = await _loadCanonicalOrLegacy(db: db, uid: uid);
          if (fb.isNotEmpty) {
            data = fb;
            answers = _extractAnswersFromDoc(data);
          }
        } catch (_) {
          // ignore, keep whatever we had
        }
      }

      final total =
          (data['total'] is int && (data['total'] as int) > 0)
              ? data['total'] as int
              : answers.length;

      return <String, dynamic>{...data, 'answers': answers, 'total': total};
    });
  }

  /// Optional one-shot read with safe backfills for hex and totals.
  /// Prefers draft; if missing/empty, uses month/legacy fallback.
  static Future<Map<String, dynamic>> getAnswersWithHexOnce() async {
    final db = _db;
    final uid = _uidOrThrow();

    Map<String, dynamic> data;
    try {
      final snap = await _draftDoc().get();
      data = snap.data() ?? const <String, dynamic>{};
    } catch (_) {
      data = const <String, dynamic>{};
    }

    if (_extractAnswersFromDoc(data).isEmpty) {
      try {
        final fb = await _loadCanonicalOrLegacy(db: db, uid: uid);
        if (fb.isNotEmpty) {
          data = fb;
        }
      } catch (_) {
        // ignore
      }
    }

    final answers = _extractAnswersFromDoc(data);

    final answersHex =
        (data['answersHex'] is List)
            ? (data['answersHex'] as List).whereType<String>().toList()
            : _hexListFromAnswers(answers); // backfill if missing

    final total =
        (data['total'] is int && (data['total'] as int) > 0)
            ? data['total'] as int
            : answers.length;

    return {
      'answers': answers,
      'answersHex': answersHex,
      'total': total,
      'completed': data['completed'] == true,
      'shuffleSeed': (data['shuffleSeed'] is int) ? data['shuffleSeed'] : null,
      'completedAt': data['completedAt'],
      'updatedAt': data['updatedAt'],
      'createdAt': data['createdAt'],
      'monthId': data['monthId'],
    };
  }

  /// Stream newest-first history of versions (helpful for a History screen).
  static Stream<List<Map<String, dynamic>>> historyStream({int limit = 24}) {
    return _versionsCol()
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (qs) =>
              qs.docs.map((d) {
                final data = d.data();
                return {
                  'id': d.id,
                  'monthId': data['monthId'],
                  'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
                  'total': data['total'],
                  'answers':
                      (data['answers'] is List)
                          ? (data['answers'] as List).whereType<int>().toList()
                          : <int>[],
                  'answersHex':
                      (data['answersHex'] is List)
                          ? (data['answersHex'] as List)
                              .whereType<String>()
                              .toList()
                          : null,
                  'shuffleSeed':
                      (data['shuffleSeed'] is int) ? data['shuffleSeed'] : null,
                };
              }).toList(),
        );
  }

  /// Fetch the most recent version (if any).
  static Future<Map<String, dynamic>?> latestVersionOnce() async {
    final qs =
        await _versionsCol()
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();
    if (qs.docs.isEmpty) return null;
    final d = qs.docs.first;
    final data = d.data();
    return {
      'id': d.id,
      'monthId': data['monthId'],
      'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
      'total': data['total'],
      'answers':
          (data['answers'] is List)
              ? (data['answers'] as List).whereType<int>().toList()
              : <int>[],
      'answersHex':
          (data['answersHex'] is List)
              ? (data['answersHex'] as List).whereType<String>().toList()
              : null,
      'shuffleSeed': (data['shuffleSeed'] is int) ? data['shuffleSeed'] : null,
    };
  }
}
