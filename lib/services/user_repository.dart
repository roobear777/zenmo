import 'package:cloud_firestore/cloud_firestore.dart';

class UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final doc = await _usersCollection.doc(userId).get();
    if (doc.exists) return doc.data();
    return null;
  }

  Future<void> setUserProfile(String userId, Map<String, dynamic> data) async {
    await _usersCollection.doc(userId).set(data, SetOptions(merge: true));
  }

  Future<void> updateUserProfileField(
    String userId,
    String field,
    dynamic value,
  ) async {
    if (field == 'createdAt') return; // hard-stop: preserve join date
    await _usersCollection.doc(userId).update({field: value});
  }

  Future<void> saveUserProfile(String userId, String displayName) async {
    await setUserProfile(userId, {'displayName': displayName});
  }

  /// Returns only **canonical** (non-legacy) users, excluding [excludeUid].
  /// - Skips docs with isLegacy == true
  /// - For each remaining user, exposes `effectiveUid` = canonicalUid ?? doc.id
  /// - De-dupes by that effectiveUid to avoid duplicates after migrations
  Future<List<AppUser>> getAllUsersExcluding(String excludeUid) async {
    final snapshot = await _usersCollection.get();

    // Map by the canonical identity key so we don't surface duplicates.
    final Map<String, AppUser> byCanonical = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final docUid = doc.id;

      if (docUid == excludeUid) continue;

      final bool isLegacy = data['isLegacy'] == true;
      if (isLegacy) continue; // hide legacy accounts in pickers

      final String? canonicalUid = _safeTrim(data['canonicalUid']);
      final String effectiveUid =
          canonicalUid?.isNotEmpty == true ? canonicalUid! : docUid;

      // Build the user model we show in pickers.
      final user = AppUser(
        uid: docUid, // raw doc id (kept for reference)
        effectiveUid: effectiveUid, // uid we should send to
        displayName: _safeTrim(data['displayName']) ?? docUid,
        email: _safeTrim(data['email']),
        canonicalUid: canonicalUid,
        isLegacy: false,
      );

      // Keep first seen canonical identity (or add tie-breakers if you need).
      byCanonical.putIfAbsent(effectiveUid, () => user);
    }

    final list =
        byCanonical.values.toList()..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );

    return list;
  }

  /// --- NEW: Resolve to canonical UID (use this right before sending) ---
  Future<String> resolveCanonicalUid(String uid) async {
    final snap = await _usersCollection.doc(uid).get();
    final data = snap.data();
    if (data == null) return uid;

    final String? canonical = _safeTrim(data['canonicalUid']);
    final bool isLegacy = data['isLegacy'] == true;

    if (isLegacy && canonical != null && canonical.isNotEmpty) {
      return canonical; // legacy doc points to live account
    }
    if (canonical != null && canonical.isNotEmpty) {
      return canonical; // non-legacy but has canonical set (safe to prefer)
    }
    return uid;
  }

  /// --- NEW: block a user ---
  Future<void> blockUser({
    required String blockerUid,
    required String blockedUid,
  }) async {
    final blockDoc = _usersCollection
        .doc(blockerUid)
        .collection('blocks')
        .doc(blockedUid);

    await blockDoc.set({
      'blockedUid': blockedUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// --- NEW: check if a user is blocked ---
  Future<bool> isBlocked({
    required String blockerUid,
    required String blockedUid,
  }) async {
    final blockDoc =
        await _usersCollection
            .doc(blockerUid)
            .collection('blocks')
            .doc(blockedUid)
            .get();

    return blockDoc.exists;
  }

  // ---- helpers ----
  String? _safeTrim(Object? v) {
    if (v is String) return v.trim();
    return null;
  }
}

class AppUser {
  /// The Firestore doc id for this user (may be legacy).
  final String uid;

  /// The UID you should actually use for addressing (canonicalUid ?? uid).
  final String effectiveUid;

  final String displayName;
  final String? email;
  final String? canonicalUid;
  final bool isLegacy;

  AppUser({
    required this.uid,
    required this.effectiveUid,
    required this.displayName,
    this.email,
    this.canonicalUid,
    this.isLegacy = false,
  });

  factory AppUser.fromFirestore(String id, Map<String, dynamic> data) {
    final canonical = (data['canonicalUid'] as String?)?.trim();
    final isLegacy = data['isLegacy'] == true;
    return AppUser(
      uid: id,
      effectiveUid:
          (canonical != null && canonical.isNotEmpty) ? canonical : id,
      displayName:
          (data['displayName'] as String?)?.trim().isNotEmpty == true
              ? (data['displayName'] as String).trim()
              : id,
      email: (data['email'] as String?)?.trim(),
      canonicalUid: canonical,
      isLegacy: isLegacy,
    );
  }
}
