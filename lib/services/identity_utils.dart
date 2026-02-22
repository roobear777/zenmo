import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class IdentityUtils {
  IdentityUtils._();

  static final _db = FirebaseFirestore.instance;
  static List<String>? _cachedKeys;
  static DateTime? _cachedAt;

  /// Returns [currentUid] plus any linkedUids on /users/{currentUid}.
  /// Caches for 60s to limit reads. Falls back to [] if no user.
  static Future<List<String>> myLinkedUids() async {
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) return const []; // signed-out or not ready

    // quick cache (60s)
    if (_cachedKeys != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < const Duration(seconds: 60)) {
      return _cachedKeys!;
    }

    try {
      final snap = await _db.collection('users').doc(current.uid).get();
      final data = snap.data() ?? const {};
      final listed = (data['linkedUids'] as List?)?.cast<String>() ?? const [];

      // Always include current uid; Firestore whereIn cap = 10
      final keys =
          <String>{
            current.uid,
            ...listed.where((e) => e.trim().isNotEmpty),
          }.take(10).toList();

      _cachedKeys = keys;
      _cachedAt = DateTime.now();
      return keys;
    } catch (_) {
      // On any error, at least return current uid.
      final keys = <String>{current.uid}.toList();
      _cachedKeys = keys;
      _cachedAt = DateTime.now();
      return keys;
    }
  }

  // ---------------------------
  // Query builders (linked aware)
  // ---------------------------

  /// Inbox (received items)
  /// - Filters status == 'sent'
  /// - recipientId ∈ [my uid + linked]
  /// - Ordered by sentAt DESC
  static Future<Query<Map<String, dynamic>>> buildInboxQuery() async {
    final keys = await myLinkedUids();
    // If no user, return a query that will yield nothing safely.
    Query<Map<String, dynamic>> q = _db
        .collectionGroup('userSwatches')
        .where('status', isEqualTo: 'sent');

    if (keys.isEmpty) {
      // harmless: impossible filter
      q = q.where('recipientId', isEqualTo: '__none__');
    } else if (keys.length == 1) {
      q = q.where('recipientId', isEqualTo: keys.first);
    } else {
      q = q.where('recipientId', whereIn: keys);
    }

    return q.orderBy('sentAt', descending: true);
  }

  /// Sent (outbox)
  /// - Filters status == 'sent'
  /// - senderId ∈ [my uid + linked]
  /// - Ordered by sentAt DESC
  static Future<Query<Map<String, dynamic>>> buildSentQuery() async {
    final keys = await myLinkedUids();

    Query<Map<String, dynamic>> q = _db
        .collectionGroup('userSwatches')
        .where('status', isEqualTo: 'sent');

    if (keys.isEmpty) {
      q = q.where('senderId', isEqualTo: '__none__');
    } else if (keys.length == 1) {
      q = q.where('senderId', isEqualTo: keys.first);
    } else {
      q = q.where('senderId', whereIn: keys);
    }

    return q.orderBy('sentAt', descending: true);
  }

  /// Drafts (my drafts across linked accounts)
  /// - Filters status == 'draft'
  /// - senderId ∈ [my uid + linked]
  /// - Ordered by createdAt DESC
  static Future<Query<Map<String, dynamic>>> buildDraftsQuery() async {
    final keys = await myLinkedUids();

    Query<Map<String, dynamic>> q = _db
        .collectionGroup('userSwatches')
        .where('status', isEqualTo: 'draft');

    if (keys.isEmpty) {
      q = q.where('senderId', isEqualTo: '__none__');
    } else if (keys.length == 1) {
      q = q.where('senderId', isEqualTo: keys.first);
    } else {
      q = q.where('senderId', whereIn: keys);
    }

    return q.orderBy('createdAt', descending: true);
  }

  // ---------------------------
  // Counters
  // ---------------------------

  /// Fast unread counter (linked aware). Counts docs where readAt is null.
  static Future<int> countUnread() async {
    final keys = await myLinkedUids();

    Query<Map<String, dynamic>> q = _db
        .collectionGroup('userSwatches')
        .where('status', isEqualTo: 'sent')
        .where('readAt', isNull: true);

    if (keys.isEmpty) {
      q = q.where('recipientId', isEqualTo: '__none__');
    } else if (keys.length == 1) {
      q = q.where('recipientId', isEqualTo: keys.first);
    } else {
      q = q.where('recipientId', whereIn: keys);
    }

    final snap = await q.get();
    return snap.size;
  }

  /// Legacy-safe unread counter (treats missing readAt as unread).
  static Future<int> countUnreadIncludingLegacy() async {
    final keys = await myLinkedUids();

    Query<Map<String, dynamic>> q = _db
        .collectionGroup('userSwatches')
        .where('status', isEqualTo: 'sent');

    if (keys.isEmpty) {
      q = q.where('recipientId', isEqualTo: '__none__');
    } else if (keys.length == 1) {
      q = q.where('recipientId', isEqualTo: keys.first);
    } else {
      q = q.where('recipientId', whereIn: keys);
    }

    final snap = await q.orderBy('sentAt', descending: true).get();
    int count = 0;
    for (final d in snap.docs) {
      final m = d.data();
      if (!m.containsKey('readAt') || m['readAt'] == null) count++;
    }
    return count;
  }

  /// (Optional) Call when user explicitly switches account to refresh cache.
  static void invalidateLinkedCache() {
    _cachedKeys = null;
    _cachedAt = null;
  }
}
