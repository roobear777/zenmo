// lib/services/report_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ReportRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a report document and (optionally) email moderators.
  Future<void> submitReport({
    required String reporterId,
    required String targetUserId,
    required String reason,
    String? swatchPath,
    String? details,
    bool emailModerators = true,
  }) async {
    await _firestore.collection('reports').add({
      'reporterId': reporterId,
      'targetUserId': targetUserId,
      'reason': reason,
      if (swatchPath != null) 'swatchPath': swatchPath,
      if (details != null && details.isNotEmpty) 'details': details,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (emailModerators) {
      final body =
          StringBuffer()
            ..writeln('New report')
            ..writeln('Reporter: $reporterId')
            ..writeln('Target:   $targetUserId')
            ..writeln('Reason:   $reason');
      if (swatchPath != null) body.writeln('Swatch:   $swatchPath');
      if (details != null && details.isNotEmpty) {
        body.writeln('\nDetails:\n$details');
      }
      await _sendModeratorEmail(
        subject: 'Zenmo - New Report',
        text: body.toString(),
      );
    }
  }

  /// Add /users/{ownerUid}/blocks/{blockedUid}
  Future<void> setBlock({
    required String ownerUid,
    required String blockedUid,
  }) async {
    await _firestore
        .collection('users')
        .doc(ownerUid)
        .collection('blocks')
        .doc(blockedUid)
        .set({
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Fire the /mail trigger (if you set up the extension / Cloud Function).
  Future<void> _sendModeratorEmail({
    required String subject,
    required String text,
    String to = 'zenmoapp@gmail.com',
    String? replyTo,
  }) async {
    await _firestore.collection('mail').add({
      'to': to,
      if (replyTo != null) 'replyTo': replyTo,
      'message': {'subject': subject, 'text': text},
    });
  }
}
