// lib/debug/keeps_debug.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Standalone debug helper for Daily Hues keeps.
/// Call `KeepsDebug.runOnce()` from somewhere (e.g. WalletScreen.initState)
/// while logged in; check console output for [KeepsDebug] lines.
class KeepsDebug {
  static bool _hasRun = false;

  static String _newAttemptId() {
    final now = DateTime.now().toUtc().toIso8601String();
    final r = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '$now-$r';
  }

  static void _log(String attemptId, String msg) {
    // ignore: avoid_print
    print('[KeepsDebug][$attemptId] $msg');
  }

  static String _uidOrThrow() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('KeepsDebug: Not signed in');
    }
    return uid;
  }

  /// Run a one-off debug pass:
  /// 1) List raw /keeps docs for current user.
  /// 2) For each keep, try to load matching /answers and /public_feed docs.
  static Future<void> runOnce() async {
    if (_hasRun) {
      // avoid spamming logs if called multiple times
      return;
    }
    _hasRun = true;

    final attemptId = _newAttemptId();
    final db = FirebaseFirestore.instance;

    try {
      final uid = _uidOrThrow();
      _log(attemptId, 'Starting keeps debug for uid=$uid');

      // ---- 1) RAW /keeps docs for this user ----
      Query<Map<String, dynamic>> q = db
          .collection('keeps')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true);

      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await q.get(const GetOptions(source: Source.server));
      } on FirebaseException catch (e) {
        // If composite index missing for (userId ==, orderBy createdAt desc),
        // fall back to simple query just to see *something*.
        if (e.code.toLowerCase() == 'failed-precondition') {
          _log(
            attemptId,
            'WARN: missing index for userId+createdAt, falling back to simple where(userId)',
          );
          snap = await db
              .collection('keeps')
              .where('userId', isEqualTo: uid)
              .get(const GetOptions(source: Source.server));
        } else {
          rethrow;
        }
      }

      _log(attemptId, 'RAW /keeps query returned docs=${snap.docs.length}');

      if (snap.docs.isEmpty) {
        _log(
          attemptId,
          'No keeps found for this user. If you expect some, this hints at RULES or WRITE issues.',
        );
        return;
      }

      // ---- 2) Inspect each keep + matching answer/public_feed ----
      for (final d in snap.docs) {
        final m = d.data();
        final keepId = d.id;
        final userId = m['userId'];
        final answerId = m['answerId'];
        final createdAt = m['createdAt'];
        final origin = m['origin'];
        final colorHex = m['colorHex'];
        final title = m['title'];
        final creatorName = m['creatorName'];
        final sentAt = m['sentAt'];
        final readAt = m['readAt'];

        _log(
          attemptId,
          'KEEP raw id=$keepId '
          'userId=$userId '
          'answerId=$answerId '
          'createdAt=$createdAt '
          'origin=$origin '
          'colorHex=$colorHex '
          'title=$title '
          'creatorName=$creatorName '
          'sentAt=$sentAt '
          'readAt=$readAt',
        );

        if (answerId is! String || answerId.isEmpty) {
          _log(attemptId, '  ↳ SKIP: answerId missing or not a string');
          continue;
        }

        // 2a) Try /answers/{answerId}
        try {
          final ansDoc = await db
              .collection('answers')
              .doc(answerId)
              .get(const GetOptions(source: Source.server));
          if (ansDoc.exists) {
            final a = ansDoc.data() ?? const <String, dynamic>{};
            _log(
              attemptId,
              '  ↳ ANSWER FOUND: id=$answerId '
              'colorHex=${a['colorHex']} '
              'title=${a['title']} '
              'responderId=${a['responderId']} '
              'createdAt=${a['createdAt']}',
            );
          } else {
            _log(
              attemptId,
              '  ↳ ANSWER MISSING: /answers/$answerId does not exist',
            );
          }
        } catch (e) {
          _log(attemptId, '  ↳ ERROR reading /answers/$answerId : $e');
        }

        // 2b) Try /public_feed/{answerId} (Daily Hues keeps often mirror feed)
        try {
          final feedDoc = await db
              .collection('public_feed')
              .doc(answerId)
              .get(const GetOptions(source: Source.server));
          if (feedDoc.exists) {
            final f = feedDoc.data() ?? const <String, dynamic>{};
            _log(
              attemptId,
              '  ↳ FEED FOUND: id=$answerId '
              'type=${f['type']} '
              'colorHex=${f['colorHex']} '
              'title=${f['title']} '
              'creatorName=${f['creatorName']} '
              'sentAt=${f['sentAt']} '
              'utcDay=${f['utcDay']} '
              'day=${f['day']}',
            );
          } else {
            _log(
              attemptId,
              '  ↳ FEED MISSING: /public_feed/$answerId does not exist',
            );
          }
        } catch (e) {
          _log(attemptId, '  ↳ ERROR reading /public_feed/$answerId : $e');
        }
      }

      _log(attemptId, 'Keeps debug finished.');
    } catch (e, st) {
      _log(attemptId, 'FATAL ERROR type=${e.runtimeType} err=$e stack=$st');
    }
  }
}
