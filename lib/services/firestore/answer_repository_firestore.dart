import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/answer.dart';
import '../answer_repository.dart';
import '../paged.dart';

class AnswerRepositoryFirestore implements AnswerRepository {
  AnswerRepositoryFirestore({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // ---- Public API (unchanged) ------------------------------------------------

  @override
  Future<List<Answer>> getAnswersForDay(String day) async {
    // Prefer utcDay; fall back to localDay only if utcDay has no results.
    final preferred = await _fetchBothDayKeys(day, limit: 200);
    // Preserve previous behavior of returning up to ~120.
    return preferred.take(120).toList();
  }

  @override
  Future<Paged<Answer>> getAnswersForDayPage(
    String day, {
    int limit = 50,
    DateTime? startAfterCreatedAt,
  }) async {
    // Prefer utcDay; fall back to localDay only if utcDay returns empty.
    final preferred = await _fetchBothDayKeys(
      day,
      limit: limit,
      startAfterCreatedAt: startAfterCreatedAt,
    );

    final items = preferred.take(limit).toList();
    final hasMore = preferred.length > items.length;
    final nextCursor = hasMore ? items.last.createdAt : null;

    return Paged(
      items: items,
      nextCreatedAtCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  @override
  Future<Answer?> getAnswerById(String id) async {
    final doc = await _db.collection('answers').doc(id).get();
    if (!doc.exists) return null;
    return _answerFromDoc(doc);
  }

  // ---- New public helper (per-user guard) -----------------------------------

  /// Returns true iff the current user has already answered this [questionId].
  /// Cheap, unambiguous: direct existence check of `/answers/{questionId}_{uid}`.
  Future<bool> hasUserAnswered(String questionId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');

    final qid = _normalizeKey(questionId);
    final docId = '${qid}_$uid';

    final snap = await _db.collection('answers').doc(docId).get();
    return snap.exists;
  }

  // ---- Internals -------------------------------------------------------------

  /// Prefer UTC day; fall back to legacy localDay only if UTC has no rows.
  Future<List<Answer>> _fetchBothDayKeys(
    String day, {
    int? limit,
    DateTime? startAfterCreatedAt,
  }) async {
    Query<Map<String, dynamic>> baseWhere(String field) {
      var q = _db
          .collection('answers')
          .where(field, isEqualTo: day)
          .orderBy('createdAt', descending: true);
      if (startAfterCreatedAt != null) {
        q = q.startAfter([Timestamp.fromDate(startAfterCreatedAt)]);
      }
      if (limit != null) q = q.limit(limit);
      return q;
    }

    // 1) Try UTC first (canonical)
    final utcSnap = await baseWhere('utcDay').get();
    if (utcSnap.docs.isNotEmpty) {
      return utcSnap.docs.map(_answerFromDoc).toList();
    }

    // 2) Fallback to localDay only if UTC had no rows
    final localSnap = await baseWhere('localDay').get();
    return localSnap.docs.map(_answerFromDoc).toList();
  }

  Answer _answerFromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final map = d.data() ?? const <String, dynamic>{};
    final createdAtMs =
        (map['createdAt'] is Timestamp)
            ? (map['createdAt'] as Timestamp).millisecondsSinceEpoch
            : (map['createdAt'] as int? ??
                DateTime.now().millisecondsSinceEpoch);

    // Be tolerant: if localDay is missing (new data), fall back to utcDay.
    final String localDay =
        (map['localDay'] as String?) ?? (map['utcDay'] as String?) ?? '';

    return Answer(
      id: d.id,
      questionId: (map['questionId'] as String?) ?? '',
      responderId: (map['responderId'] as String?) ?? '',
      colorHex: (map['colorHex'] as String?) ?? '#000000',
      title: (map['title'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      localDay: localDay,
      visibleTo: (map['visibleTo'] as String?) ?? 'all',
    );
  }

  /// Unique per (questionId, userId) using composite ID.
  Future<String> createAnswer({
    required String questionId,
    required String colorHex,
    required String title,
    required String localDay,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');

    final qid = _normalizeKey(questionId);
    final id = '${qid}_$uid';
    final ref = _db.collection('answers').doc(id);

    // Anchor answer's utcDay to the QUESTION's utcDay (or derived from its createdAt).
    final qSnap = await _db.collection('questions').doc(qid).get();
    if (!qSnap.exists) {
      throw StateError('Question not found: $qid');
    }
    final qData = qSnap.data()!;
    final String questionUtcDay =
        (qData['utcDay'] as String?) ??
        _yyyyMmDdUtc(
          ((qData['createdAt'] as Timestamp?) ?? Timestamp.now())
              .toDate()
              .toUtc(),
        );

    // Detect first-time answer to avoid double-incrementing counts.
    final existed = (await ref.get()).exists;

    await ref.set({
      'questionId': qid,
      'responderId': uid,
      'colorHex': colorHex,
      'title': title,
      'createdAt': FieldValue.serverTimestamp(), // actual answer time
      'localDay': localDay, // back-compat
      'utcDay': questionUtcDay, // canonical day anchor
      'visibleTo': 'all',
      'visibility': 'all',
    }, SetOptions(merge: false));

    // Increment question's denormalized counts only on first answer by this user.
    if (!existed) {
      await _db.runTransaction((tx) async {
        final qref = _db.collection('questions').doc(qid);
        final snap = await tx.get(qref);
        if (snap.exists) {
          tx.update(qref, {
            'answers': FieldValue.increment(1),
            'answerCount': FieldValue.increment(1),
          });
        }
      });
    }

    return id;
  }
}

/// Remove BOM/zero-width/invisible chars and trim — for stable doc IDs.
String _normalizeKey(String s) {
  // \uFEFF = BOM, \u200B-\u200D = zero-width space/joiners, \u2060 = word joiner
  const zw = r'[\u200B-\u200D\u2060]';
  return s.replaceAll('\uFEFF', '').replaceAll(RegExp(zw), '').trim();
}

/// Helper: format "YYYY-MM-DD" from a UTC DateTime.
String _yyyyMmDdUtc(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}
