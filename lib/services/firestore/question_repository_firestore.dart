// lib/services/firestore/question_repository_firestore.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/question.dart';
import '../question_repository.dart';
import '../paged.dart';

class QuestionRepositoryFirestore implements QuestionRepository {
  QuestionRepositoryFirestore({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // ---- Public API (unchanged) ------------------------------------------------

  @override
  Future<List<Question>> getQuestionsForDay(String day) async {
    // Prefer utcDay; fall back to localDay only if utcDay has no results.
    final preferred = await _fetchBothDayKeys(day, limit: 100);
    return preferred.take(50).toList(); // preserve previous effective cap
  }

  @override
  Future<Question?> getQuestionById(String id) async {
    final doc = await _db.collection('questions').doc(id).get();
    if (!doc.exists) return null;
    return _fromDoc(doc);
  }

  @override
  Future<String> createQuestion({
    required String text,
    required String localDay,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 150) {
      throw ArgumentError('Prompt must be 1–150 characters');
    }

    final utcDay = _yyyyMmDdUtc(DateTime.now().toUtc());
    final ref = await _db.collection('questions').add({
      'authorId': uid,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
      'localDay': localDay, // keep writing localDay for backward-compat
      'utcDay': utcDay, // canonical
      'status': 'active',
      'visibility': 'all',
      'answersCount': 0,
    });
    return ref.id;
  }

  @override
  Future<Paged<Question>> getQuestionsForDayPage(
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

  // ---- Internals -------------------------------------------------------------

  /// NOTE: name kept for minimal churn, behaviour updated to "prefer UTC":
  /// 1) Try `utcDay == day` ordered by createdAt desc.
  /// 2) If (and only if) step 1 returns empty, try legacy `localDay == day`.
  /// No merging/deduping is performed anymore.
  Future<List<Question>> _fetchBothDayKeys(
    String day, {
    int? limit,
    DateTime? startAfterCreatedAt,
  }) async {
    Query<Map<String, dynamic>> baseWhere(String field) {
      var q = _db
          .collection('questions')
          .where(field, isEqualTo: day)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true);
      if (startAfterCreatedAt != null) {
        q = q.startAfter([Timestamp.fromDate(startAfterCreatedAt)]);
      }
      if (limit != null) q = q.limit(limit);
      return q;
    }

    // 1) Try UTC first (canonical)
    final qUtc = baseWhere('utcDay');
    final utcSnap = await qUtc.get();
    if (utcSnap.docs.isNotEmpty) {
      return utcSnap.docs.map(_fromDoc).toList();
    }

    // 2) Fallback to localDay only if UTC had no rows
    final qLocal = baseWhere('localDay');
    final localSnap = await qLocal.get();
    return localSnap.docs.map(_fromDoc).toList();
  }

  List<Question> _fromSnap(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map(_fromDoc).toList();

  Question _fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final map = d.data() ?? const <String, dynamic>{};
    final createdAtMs =
        (map['createdAt'] is Timestamp)
            ? (map['createdAt'] as Timestamp).millisecondsSinceEpoch
            : (map['createdAt'] as int? ??
                DateTime.now().millisecondsSinceEpoch);

    // Be tolerant of either day key; keep mapping into model.localDay for now.
    final String localDay =
        (map['localDay'] as String?) ?? (map['utcDay'] as String?) ?? '';

    return Question(
      id: d.id,
      authorId: (map['authorId'] as String?) ?? '',
      text: (map['text'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      localDay: localDay,
      status: (map['status'] as String?) ?? 'active',
      visibility: (map['visibility'] as String?) ?? 'all',
      answersCount: (map['answersCount'] as int?) ?? 0,
    );
  }
}

/// Helper: format "YYYY-MM-DD" from a UTC DateTime.
String _yyyyMmDdUtc(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}
