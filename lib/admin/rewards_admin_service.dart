import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Data model for a reward row coming from a collectionGroup("rewards") query.
class RewardRow {
  final String rewardId;
  final String userId; // parent segment extracted from document reference path
  final int threshold;
  final String label;
  final String
  status; // pending|fulfilled|skipped (fulfilmentStatus if present; else "pending")
  final bool userNotified;
  final bool adminNotified;
  final Timestamp? createdAt;
  final Timestamp? userEmailSentAt;
  final Timestamp? adminEmailSentAt;
  final Timestamp? fulfilledAt;
  final Timestamp? lastUpdatedAt;
  final String? displayName;
  final String? email;
  final int? totalSentCount;
  final DocumentReference<Map<String, dynamic>> docRef;

  RewardRow({
    required this.rewardId,
    required this.userId,
    required this.threshold,
    required this.label,
    required this.status,
    required this.userNotified,
    required this.adminNotified,
    required this.createdAt,
    required this.userEmailSentAt,
    required this.adminEmailSentAt,
    required this.fulfilledAt,
    required this.lastUpdatedAt,
    required this.displayName,
    required this.email,
    required this.totalSentCount,
    required this.docRef,
  });

  static String _extractUserIdFromPath(String fullPath) {
    // Expected path: users/{userId}/rewards/{rewardId}
    final parts = fullPath.split('/');
    final uIdx = parts.indexOf('users');
    if (uIdx >= 0 && uIdx + 1 < parts.length) return parts[uIdx + 1];
    return '';
  }

  factory RewardRow.fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? {};
    return RewardRow(
      rewardId: snap.id,
      userId: _extractUserIdFromPath(snap.reference.path),
      threshold:
          (d['threshold'] ?? 0) is int
              ? d['threshold'] as int
              : int.tryParse('${d['threshold']}') ?? 0,
      label: (d['label'] ?? '') as String,
      status: (d['fulfilmentStatus'] ?? 'pending') as String,
      userNotified: (d['userNotified'] ?? false) as bool,
      adminNotified: (d['adminNotified'] ?? false) as bool,
      createdAt: d['createdAt'] as Timestamp?,
      userEmailSentAt: d['userEmailSentAt'] as Timestamp?,
      adminEmailSentAt: d['adminEmailSentAt'] as Timestamp?,
      fulfilledAt: d['fulfilledAt'] as Timestamp?,
      lastUpdatedAt: d['lastUpdatedAt'] as Timestamp?,
      displayName:
          d['displayName'] as String?, // may be populated later; optional
      email: d['email'] as String?, // may be populated later; optional
      totalSentCount:
          d['totalSentCount'] is int ? d['totalSentCount'] as int : null,
      docRef: snap.reference,
    );
  }
}

class RewardsAdminService {
  RewardsAdminService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    this.region = 'europe-west2',
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west2');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String region;

  /// Stream rewards via collectionGroup; supports basic filtering.
  Stream<List<RewardRow>> streamRewards({
    String statusFilter = 'all', // all|pending|fulfilled|skipped
    int? thresholdEquals,
    String? searchText, // matches userId/email/rewardId (client-side)
    int limit = 200,
  }) {
    Query<Map<String, dynamic>> q = _firestore.collectionGroup('rewards');

    if (statusFilter != 'all') {
      q = q.where('fulfilmentStatus', isEqualTo: statusFilter);
    }
    if (thresholdEquals != null) {
      q = q.where('threshold', isEqualTo: thresholdEquals);
    }

    q = q.orderBy('createdAt', descending: true).limit(limit);

    return q.snapshots().map((snap) {
      final rows = snap.docs.map((d) => RewardRow.fromSnap(d)).toList();
      if (searchText == null || searchText.trim().isEmpty) return rows;
      final needle = searchText.trim().toLowerCase();
      return rows.where((r) {
        final bucket =
            [
              r.userId,
              r.rewardId,
              r.displayName ?? '',
              r.email ?? '',
              r.label,
              '${r.threshold}',
            ].join(' ').toLowerCase();
        return bucket.contains(needle);
      }).toList();
    });
  }

  /// Call Tier-4 callable to update fulfilment & write audit entry.
  Future<void> updateFulfilment({
    required String userId,
    required String rewardId,
    required String status, // pending|fulfilled|skipped
    String? notes,
  }) async {
    final callable = _functions.httpsCallable('updateRewardFulfilment');
    await callable.call(<String, dynamic>{
      'userId': userId,
      'rewardId': rewardId,
      'status': status,
      if (notes != null) 'notes': notes,
    });
  }
}
