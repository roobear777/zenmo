import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Centralized data access for swatches.
/// Path model: /swatches/{senderId}/userSwatches/{swatchId}
class SwatchRepository {
  SwatchRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  // ------------- Collections / helpers -----------------

  CollectionReference<Map<String, dynamic>> _userSwatchesCol(String senderId) =>
      _firestore
          .collection('swatches')
          .doc(senderId)
          .collection('userSwatches');

  Query<Map<String, dynamic>> get _userSwatchesCG =>
      _firestore.collectionGroup('userSwatches');

  CollectionReference<Map<String, dynamic>> get _publicFeed =>
      _firestore.collection('public_feed');

  String? get _me => _auth.currentUser?.uid;

  static String _yyyyMmDd(DateTime dtUtc) {
    final y = dtUtc.year.toString().padLeft(4, '0');
    final m = dtUtc.month.toString().padLeft(2, '0');
    final d = dtUtc.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _toHex6FromColorInt(int colorValue) {
    // incoming is ARGB; convert to #RRGGBB (force opaque)
    final rgb = colorValue & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  // Extract {senderId} from /swatches/{senderId}/userSwatches/{swatchId}
  String? _senderIdFromSnapshot(DocumentSnapshot<Map<String, dynamic>> d) {
    try {
      return d.reference.parent.parent?.id;
    } catch (_) {
      return null;
    }
  }

  // ------------- CREATE / SEND -----------------

  Future<DocumentReference<Map<String, dynamic>>> saveSwatch({
    Map<String, dynamic>? swatchData,
    String? status,
    String? recipientId,
    String? rootId,
    String? parentId,

    // legacy
    String? colorHex,
    String? title,
    String? creatorName,
    String? message,
  }) async {
    final uid = _me;
    if (uid == null) {
      throw StateError('Not authenticated');
    }

    final isNewStyle = swatchData != null;
    final serverNow = FieldValue.serverTimestamp();

    late final String effectiveStatus;
    late final String? effectiveRecipient;
    late final String effectiveTitle;
    late final String effectiveCreatorName;
    late final String effectiveColorHex;
    String? effectiveMessage;

    if (isNewStyle) {
      effectiveStatus = (status ?? 'draft').trim();
      effectiveRecipient =
          recipientId?.trim().isNotEmpty == true ? recipientId!.trim() : null;

      final int colorInt = (swatchData['color'] as int?) ?? 0xFF000000;
      effectiveColorHex = _toHex6FromColorInt(colorInt);

      effectiveTitle = (swatchData['title'] as String? ?? '').trim();

      // Source of truth for display name on the doc:
      // mirror creatorName = senderName for compatibility.
      final fromSender = (swatchData['senderName'] as String? ?? '').trim();
      effectiveCreatorName = fromSender;

      final rawMsg = (swatchData['message'] as String? ?? '').trim();
      effectiveMessage = rawMsg.isEmpty ? null : rawMsg;
    } else {
      effectiveStatus =
          (status ?? (recipientId == null ? 'draft' : 'sent')).trim();
      effectiveRecipient =
          recipientId?.trim().isNotEmpty == true ? recipientId!.trim() : null;
      effectiveTitle = (title ?? '').trim();
      effectiveCreatorName = (creatorName ?? '').trim();
      effectiveColorHex = (colorHex ?? '#000000').trim();
      final rawMsg = (message ?? '').trim();
      effectiveMessage = rawMsg.isEmpty ? null : rawMsg;
    }

    final isSent = effectiveStatus == 'sent' && (effectiveRecipient != null);

    final ref = _userSwatchesCol(uid).doc();
    final newId = ref.id;

    // Compose create payload with server timestamps, mirrored names, and lineage.
    final data = <String, dynamic>{
      'id': newId,
      'senderId': uid,
      'status': isSent ? 'sent' : 'draft',
      'colorHex': effectiveColorHex,
      'senderName': effectiveCreatorName,
      'creatorName': effectiveCreatorName, // mirror for compatibility
      'title': effectiveTitle,
      'createdAt': serverNow,
      if (effectiveRecipient != null) 'recipientId': effectiveRecipient,
      if (isSent) 'sentAt': serverNow, // required for new sent
      'rootId': (rootId ?? newId), // ensure presence
      if (parentId != null) 'parentId': parentId,
      if (effectiveMessage != null) 'message': effectiveMessage,
    };

    await ref.set(data, SetOptions(merge: true));

    // Mirror to public_feed only for sent swatches.
    if (isSent) {
      final yyyyMmDd = _yyyyMmDd(DateTime.now().toLocal());
      try {
        await _mirrorToPublicFeed(
          day: yyyyMmDd,
          swatchId: newId,
          colorHex: effectiveColorHex,
          title: effectiveTitle,
          creatorName: effectiveCreatorName,
          rootId: (rootId ?? newId),
        );
      } catch (e) {
        debugPrint('public_feed mirror failed: $e');
        // Optionally report error
      }
    }

    return ref;
  }

  Future<DocumentReference<Map<String, dynamic>>> resendFromParentPath({
    required String parentPath,
    required String toUid,
    required String toName,
    String? messageOverride,
  }) async {
    final me = _me;
    if (me == null) throw StateError('Not authenticated');

    final segs = parentPath.split('/');
    if (segs.length != 4 ||
        segs.first != 'swatches' ||
        segs[2] != 'userSwatches') {
      throw ArgumentError('Invalid parentPath: $parentPath');
    }
    final parentSenderId = segs[1];
    final parentSwatchId = segs[3];

    final parentSnap =
        await _userSwatchesCol(parentSenderId).doc(parentSwatchId).get();
    if (!parentSnap.exists) {
      throw StateError('Parent swatch not found');
    }
    final p = parentSnap.data()!;

    final String hex = (p['colorHex'] as String?) ?? '#000000';
    final String title = (p['title'] as String?) ?? '';
    final String creator =
        (p['creatorName'] as String?) ??
        (p['senderName'] as String?) ??
        'Anonymous';

    // Keep the chain intact:
    // prefer parent's rootId; else fall back to parent id; else new id (handled in saveSwatch).
    final String? parentRoot = (p['rootId'] as String?);

    final ref = await saveSwatch(
      colorHex: hex,
      title: title,
      creatorName: creator, // saveSwatch mirrors to senderName
      status: 'sent',
      recipientId: toUid,
      rootId: parentRoot ?? parentSwatchId, // ensure lineage continuity
      parentId: parentSwatchId,
      message: messageOverride,
    );

    await writeLineageEvent(
      rootId: parentRoot ?? parentSwatchId,
      parentId: parentSwatchId,
      newId: ref.id,
      fromUid: me,
      fromName: creator,
      toUid: toUid,
      toName: toName,
      rootCreatorId:
          (p['rootCreatorId'] as String?) ?? (p['senderId'] as String?),
      rootCreatorName:
          (p['rootCreatorName'] as String?) ?? (p['senderName'] as String?),
    );

    return ref;
  }

  Future<void> resendFromParentParts({
    required String parentSenderId,
    required String swatchId,
    required String newRecipientId,
    required String creatorName,
    String? rootIdOverride,
  }) async {
    final parentPath = 'swatches/$parentSenderId/userSwatches/$swatchId';
    await resendFromParentPath(
      parentPath: parentPath,
      toUid: newRecipientId,
      toName: creatorName,
      // lineage is taken from parent inside resendFromParentPath
    );
  }

  // ------------- Public Feed mirror -----------------

  Future<void> _mirrorToPublicFeed({
    required String day, // "YYYY-MM-DD"
    required String swatchId,
    required String colorHex, // "#RRGGBB"
    required String title,
    required String creatorName,
    String? rootId,
  }) async {
    final docId = '${day}__$swatchId';

    final String safeTitle =
        title.length > 120 ? title.substring(0, 120) : title;
    final String safeCreator =
        creatorName.length > 80 ? creatorName.substring(0, 80) : creatorName;

    final RegExp hex6 = RegExp(r'^#[0-9A-Fa-f]{6}$');
    final String safeHex = hex6.hasMatch(colorHex) ? colorHex : '#000000';

    final data = <String, dynamic>{
      'type': 'swatch',
      'day': day, // local mirror (legacy)
      'utcDay': _yyyyMmDd(DateTime.now().toUtc()), // ← add this line
      'sentAt': FieldValue.serverTimestamp(),
      'colorHex': safeHex,
      'creatorName': safeCreator,
      if (safeTitle.isNotEmpty) 'title': safeTitle,
      if (rootId != null) 'rootId': rootId,
    };

    await _publicFeed.doc(docId).set(data, SetOptions(merge: true));
  }

  // ------------- Reads (lists) -----------------

  Future<List<Map<String, dynamic>>> loadReceivedSwatches({
    int limit = 100,
  }) async {
    final uid = _me;
    if (uid == null) return [];
    final qs =
        await _userSwatchesCG
            .where('recipientId', isEqualTo: uid)
            .where('status', isEqualTo: 'sent')
            .orderBy('sentAt', descending: true)
            .limit(limit)
            .get();

    return qs.docs
        .map((d) {
          final m = d.data()..['id'] = d.id;

          // Inject senderId if it’s missing (older docs)
          final sidInDoc = m['senderId'];
          if (sidInDoc == null || (sidInDoc is String && sidInDoc.isEmpty)) {
            final sidFromPath = _senderIdFromSnapshot(d);
            if (sidFromPath != null) {
              m['senderId'] = sidFromPath;
            }
          }

          return m;
        })
        .where((m) => m['hiddenForRecipient'] != true)
        .toList();
  }

  Future<List<Map<String, dynamic>>> loadDraftSwatches({
    int limit = 100,
  }) async {
    final uid = _me;
    if (uid == null) return [];
    final qs =
        await _userSwatchesCol(uid)
            .where('status', isEqualTo: 'draft')
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .get();
    return qs.docs.map((d) => d.data()..['id'] = d.id).toList();
  }

  Future<List<Map<String, dynamic>>> loadSentSwatches({int limit = 100}) async {
    final uid = _me;
    if (uid == null) return [];
    final qs =
        await _userSwatchesCol(uid)
            .where('status', isEqualTo: 'sent')
            .orderBy('sentAt', descending: true)
            .limit(limit)
            .get();
    return qs.docs.map((d) => d.data()..['id'] = d.id).toList();
  }

  // ------------- Streams (badge counts) -----------------

  Stream<int> inboxUnreadCountStream() {
    final uid = _me;
    if (uid == null) return Stream.value(0);
    return _userSwatchesCG
        .where('recipientId', isEqualTo: uid)
        .where('status', isEqualTo: 'sent')
        .snapshots()
        .map(
          (qs) =>
              qs.docs.where((d) {
                final m = d.data();
                final hidden = m['hiddenForRecipient'] == true;
                final readAt = m['readAt'];
                return !hidden && (readAt == null);
              }).length,
        );
  }

  Stream<int> heartsUnreadCountStream() {
    final uid = _me;
    if (uid == null) return Stream.value(0);
    return _userSwatchesCG
        .where('senderId', isEqualTo: uid)
        .where('status', isEqualTo: 'sent')
        .where('hearted', isEqualTo: true)
        .snapshots()
        .map(
          (qs) =>
              qs.docs.where((d) {
                final m = d.data();
                return m['heartedSeen'] != true;
              }).length,
        );
  }

  // ------------- Mutations on swatch docs -----------------

  Future<void> deleteSwatch({
    required String swatchId,
    required String userId,
  }) async {
    await _userSwatchesCol(userId).doc(swatchId).delete();
  }

  Future<void> hideForRecipient({
    required String senderId,
    required String swatchId,
    required bool hidden,
  }) async {
    await _userSwatchesCol(
      senderId,
    ).doc(swatchId).update({'hiddenForRecipient': hidden});
  }

  Future<void> markRead({
    required String senderId,
    required String swatchId,
  }) async {
    await _userSwatchesCol(
      senderId,
    ).doc(swatchId).update({'readAt': FieldValue.serverTimestamp()});
  }

  Future<void> markHeartSeen({
    required String senderId,
    required String swatchId,
  }) async {
    await _userSwatchesCol(senderId).doc(swatchId).update({
      'heartedSeen': true,
      'heartedSeenAt': FieldValue.serverTimestamp(),
    });
  }

  /// Batch-clear unseen hearts for the current sender across the entire collection group.
  /// Returns the number of documents updated in this pass (up to [limit]).
  Future<int> clearUnseenHeartsForCurrentSender({int limit = 200}) async {
    final uid = _me;
    if (uid == null) return 0;

    // Fetch candidate docs (hearted == true) then client-filter heartedSeen != true (covers missing).
    final qs =
        await _userSwatchesCG
            .where('senderId', isEqualTo: uid)
            .where('status', isEqualTo: 'sent')
            .where('hearted', isEqualTo: true)
            .orderBy('sentAt', descending: true)
            .limit(limit)
            .get();

    final unseen =
        qs.docs.where((d) {
          final m = d.data();
          return m['heartedSeen'] != true; // includes false or missing
        }).toList();

    if (unseen.isEmpty) return 0;

    final batch = _firestore.batch();
    final serverNow = FieldValue.serverTimestamp();

    for (final d in unseen) {
      batch.update(d.reference, {
        'heartedSeen': true,
        'heartedSeenAt': serverNow,
      });
    }

    await batch.commit();
    return unseen.length;
  }

  Future<void> setKept({
    required String senderId,
    required String swatchId,
    required bool kept,
  }) async {
    // Recipient toggles only: update kept + keptAt (rules allow these).
    final update = <String, dynamic>{
      'kept': kept,
      'keptAt': kept ? FieldValue.serverTimestamp() : null,
    };
    await _userSwatchesCol(senderId).doc(swatchId).update(update);
  }

  Future<void> setHeartedWithIdentity({
    required String senderId,
    required String swatchId,
    required bool hearted,
    String? displayNameOverride,
  }) async {
    final uid = _me;
    if (uid == null) throw StateError('Not authenticated');

    final String? name =
        (displayNameOverride?.trim().isNotEmpty ?? false)
            ? displayNameOverride!.trim()
            : null;

    final update = <String, dynamic>{
      'hearted': hearted,
      'heartedAt': hearted ? FieldValue.serverTimestamp() : null,
      'heartedByUid': hearted ? uid : null,
      'heartedByName': hearted ? (name ?? '') : null,
      'heartedSeen': false, // reset on new heart
    };

    await _userSwatchesCol(senderId).doc(swatchId).update(update);
  }

  // ------------- Lineage API -----------------

  Future<void> writeLineageEvent({
    required String rootId,
    required String parentId,
    required String newId,
    required String fromUid,
    required String fromName,
    required String toUid,
    required String toName,
    String? rootCreatorId,
    String? rootCreatorName,
  }) async {
    final col = _firestore
        .collection('lineage')
        .doc(rootId)
        .collection('events');
    await col.add({
      'rootId': rootId,
      'parentId': parentId,
      'newId': newId,
      'fromUid': fromUid,
      'fromName': fromName,
      'toUid': toUid,
      'toName': toName,
      'sentAt': FieldValue.serverTimestamp(),
      if (rootCreatorId != null) 'rootCreatorId': rootCreatorId,
      if (rootCreatorName != null) 'rootCreatorName': rootCreatorName,
    });
  }

  Future<List<Map<String, dynamic>>> getLineage(String rootId) async {
    final qs =
        await _firestore
            .collection('lineage')
            .doc(rootId)
            .collection('events')
            .orderBy('sentAt')
            .get();
    return qs.docs.map((d) => d.data()..['id'] = d.id).toList();
  }
}
