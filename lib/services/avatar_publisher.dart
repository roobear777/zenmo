import 'package:cloud_firestore/cloud_firestore.dart';

const _white = '#FFFFFF';
const _grey = '#E6E8ED';

List<int> _centerOutSpiral({int rows = 5, int cols = 5}) {
  final total = rows * cols;
  final order = <int>[];
  int r = rows ~/ 2, c = cols ~/ 2;
  order.add(r * cols + c);
  int step = 1, d = 0;
  const dirs = [
    [0, 1], // right
    [1, 0], // down
    [0, -1], // left
    [-1, 0], // up
  ];
  while (order.length < total) {
    for (int rep = 0; rep < 2; rep++) {
      final dx = dirs[d % 4][0], dy = dirs[d % 4][1];
      for (int s = 0; s < step; s++) {
        r += dx;
        c += dy;
        if (r >= 0 && r < rows && c >= 0 && c < cols) {
          order.add(r * cols + c);
          if (order.length == total) return order;
        }
      }
      d++;
    }
    step++;
  }
  return order;
}

List<List<String>> _makeChecker({int rows = 5, int cols = 5}) => List.generate(
  rows,
  (r) => List.generate(cols, (c) => ((r + c) % 2 == 0) ? _white : _grey),
);

String _intArgbToHex(int v) {
  final rgb = v & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

List<String> _normalizeHexList(List<dynamic>? raw) {
  if (raw == null) return const [];
  final out = <String>[];
  for (final x in raw) {
    if (x is int) {
      out.add(_intArgbToHex(x));
    } else if (x is String) {
      final s = x.startsWith('#') ? x.substring(1) : x;
      if (s.length == 6) {
        final ok = int.tryParse(s, radix: 16);
        if (ok != null) out.add('#${s.toUpperCase()}');
      }
    }
  }
  return out;
}

List<List<String>> buildAvatarGridFromHex(List<String> hexes) {
  const total = 25;
  final spiral = _centerOutSpiral();
  final grid = _makeChecker();
  final progress = hexes.length.clamp(0, total);
  for (int i = 0; i < progress; i++) {
    final idx = spiral[i];
    final r = idx ~/ 5, c = idx % 5;
    grid[r][c] = hexes[i].toUpperCase();
  }
  return grid;
}

/// Upsert /users/{uid}/public/avatar with monotonic progress in a transaction.
Future<void> _upsertPublicAvatar({
  required FirebaseFirestore db,
  required String uid,
  required List<String> denseHex, // normalized #RRGGBB, max 25
}) async {
  final ref = db
      .collection('users')
      .doc(uid)
      .collection('public')
      .doc('avatar');
  final grid = buildAvatarGridFromHex(denseHex);
  final progress = denseHex.length.clamp(0, 25);

  await db.runTransaction((txn) async {
    final snap = await txn.get(ref);
    int prev = 0;
    if (snap.exists) {
      final data = snap.data() ?? {};
      final p = data['progress'];
      if (p is int) prev = p;
    }
    final next = (progress > prev) ? progress : prev;
    txn.set(ref, {
      'grid': grid,
      'progress': next,
      'total': 25,
      'version': 1,
      'updatedAt': FieldValue.serverTimestamp(),
      if (!snap.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  });
}

/// Reads the user’s draft fingerprint and publishes the 5×5 avatar
/// (no monthly, no shuffle; monotonic progress).
Future<void> publishAvatarForUser({
  required FirebaseFirestore db,
  required String uid,
}) async {
  // read draft (private)
  final draftRef = db
      .collection('users')
      .doc(uid)
      .collection('private')
      .doc('fingerprint');
  final draftSnap = await draftRef.get();
  final draft = draftSnap.data() ?? const <String, dynamic>{};
  final draftHex = _normalizeHexList(draft['answersHex']);
  final draftIntsHex = _normalizeHexList(draft['answers']);
  final chosen =
      (draftHex.isNotEmpty ? draftHex : draftIntsHex).take(25).toList();

  await _upsertPublicAvatar(db: db, uid: uid, denseHex: chosen);
}
