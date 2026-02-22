// lib/models/question.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Question {
  final String id;
  final String authorId;
  final String text; // <= 150 chars
  final DateTime createdAt;
  final String localDay; // "YYYY-MM-DD" (falls back to utcDay if missing)
  final String status; // 'active' | 'expired'
  final String visibility; // 'all' (falls back from visibleTo)
  final int answersCount;

  // Legacy alias to avoid crashes if any code still references it.
  String get uid => authorId;

  Question({
    required this.id,
    required this.authorId,
    required this.text,
    required this.createdAt,
    required this.localDay,
    required this.status,
    required this.visibility,
    required this.answersCount,
  }) {
    if (text.length > 150) {
      throw ArgumentError('Question.text must be <= 150 chars');
    }
  }

  factory Question.fromMap(String id, Map<String, dynamic> map) {
    // createdAt may be Timestamp, int(ms), num(ms), or DateTime; normalize.
    final dynamic created = map['createdAt'];
    final DateTime createdAt = switch (created) {
      Timestamp ts => ts.toDate(),
      int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
      DateTime dt => dt,
      _ => DateTime.now(),
    };

    final String authorId =
        (map['authorId'] as String?) ??
        (map['uid'] as String?) ?? // legacy fallback
        '';

    // Prefer localDay; fall back to utcDay if needed.
    final String localDay =
        (map['localDay'] as String?) ?? (map['utcDay'] as String?) ?? '';

    // Prefer 'visibility'; accept legacy 'visibleTo'.
    final String visibility =
        (map['visibility'] as String?) ??
        (map['visibleTo'] as String?) ??
        'all';

    return Question(
      id: id,
      authorId: authorId,
      text: (map['text'] as String?) ?? '',
      createdAt: createdAt,
      localDay: localDay,
      status: (map['status'] as String?) ?? 'active',
      visibility: visibility,
      answersCount: (map['answersCount'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'authorId': authorId,
    'text': text,
    // FlutterFire will serialize DateTime to Firestore Timestamp automatically.
    'createdAt': createdAt,
    'localDay': localDay,
    'status': status,
    'visibility': visibility,
    'answersCount': answersCount,
  };
}
