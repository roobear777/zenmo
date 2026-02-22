// lib/services/moderation_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_identity_service.dart';

class ModerationRepository {
  final _db = FirebaseFirestore.instance;
  final _id = UserIdentityService();

  Future<void> submitReport({
    required String reportedUid,
    required String reason, // e.g. "abuse", "spam", "other"
    String? details, // free text
    String?
    swatchPath, // optional context: 'swatches/{senderId}/userSwatches/{swatchId}'
  }) async {
    final reporterUid = await _id.getCurrentUserId();
    final batch = _db.batch();

    // 1) create the report
    final repRef = _db.collection('reports').doc();
    batch.set(repRef, {
      'reportedUid': reportedUid,
      'reporterUid': reporterUid,
      'reason': reason,
      'details': details ?? '',
      'context': {if (swatchPath != null) 'swatchPath': swatchPath},
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2) send email to zenmoapp@gmail.com (Firebase 'Trigger Email' extension)
    final mailRef = _db.collection('mail').doc();
    final subject = 'New report: $reason';
    final text = [
      'Reporter: $reporterUid',
      'Reported: $reportedUid',
      if (swatchPath != null) 'Swatch: $swatchPath',
      'Reason: $reason',
      if ((details ?? '').isNotEmpty) 'Details: $details',
      'Created: (server time)',
    ].join('\n');

    batch.set(mailRef, {
      'to': 'zenmoapp@gmail.com',
      'message': {'subject': subject, 'text': text},
      // optional: replyTo will be the reporter's verified email if your rules allow it
    });

    await batch.commit();
  }
}
