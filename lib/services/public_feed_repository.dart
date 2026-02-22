import 'package:cloud_firestore/cloud_firestore.dart';

/// Value object for a single public-feed swatch row.
class PublicFeedItem {
  final String id; // "<YYYY-MM-DD>__<swatchId>"
  final String day; // "YYYY-MM-DD" (from 'utcDay' preferred, else 'day')
  final String colorHex; // "#RRGGBB"
  final String title; // may be empty
  final String creatorName; // display name
  final DateTime? sentAt; // server time
  /// If present, the originating Answer/Swatch id. Enables "Keep".
  final String? rootId;

  PublicFeedItem({
    required this.id,
    required this.day,
    required this.colorHex,
    required this.title,
    required this.creatorName,
    required this.sentAt,
    this.rootId,
  });

  factory PublicFeedItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    final String dayVal =
        (m['utcDay'] as String?)?.trim() ?? (m['day'] as String?)?.trim() ?? '';
    return PublicFeedItem(
      id: d.id,
      day: dayVal,
      colorHex: (m['colorHex'] as String?)?.trim() ?? '#000000',
      title: (m['title'] as String?)?.trim() ?? '',
      creatorName: (m['creatorName'] as String?)?.trim() ?? '',
      sentAt: (m['sentAt'] as Timestamp?)?.toDate(),
      rootId: (m['rootId'] as String?)?.trim(),
    );
  }
}

abstract class PublicFeedRepository {
  /// `day` is the canonical "YYYY-MM-DD" key the UI is asking for.
  /// In practice this is the same string we use for `utcDay` on write.
  Future<List<PublicFeedItem>> getForDay(String day, {int? limit});

  /// Resolve a feed row by the originating Answer/Swatch id it mirrors.
  /// Returns the most recent match if multiple exist.
  Future<PublicFeedItem?> getByRootId(String rootId);

  /// Not used by Daily screens (they only READ), but kept for parity/tests.
  Future<void> mirrorSwatch({
    required String day, // "YYYY-MM-DD" (local passed by caller)
    required String swatchId, // new swatch id
    required String colorHex, // "#RRGGBB"
    required String title,
    required String creatorName,
    String? rootId, // pass original id to enable Keep on feed
  });
}

class PublicFeedRepositoryFirestore implements PublicFeedRepository {
  final FirebaseFirestore firestore;
  PublicFeedRepositoryFirestore({required this.firestore});

  CollectionReference<Map<String, dynamic>> get _col =>
      firestore.collection('public_feed');

  @override
  Future<List<PublicFeedItem>> getForDay(String day, {int? limit}) async {
    // Strict behaviour, mirroring Questions/Answers:
    // 1) Try utcDay == day ordered by sentAt desc.
    // 2) If (and only if) step 1 returns empty, try legacy day == day.
    Query<Map<String, dynamic>> baseWhere(String field) {
      var q = _col
          .where(field, isEqualTo: day)
          .orderBy('sentAt', descending: true);
      if (limit != null) {
        q = q.limit(limit);
      }
      return q;
    }

    // 1) Canonical UTC anchor
    final utcSnap = await baseWhere('utcDay').get();
    if (utcSnap.docs.isNotEmpty) {
      return utcSnap.docs.map(PublicFeedItem.fromDoc).toList();
    }

    // 2) Legacy local-day field (for old rows)
    final localSnap = await baseWhere('day').get();
    return localSnap.docs.map(PublicFeedItem.fromDoc).toList();
  }

  @override
  Future<PublicFeedItem?> getByRootId(String rootId) async {
    if (rootId.isEmpty) return null;

    final q = _col
        .where('type', isEqualTo: 'swatch')
        .where('rootId', isEqualTo: rootId)
        .orderBy('sentAt', descending: true)
        .limit(1);

    final snap = await q.get();
    if (snap.docs.isEmpty) return null;
    return PublicFeedItem.fromDoc(snap.docs.first);
  }

  @override
  Future<void> mirrorSwatch({
    required String day, // local YYYY-MM-DD (as passed in)
    required String swatchId,
    required String colorHex,
    required String title,
    required String creatorName,
    String? rootId,
  }) async {
    // Deterministic id retains legacy form "<day>__<swatchId>"
    final docId = '${day}__$swatchId';

    final String safeTitle =
        title.length > 120 ? title.substring(0, 120) : title;
    final String safeCreator =
        creatorName.length > 80 ? creatorName.substring(0, 80) : creatorName;
    final RegExp hex6 = RegExp(r'^#[0-9A-Fa-f]{6}$');
    final String safeHex = hex6.hasMatch(colorHex) ? colorHex : '#000000';

    final String utcDay = _yyyyMmDdUtc(DateTime.now().toUtc());

    final data = <String, dynamic>{
      'type': 'swatch',
      'day': day, // keep legacy/local for compatibility
      'utcDay': utcDay, // canonical key for cross-timezone reads
      'sentAt': FieldValue.serverTimestamp(),
      'colorHex': safeHex,
      'creatorName': safeCreator,
      if (safeTitle.isNotEmpty) 'title': safeTitle,
      if (rootId != null && rootId.isNotEmpty) 'rootId': rootId,
    };

    await _col.doc(docId).set(data, SetOptions(merge: true));
  }
}

/// Format "YYYY-MM-DD" from a UTC DateTime.
String _yyyyMmDdUtc(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}
