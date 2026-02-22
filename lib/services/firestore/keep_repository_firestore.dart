import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/keep.dart';
import '../keep_repository.dart';
import '../paged.dart';

class KeepRepositoryFirestore implements KeepRepository {
  // Default constructor (backwards-compatible). Functions kept for API stability.
  KeepRepositoryFirestore({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       // ignore: unused_field
       _functions = functions ?? FirebaseFunctions.instance {
    // ignore: avoid_print
    print('[Repo] KeepRepositoryFirestore (services/firestore) constructed');
  }

  // Convenience constructor for europe-west2 deployments (kept for stability).
  KeepRepositoryFirestore.euWest2({FirebaseFirestore? firestore})
    : this(
        firestore: firestore,
        functions: FirebaseFunctions.instanceFor(region: 'europe-west2'),
      );

  final FirebaseFirestore _db;
  // ignore: unused_field
  final FirebaseFunctions _functions;

  // Debug helpers
  bool _loggedEnv = false;

  void _dbg(String attemptId, String msg) {
    // ignore: avoid_print
    print('[KeepDebug][$attemptId] $msg');
  }

  String _newAttemptId() {
    final now = DateTime.now().toUtc().toIso8601String();
    final r = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '$now-$r';
  }

  void _envStampOnce(String attemptId) {
    if (_loggedEnv) return;
    final s = _db.settings;
    _dbg(
      attemptId,
      'env host=${s.host} ssl=${s.sslEnabled} cacheSizeBytes=${s.cacheSizeBytes}',
    );
    _loggedEnv = true;
  }

  Future<bool> _existsServer(final String path) async {
    final snap = await _db
        .doc(path)
        .get(const GetOptions(source: Source.server));
    return snap.exists;
  }

  Future<bool> _existsCache(String path) async {
    try {
      final snap = await _db
          .doc(path)
          .get(const GetOptions(source: Source.cache));
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  // Auth util
  String _uidOrThrow() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw StateError('Not signed in');
    return uid;
  }

  // Opportunistic snapshot of source (feed/answer) for display without joins
  Future<Map<String, dynamic>?> _tryBuildSnapshot(String id) async {
    // 1) Public feed swatch (preferred for Daily Scroll keeps)
    try {
      final feedDoc = await _db
          .collection('public_feed')
          .doc(id)
          .get(const GetOptions(source: Source.server));
      final m = feedDoc.data();
      if (feedDoc.exists && m != null && (m['type'] == 'swatch')) {
        final String hex = (m['colorHex'] as String? ?? '#000000').trim();
        final String title = (m['title'] as String? ?? '').trim();
        final String creatorName = (m['creatorName'] as String? ?? '').trim();
        final Timestamp? sentTs = m['sentAt'] as Timestamp?;
        return <String, dynamic>{
          'origin': 'feed',
          'colorHex':
              RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex) ? hex : '#000000',
          if (title.isNotEmpty) 'title': title,
          if (creatorName.isNotEmpty) 'creatorName': creatorName,
          if (sentTs != null) 'sentAt': sentTs,
        };
      }
    } catch (_) {
      // ignore snapshot failure
    }

    // 2) Answer document (fallback)
    try {
      final ansDoc = await _db
          .collection('answers')
          .doc(id)
          .get(const GetOptions(source: Source.server));
      final a = ansDoc.data();
      if (ansDoc.exists && a != null) {
        final String? hex = (a['colorHex'] as String?)?.trim();
        final String title = (a['title'] as String? ?? '').trim();
        final Timestamp? created = a['createdAt'] as Timestamp?;
        return <String, dynamic>{
          'origin': 'answer',
          if (hex != null && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex))
            'colorHex': hex,
          if (title.isNotEmpty) 'title': title,
          if (created != null) 'sentAt': created,
        };
      }
    } catch (_) {
      // ignore snapshot failure
    }

    return null;
  }

  // ---------- Public API ----------

  @override
  Future<bool> isKept(String answerId) async {
    final uid = _uidOrThrow();
    final id = '${uid}_$answerId';
    final doc = await _db
        .collection('keeps')
        .doc(id)
        .get(const GetOptions(source: Source.server));
    return doc.exists;
  }

  /// Toggle keep for a swatch.
  ///
  /// - If called with a **plain answerId/rootId**: creates or deletes /keeps/<uid>_<answerId>.
  /// - If called with a **keep document id** ("<uid>_<answerId>"): we derive the answerId
  ///   from the suffix and still toggle create/delete against that canonical id.
  @override
  Future<bool> toggleKeep(String idOrAnswerId) async {
    final attemptId = _newAttemptId();
    if (idOrAnswerId.isEmpty) {
      throw ArgumentError('id or answerId required');
    }

    final uid = _uidOrThrow();

    // Detect if the caller passed a keep doc id ("<uid>_<answerId>") or a plain answerId.
    final bool looksLikeDocId = idOrAnswerId.startsWith('${uid}_');

    // Canonical answerId is always the part after "<uid>_" if present,
    // otherwise the raw idOrAnswerId.
    final String answerId =
        looksLikeDocId ? idOrAnswerId.substring(uid.length + 1) : idOrAnswerId;

    // Canonical keep document id always uses "<uid>_<answerId>".
    final String keepDocId = '${uid}_$answerId';

    // We now always allow toggle semantics: if the doc exists, delete; if it
    // does not exist, create it using the derived answerId.
    const bool allowCreate = true;

    final String path = 'keeps/$keepDocId';
    final docRef = _db.doc(path);

    _envStampOnce(attemptId);
    _dbg(
      attemptId,
      'ctx uid=$uid arg=$idOrAnswerId looksLikeDocId=$looksLikeDocId answerId=$answerId keepDocId=$keepDocId allowCreate=$allowCreate',
    );

    // Prefer server read to avoid cache races during rapid toggles.
    final preSnap = await docRef.get(const GetOptions(source: Source.server));
    final preExists = preSnap.exists;
    _dbg(attemptId, 'pre.exists server=$preExists');

    // ignore: avoid_print
    print('[Keep] toggle begin (firestore) id=$keepDocId');

    final t0 = DateTime.now().microsecondsSinceEpoch;
    try {
      if (preExists) {
        // UNKEEP — delete the document
        await docRef.delete();
      } else {
        // KEEP — always allowed now
        final Map<String, dynamic> base = <String, dynamic>{
          'userId': uid,
          'answerId': answerId,
          'createdAt': FieldValue.serverTimestamp(),
        };

        final snap = await _tryBuildSnapshot(answerId);
        if (snap != null) {
          base.addAll(snap);
        }

        await docRef.set(base, SetOptions(merge: false));
      }

      // Verify result from server
      final postSnap = await docRef.get(
        const GetOptions(source: Source.server),
      );
      final keptNow = postSnap.exists;

      final t1 = DateTime.now().microsecondsSinceEpoch;
      _dbg(
        attemptId,
        'result=SUCCESS kept=$keptNow durationMs=${(t1 - t0) / 1000.0}',
      );

      // ignore: avoid_print
      print('[Keep] toggle ok (firestore) id=$keepDocId kept=$keptNow');
      return keptNow;
    } catch (e, st) {
      final t1 = DateTime.now().microsecondsSinceEpoch;
      _dbg(
        attemptId,
        'result=ERROR durationMs=${(t1 - t0) / 1000.0} type=${e.runtimeType} err=$e',
      );
      _dbg(attemptId, 'stack=$st');
      rethrow;
    }
  }

  @override
  Future<Paged<Keep>> getKeepsForCurrentUser({
    int limit = 20,
    DateTime? startAfterCreatedAt,
  }) async {
    final uid = _uidOrThrow();

    Query<Map<String, dynamic>> q = _db
        .collection('keeps')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfterCreatedAt != null) {
      q = q.startAfter([Timestamp.fromDate(startAfterCreatedAt)]);
    }

    QuerySnapshot<Map<String, dynamic>> snap;

    try {
      // Prefer fresh server data so an empty cache doesn’t mask new keeps
      snap = await q.get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      // Missing composite index for (userId ==, orderBy createdAt desc)
      if (e.code.toLowerCase() == 'failed-precondition') {
        final q2 = _db
            .collection('keeps')
            .where('userId', isEqualTo: uid)
            .limit(limit);
        snap = await q2.get(const GetOptions(source: Source.server));
      } else {
        rethrow;
      }
    }

    final keeps =
        snap.docs.map((d) {
          final m = d.data();

          // createdAt: support both Timestamp and legacy int millis
          late final DateTime createdAt;
          final created = m['createdAt'];
          if (created is Timestamp) {
            createdAt = created.toDate();
          } else if (created is int) {
            createdAt = DateTime.fromMillisecondsSinceEpoch(created);
          } else {
            createdAt = DateTime.now();
          }

          // readAt: support both Timestamp and legacy int millis
          DateTime? readAt;
          final read = m['readAt'];
          if (read is Timestamp) {
            readAt = read.toDate();
          } else if (read is int) {
            readAt = DateTime.fromMillisecondsSinceEpoch(read);
          } else {
            readAt = null;
          }

          // Optional snapshot fields (feed/answer)
          final String? origin = m['origin'] as String?;
          final String? colorHex = (m['colorHex'] as String?)?.trim();
          final String? title = (m['title'] as String?)?.trim();
          final String? creatorName = (m['creatorName'] as String?)?.trim();

          DateTime? sentAt;
          final sent = m['sentAt'];
          if (sent is Timestamp) {
            sentAt = sent.toDate();
          } else if (sent is int) {
            sentAt = DateTime.fromMillisecondsSinceEpoch(sent);
          }

          return Keep(
            id: d.id,
            userId: (m['userId'] as String?) ?? '',
            answerId: (m['answerId'] as String?) ?? '',
            createdAt: createdAt,
            readAt: readAt,
            origin: origin,
            colorHex: colorHex,
            title: title,
            creatorName: creatorName,
            sentAt: sentAt,
          );
        }).toList();

    // Local sort ensures correct order if we fell back to the non-indexed query.
    keeps.sort((a, b) => (b.createdAt).compareTo(a.createdAt));

    final hasMore = keeps.length == limit;
    final nextCursor = hasMore ? keeps.last.createdAt : null;
    return Paged(
      items: keeps,
      nextCreatedAtCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  /// Mark a kept item as read so its black outline clears — by **keep document id**.
  Future<void> markReadKept(String keepDocId) async {
    if (keepDocId.isEmpty) {
      throw ArgumentError('keepDocId required');
    }
    await _db.doc('keeps/$keepDocId').set({
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
