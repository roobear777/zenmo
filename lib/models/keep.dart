import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

class Keep {
  final String id;
  final String userId;
  final String answerId;
  final DateTime createdAt;
  final DateTime? readAt;

  // Optional snapshot fields for non-Answer keeps (e.g., public feed swatches)
  final String? origin; // e.g. 'answer' | 'feed'
  final String? colorHex; // "#RRGGBB"
  final String? title;
  final String? creatorName;
  final DateTime? sentAt;

  Keep({
    required this.id,
    required this.userId,
    required this.answerId,
    required this.createdAt,
    this.readAt,
    this.origin,
    this.colorHex,
    this.title,
    this.creatorName,
    this.sentAt,
  });

  factory Keep.fromMap(String id, Map<String, dynamic> map) {
    final created = map['createdAt'];
    final read = map['readAt'];
    final sent = map['sentAt'];

    DateTime createdAt;
    if (created is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(created);
    } else if (created is Timestamp) {
      createdAt = created.toDate();
    } else {
      createdAt = DateTime.now();
    }

    DateTime? readAt;
    if (read is int) {
      readAt = DateTime.fromMillisecondsSinceEpoch(read);
    } else if (read is Timestamp) {
      readAt = read.toDate();
    } else {
      readAt = null;
    }

    DateTime? sentAt;
    if (sent is int) {
      sentAt = DateTime.fromMillisecondsSinceEpoch(sent);
    } else if (sent is Timestamp) {
      sentAt = sent.toDate();
    } else {
      sentAt = null;
    }

    return Keep(
      id: id,
      userId: (map['userId'] as String?) ?? '',
      answerId: (map['answerId'] as String?) ?? '',
      createdAt: createdAt,
      readAt: readAt,
      origin: map['origin'] as String?,
      colorHex: (map['colorHex'] as String?)?.trim(),
      title: (map['title'] as String?)?.trim(),
      creatorName: (map['creatorName'] as String?)?.trim(),
      sentAt: sentAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'answerId': answerId,
    // Use Firestore Timestamps for writes to satisfy rules
    'createdAt': Timestamp.fromDate(createdAt),
    if (readAt != null) 'readAt': Timestamp.fromDate(readAt!),

    // Optional snapshot fields
    if (origin != null) 'origin': origin,
    if (colorHex != null) 'colorHex': colorHex,
    if (title != null && title!.isNotEmpty) 'title': title,
    if (creatorName != null && creatorName!.isNotEmpty)
      'creatorName': creatorName,
    if (sentAt != null) 'sentAt': Timestamp.fromDate(sentAt!),
  };
}
