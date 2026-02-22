// lib/models/answer.dart
class Answer {
  final String id;
  final String questionId;
  final String responderId;
  final String colorHex; // "#RRGGBB"
  final String title; // ≤25 chars
  final DateTime createdAt;
  final String localDay; // "YYYY-MM-DD"
  final String visibleTo; // 'all'

  Answer({
    required this.id,
    required this.questionId,
    required this.responderId,
    required this.colorHex,
    required this.title,
    required this.createdAt,
    required this.localDay,
    required this.visibleTo,
  }) {
    if (title.length > 25) {
      throw ArgumentError('Answer.title must be ≤ 25 chars');
    }
  }

  factory Answer.fromMap(String id, Map<String, dynamic> map) {
    return Answer(
      id: id,
      questionId: map['questionId'] as String,
      responderId: map['responderId'] as String,
      colorHex: map['colorHex'] as String,
      title: map['title'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      localDay: map['localDay'] as String,
      visibleTo: map['visibleTo'] as String,
    );
  }

  Map<String, dynamic> toMap() => {
    'questionId': questionId,
    'responderId': responderId,
    'colorHex': colorHex,
    'title': title,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'localDay': localDay,
    'visibleTo': visibleTo,
  };
}
