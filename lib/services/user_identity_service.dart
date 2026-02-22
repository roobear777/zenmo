// lib/services/user_identity_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'dart:async' show unawaited;

/// Manages the signed-in user and their Firestore profile.
class UserIdentityService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Read once from --dart-define=USE_FIRESTORE_EMU=true
  static const bool _useEmu = bool.fromEnvironment(
    'USE_FIRESTORE_EMU',
    defaultValue: false,
  );

  // Ensures we only run the self-test once per app session.
  static bool _usersRulesProbed = false;

  /// Returns the current Firebase user's UID, or throws if none.
  Future<String> getCurrentUserId() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No user is currently signed in.',
      );
    }
    return user.uid;
  }

  /// Returns the currently signed-in [User], or null if signed out.
  User? getCurrentUser() => _auth.currentUser;

  /// Returns the current user's display name, or 'anonymous' if not set.
  String get currentDisplayName {
    final user = _auth.currentUser;
    return (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : 'anonymous';
  }

  // ---- internal -----------------------------------------------------------

  /// Build a shallow copy without null values (rules prefer absent over null).
  Map<String, dynamic> _noNulls(Map<String, dynamic> m) =>
      Map<String, dynamic>.from(m)..removeWhere((k, v) => v == null);

  // ---- writers ------------------------------------------------------------

  /// Create/merge the user profile in Firestore under `users/{uid}`.
  /// Guardrails: this writer never touches username/usernameLower.
  Future<void> saveUserProfile(String displayName) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userDoc = _firestore.collection('users').doc(user.uid);
    final snap = await userDoc.get(); // <-- check existence once
    final now = Timestamp.now();

    final payload = _noNulls({
      'displayName': displayName.trim(),
      'email': user.email, // may be null -> stripped
      'lastActive': now,
      'updatedAt': now,
      'updatedAt': now,
      'createdAt': now,

      // set-once: only add createdAt on first create / if absent
      if (!snap.exists || (snap.data()?['createdAt'] == null)) 'createdAt': now,
    });

    await userDoc.set(payload, SetOptions(merge: true));
  }

  /// Sets (or clears) the user avatar URL. Pass `null` to clear.
  /// Also bumps `updatedAt` with a timestamp.
  Future<void> setAvatarUrl(String? url) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No user is currently signed in.',
      );
    }
    final now = Timestamp.now();
    await _firestore.collection('users').doc(user.uid).set({
      'photoURL': url, // null explicitly allowed by rules
      'updatedAt': now,
    }, SetOptions(merge: true));
  }

  /// Fetch the display name from Firestore (fallbacks to Auth/email prettified).
  Future<String?> getDisplayName() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final doc = await _firestore.collection('users').doc(user.uid).get();
    final fromDb = (doc.data()?['displayName'] as String?)?.trim();
    if (fromDb != null && fromDb.isNotEmpty) return fromDb;

    final fromAuth = user.displayName?.trim();
    if (fromAuth != null && fromAuth.isNotEmpty) return fromAuth;

    return _guessNameFromEmail(user.email) ?? 'You';
  }

  /// Ensure both Auth and Firestore have a usable display name.
  ///
  /// Guardrails:
  /// - Never writes username/usernameLower; claimNameOnSignup is the sole authority.
  /// - Uses timestamps compatible with your current CREATE rules.
  Future<void> ensureDisplayIdentity() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userRef = _firestore.collection('users').doc(user.uid);
    final snap = await userRef.get();

    final dbName = (snap.data()?['displayName'] as String?)?.trim();
    final authName = user.displayName?.trim();

    final targetName =
        (authName != null && authName.isNotEmpty)
            ? authName
            : (dbName != null && dbName.isNotEmpty)
            ? dbName
            : _guessNameFromEmail(user.email) ?? 'You';

    // Update Auth.displayName if missing (best-effort).
    if (authName == null || authName.isEmpty) {
      try {
        await user.updateDisplayName(targetName);
        await user.reload();
      } catch (_) {
        // Non-fatal; still write Firestore below.
      }
    }

    final now = Timestamp.now();

    // Mirror into Firestore (strip nulls first).
    final payload = _noNulls({
      'displayName': targetName,
      'email': user.email, // may be null -> stripped
      'lastActive': now,
      'updatedAt': now,
      // set-once: only add createdAt on first create / if absent
      if (!snap.exists || (snap.data()?['createdAt'] == null)) 'createdAt': now,
    });

    await userRef.set(payload, SetOptions(merge: true));

    // ---- DEBUG: run users rules probe once (only in debug + emulator define) ----
    if (!_usersRulesProbed && kDebugMode) {
      _usersRulesProbed = true;
      if (_useEmu) {
        unawaited(_debugUsersRulesCreateAndUpdate());
      }
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // --------------------------------------------------------------------------
  // Unique name claim at signup (sole authority for username/usernameLower)
  // --------------------------------------------------------------------------

  /// Claims `/usernames/{lower}` and writes username fields into `/users/{uid}`.
  /// - Enforces uniqueness of `usernameLower`.
  /// - Uses timestamps compatible with your current CREATE rules.
  /// - If the ledger document exists for the same uid, it is left intact
  ///   (we avoid resetting createdAt). We may backfill the mirror `username`.
  Future<void> claimNameOnSignup(String rawName) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No user is currently signed in.',
      );
    }
    final uid = user.uid;
    final email = user.email ?? '';

    final display = rawName.trim();
    if (display.isEmpty) {
      throw StateError('Please enter a name');
    }

    // 2–20 chars, letters/digits/space/._-
    final isValid = RegExp(r'^[a-zA-Z0-9._ \-]{2,20}$').hasMatch(display);
    if (!isValid) {
      throw StateError(
        'Name must be 2–20 chars (letters, numbers, space, . _ -)',
      );
    }

    final lower = display.toLowerCase();
    final usernamesRef = _firestore.collection('usernames').doc(lower);
    final userRef = _firestore.collection('users').doc(uid);

    // IMPORTANT: use a real timestamp (rules reject serverTimestamp on CREATE).
    final now = Timestamp.now();

    // NOTE (web): don’t throw from inside the transaction callback.
    // If the callback throws, Flutter web often surfaces only:
    // "Dart exception thrown from converted Future…"
    // Instead, return a boolean and throw *after* the transaction completes.
    final bool claimed = await _firestore.runTransaction<bool>((txn) async {
      // Check current ledger state.
      final claimSnap = await txn.get(usernamesRef);
      if (claimSnap.exists) {
        final owner = (claimSnap.data()?['uid'] as String?) ?? '';
        if (owner != uid) {
          // Name is owned by someone else: do nothing and signal failure.
          return false;
        }

        // Same owner: avoid resetting createdAt; backfill mirror username if missing.
        final hasUsernameField =
            claimSnap.data()?.containsKey('username') ?? false;
        if (!hasUsernameField) {
          txn.update(usernamesRef, {
            'username': display, // mirror, display-cased
          });
        }
      } else {
        // New claim: authoritative ledger doc
        txn.set(usernamesRef, {
          'uid': uid,
          'username': display, // display-cased mirror (recommended)
          'createdAt': now,
        }, SetOptions(merge: false));
      }

      // Only set createdAt on the user doc if it's missing (update rules forbid changes).
      final userSnap = await txn.get(userRef);
      final userHasCreatedAt =
          userSnap.exists && (userSnap.data()?['createdAt'] != null);

      final userPayload = <String, dynamic>{
        'username': display,
        'usernameLower': lower,
        'displayName': display,
        'email': email,
        'lastActive': now,
        'updatedAt': now,
        if (!userHasCreatedAt) 'createdAt': now,
      };

      txn.set(userRef, userPayload, SetOptions(merge: true));
      return true;
    });

    if (!claimed) {
      throw StateError('That name is taken');
    }
  }

  // --------------------------------------------------------------------------
  // DEBUG helpers (surgical rules probe)
  // --------------------------------------------------------------------------

  Future<void> _debugUsersRulesCreateAndUpdate() async {
    await _debugUsersRulesCreate();
    await _debugUsersRulesUpdate();
  }

  Future<void> _debugUsersRulesCreate() async {
    final u = _auth.currentUser;
    if (u == null) {
      // ignore: avoid_print
      print('[users:create] no user');
      return;
    }
    final ref = _firestore.collection('users').doc(u.uid);
    final now = Timestamp.now();

    final Map<String, dynamic> payload = {
      'displayName': 'RulesProbe',
      'email': u.email, // may be null; stripped below
      'photoURL': null, // explicitly allowed in rules (we test this)
      'status': 'active',
      'lastActive': now,
      'updatedAt': now,
    };

    // strip nulls everywhere EXCEPT photoURL (we want to test null handling for it)
    final safe = _noNulls(payload);
    safe['photoURL'] = null;

    try {
      await ref.set(safe, SetOptions(merge: true));
      final snap = await ref.get();
      // ignore: avoid_print
      print('[users:create] OK -> ${snap.data()}');
    } catch (e) {
      // ignore: avoid_print
      print('[users:create] ERROR -> $e');
    }
  }

  Future<void> _debugUsersRulesUpdate() async {
    final u = _auth.currentUser;
    if (u == null) {
      // ignore: avoid_print
      print('[users:update] no user');
      return;
    }
    final ref = _firestore.collection('users').doc(u.uid);
    final now = Timestamp.now();

    final Map<String, dynamic> payload = {'lastActive': now, 'updatedAt': now};

    try {
      await ref.update(payload);
      final snap = await ref.get();
      // ignore: avoid_print
      print('[users:update] OK -> ${snap.data()}');
    } catch (e) {
      // ignore: avoid_print
      print('[users:update] ERROR -> $e');
    }
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  String? _guessNameFromEmail(String? email) {
    if (email == null || email.trim().isEmpty) return null;
    final local = email.split('@').first;
    if (local.isEmpty) return null;

    final cleaned = local.replaceAll(RegExp(r'[._\\-]+'), ' ').trim();
    if (cleaned.isEmpty) return null;

    return cleaned
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))
        .join(' ');
  }
}
