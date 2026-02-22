// lib/services/avatar_helper.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Avatar policy (keep constant across app):
/// - Not monthly; derived from the draft's dense prefix only (first 25 colors)
/// - Never shuffles
/// - Checkerboard base; fills cells in a 5×5 center-out spiral
///
/// Public doc path: /users/{uid}/public/avatar
/// Shape:
/// {
///   grid: 25-length flat list of "#RRGGBB" (row-major 5×5),
///   progress: 0..25,
///   total: 25,
///   version: 1,
///   createdAt, updatedAt
/// }

const _WHITE = '#FFFFFF';
const _GREY = '#E6E8ED';

/// Fixed center-out spiral over a 5x5 grid (row-major indices 0..24).
const List<int> _SPIRAL_5x5 = <int>[
  12,
  13,
  18,
  17,
  16,
  11,
  6,
  7,
  8,
  9,
  14,
  19,
  24,
  23,
  22,
  21,
  20,
  15,
  10,
  5,
  0,
  1,
  2,
  3,
  4,
];

/// Make a 5x5 checkerboard.
List<List<String>> _blankGrid() => List.generate(
  5,
  (r) => List.generate(5, (c) => ((r + c) % 2 == 0) ? _WHITE : _GREY),
  growable: false,
);

/// ARGB int (0xAARRGGBB) -> "#RRGGBB" (alpha dropped)
String _intToHexRgb(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = (argb) & 0xFF;
  String two(int v) => v.toRadixString(16).padLeft(2, '0');
  return '#${two(r)}${two(g)}${two(b)}'.toUpperCase();
}

/// Accepts either a string "#RRGGBB" / "RRGGBB" or an int 0xAARRGGBB.
/// Returns "#RRGGBB" or null.
String? _normToHexRgb(dynamic v) {
  if (v is int) return _intToHexRgb(v);
  if (v is String) {
    final s = v.trim();
    final h = s.startsWith('#') ? s.substring(1) : s;
    if (h.length == 6 && int.tryParse(h, radix: 16) != null) {
      return '#${h.toUpperCase()}';
    }
  }
  return null;
}

/// Build a 5x5 avatar grid from a dense list of "#RRGGBB" colors (max 25).
List<List<String>> _gridFromDenseHex(List<String> denseHex) {
  final grid = _blankGrid();
  final progress = denseHex.length.clamp(0, 25);
  for (int i = 0; i < progress; i++) {
    final idx = _SPIRAL_5x5[i];
    final r = idx ~/ 5, c = idx % 5;
    grid[r][c] = denseHex[i];
  }
  return grid;
}

/// Public entry point used by FingerprintRepo:
/// Writes /users/{uid}/public/avatar with monotonic progress.
/// - `denseHex` must already be "#RRGGBB" (we'll trust caller here).
Future<void> upsertPublicAvatar({
  required FirebaseFirestore db,
  required String uid,
  required List<String> denseHex, // first 25 colors from draft
}) async {
  final avatarRef = db
      .collection('users')
      .doc(uid)
      .collection('public')
      .doc('avatar');

  final clamped = (denseHex.length > 25) ? denseHex.sublist(0, 25) : denseHex;

  // Build 5×5 grid, then FLATTEN to a 25-length list for Firestore.
  final grid = _gridFromDenseHex(clamped);
  final flatGrid = grid.expand((row) => row).toList(growable: false);
  final progress = clamped.length.clamp(0, 25);

  await db.runTransaction((txn) async {
    final snap = await txn.get(avatarRef);
    final existed = snap.exists;
    final data = snap.data() ?? const {};
    final prev = (data['progress'] is int) ? data['progress'] as int : 0;
    final next = (progress > prev) ? progress : prev;

    txn.set(avatarRef, <String, dynamic>{
      'grid': flatGrid, // flat List<String>, length 25
      'progress': next,
      'total': 25,
      'version': 1,
      'updatedAt': FieldValue.serverTimestamp(),
      if (!existed) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  });
}

/// Optional helper if you ever want to compute from the draft on client:
/// Reads /users/{uid}/private/fingerprint and publishes avatar.
/// Not used by the repo today (repo already passes colors), but handy.
Future<void> publishAvatarFromDraft({
  required FirebaseFirestore db,
  required String uid,
}) async {
  final draftRef = db
      .collection('users')
      .doc(uid)
      .collection('private')
      .doc('fingerprint');

  final snap = await draftRef.get();
  final data = snap.data() ?? const <String, dynamic>{};

  // Prefer answersHex (strings). Fallback to answers (ints).
  final List<dynamic> hexRaw =
      (data['answersHex'] is List) ? data['answersHex'] as List : const [];
  final List<dynamic> intsRaw =
      (data['answers'] is List) ? data['answers'] as List : const [];

  List<String> dense = [];
  if (hexRaw.isNotEmpty) {
    dense = hexRaw
        .map(_normToHexRgb)
        .whereType<String>()
        .toList(growable: false);
  } else if (intsRaw.isNotEmpty) {
    dense = intsRaw
        .map(_normToHexRgb)
        .whereType<String>()
        .toList(growable: false);
  }

  if (dense.isNotEmpty) {
    await upsertPublicAvatar(
      db: db,
      uid: uid,
      denseHex: dense.take(25).toList(growable: false),
    );
  } else {
    // Nothing to publish yet; do not overwrite existing avatar.
  }
}

/// Backwards-compat helper for older call sites that used this name.
/// Simply delegates to [publishAvatarFromDraft].
Future<void> publishAvatarForUser({
  required FirebaseFirestore db,
  required String uid,
}) {
  return publishAvatarFromDraft(db: db, uid: uid);
}
