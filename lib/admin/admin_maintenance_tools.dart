import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart'; // combineLatest2
import 'package:color_wallet/fingerprint_questions.dart'; // kFingerprintQs, kFingerprintTotal

class AdminFingerprintAnswersTab extends StatefulWidget {
  const AdminFingerprintAnswersTab({
    super.key,
    required this.db,
    required this.start,
    required this.end,
    this.maxDocsForStats = 1000,
  });

  final FirebaseFirestore db;
  final Timestamp start;
  final Timestamp end;
  final int maxDocsForStats;

  @override
  State<AdminFingerprintAnswersTab> createState() =>
      _AdminFingerprintAnswersTabState();
}

class _AdminFingerprintAnswersTabState extends State<AdminFingerprintAnswersTab>
    with AutomaticKeepAliveClientMixin {
  final Map<String, String> _usernames = {}; // uid -> username (may be empty)
  bool _resolvingNames = false;

  @override
  bool get wantKeepAlive => true;

  /// Combined stream for completed + in-progress fingerprints (live, all-time)
  Stream<List<DocumentSnapshot<Map<String, dynamic>>>> _fpStream() {
    final completed =
        widget.db
            .collectionGroup('fingerprints')
            .orderBy('createdAt', descending: true)
            .limit(widget.maxDocsForStats)
            .snapshots();

    // Fetch all /private docs (we'll filter to 'fingerprint' client-side)
    final drafts =
        widget.db
            .collectionGroup('private')
            .limit(widget.maxDocsForStats)
            .snapshots();

    return Rx.combineLatest2<
      QuerySnapshot<Map<String, dynamic>>,
      QuerySnapshot<Map<String, dynamic>>,
      List<DocumentSnapshot<Map<String, dynamic>>>
    >(completed, drafts, (a, b) => [...a.docs, ...b.docs]);
  }

  // Extract UID from any /users/{uid}/subcollection/... document
  String _ownerUidOf(DocumentSnapshot<Map<String, dynamic>> d) {
    try {
      final parent = d.reference.parent; // subcollection
      final usersDoc = parent.parent; // users/{uid}
      if (usersDoc != null) return usersDoc.id;
    } catch (_) {}
    return '';
  }

  // Convert supported answer forms to Color
  Color _toColor(dynamic v) {
    if (v is String && v.startsWith('#') && (v.length == 7 || v.length == 9)) {
      final hex = v.substring(1);
      final argb = (hex.length == 6 ? 'FF$hex' : hex);
      return Color(int.parse(argb, radix: 16));
    }
    if (v is int) {
      return Color(0xFF000000 | (v & 0x00FFFFFF));
    }
    return const Color(0xFFCCCCCC);
  }

  Future<void> _ensureUsernames(Set<String> uids) async {
    final missing = <String>[];
    for (final id in uids) {
      if (id.isEmpty) continue;
      if (!_usernames.containsKey(id)) missing.add(id);
    }
    if (missing.isEmpty || _resolvingNames) return;

    _resolvingNames = true;
    try {
      const chunkSize = 10;
      for (var i = 0; i < missing.length; i += chunkSize) {
        final chunk = missing.sublist(
          i,
          math.min(i + chunkSize, missing.length),
        );
        try {
          final snap =
              await widget.db
                  .collection('users')
                  .where(FieldPath.documentId, whereIn: chunk)
                  .get();
          for (final d in snap.docs) {
            final m = d.data();
            final uname = (m['username'] as String?)?.trim() ?? '';
            _usernames[d.id] = uname;
          }
          for (final id in chunk) {
            _usernames[id] = _usernames[id] ?? '';
          }
        } catch (_) {
          for (final id in chunk) {
            _usernames[id] = _usernames[id] ?? '';
          }
        }
      }
    } finally {
      _resolvingNames = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final total = (kFingerprintTotal >= 25) ? 25 : kFingerprintTotal;
    final List<String> qTexts = List<String>.generate(25, (i) {
      if (i < total) return kFingerprintQs[i];
      return '';
    });

    return StreamBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
      stream: _fpStream(),
      builder: (context, fpSnap) {
        if (fpSnap.hasError) {
          return Center(child: Text('Data error: ${fpSnap.error}'));
        }
        if (!fpSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = fpSnap.data!;

        // 1) Pick ONE best doc per user (prefer more answers; tie -> newer createdAt)
        final bestByUid = <String, Map<String, dynamic>>{};
        final createdByUid = <String, DateTime?>{};
        final sourceIsPrivate = <String, bool>{};

        for (final d in docs) {
          // Only keep /users/{uid}/private/fingerprint from the 'private' group
          try {
            if (d.reference.parent.id == 'private' && d.id != 'fingerprint') {
              continue;
            }
          } catch (_) {}

          final m = d.data();
          if (m == null) continue;

          final uid = _ownerUidOf(d);
          if (uid.isEmpty) continue;

          final answersRaw = (m['answersHex'] ?? m['answers'] ?? m['colors']);
          if (answersRaw is! List) continue;

          final answersLen = answersRaw.length;
          DateTime? created;
          final ts = m['createdAt'];
          if (ts is Timestamp) {
            created = ts.toDate();
          } else if (ts is DateTime) {
            created = ts;
          }

          final prev = bestByUid[uid];
          if (prev == null) {
            bestByUid[uid] = m;
            createdByUid[uid] = created;
            sourceIsPrivate[uid] = (d.reference.parent.id == 'private');
          } else {
            final prevAns =
                (prev['answersHex'] ?? prev['answers'] ?? prev['colors']);
            final prevLen = (prevAns is List) ? prevAns.length : 0;
            final prevCreated = createdByUid[uid];

            bool takeNew = false;
            if (answersLen > prevLen) {
              takeNew = true;
            } else if (answersLen == prevLen) {
              // prefer newer createdAt (nulls treated oldest)
              final prevMillis = prevCreated?.millisecondsSinceEpoch ?? -1;
              final curMillis = created?.millisecondsSinceEpoch ?? -1;
              if (curMillis > prevMillis) takeNew = true;
            }
            if (takeNew) {
              bestByUid[uid] = m;
              createdByUid[uid] = created;
              sourceIsPrivate[uid] = (d.reference.parent.id == 'private');
            }
          }
        }

        // 2) Build tiles from the chosen doc per user
        final tilesByQ = List<List<_FpTile>>.generate(25, (_) => <_FpTile>[]);
        final uids = <String>{};

        bestByUid.forEach((uid, m) {
          final answers = (m['answersHex'] ?? m['answers'] ?? m['colors']);
          if (answers is! List) return;
          uids.add(uid);

          final created = createdByUid[uid];

          final count = math.min(25, answers.length);
          for (var i = 0; i < count; i++) {
            final raw = answers[i];
            final color = _toColor(raw);
            tilesByQ[i].add(
              _FpTile(uid: uid, color: color, createdAt: created),
            );
          }
        });

        // 3) Resolve usernames (async)
        _ensureUsernames(uids);

        // 4) Stats
        int totalUsers = bestByUid.length;
        int completed = 0;
        int partial = 0;
        int unknowns = 0;

        bestByUid.forEach((uid, m) {
          final answers = (m['answersHex'] ?? m['answers'] ?? m['colors']);
          final len = (answers is List) ? answers.length : 0;
          if (len >= 25) {
            completed++;
          } else {
            partial++;
          }
          final uname = _usernames[uid] ?? '';
          if (uname.isEmpty) unknowns++;
        });

        // 5) UI: stats bar + question rows
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatsBar(
              totalUsers: totalUsers,
              completed: completed,
              partial: partial,
              unknowns: unknowns,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: 25,
                itemBuilder: (context, i) {
                  final number = i + 1;
                  final labelText =
                      (i < total && kFingerprintQs[i].isNotEmpty)
                          ? 'Q$number  •  ${kFingerprintQs[i]}'
                          : 'Q$number';
                  final rowTiles = tilesByQ[i];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _QuestionRow(
                      labelText: labelText,
                      tiles: rowTiles,
                      usernameOf: (uid) {
                        final u = _usernames[uid] ?? '';
                        if (u.isNotEmpty) return u;
                        return uid.isNotEmpty && uid.length >= 6
                            ? '(unknown • ${uid.substring(0, 6)})'
                            : '(unknown)';
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.totalUsers,
    required this.completed,
    required this.partial,
    required this.unknowns,
  });

  final int totalUsers;
  final int completed;
  final int partial;
  final int unknowns;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final muted = style?.copyWith(color: const Color(0xFF666A76));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          Text('People: $totalUsers', style: muted),
          Text('Completed: $completed', style: muted),
          Text('Partial: $partial', style: muted),
          Text('Unknown names: $unknowns', style: muted),
        ],
      ),
    );
  }
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({
    required this.labelText,
    required this.tiles,
    required this.usernameOf,
  });

  final String labelText;
  final List<_FpTile> tiles;
  final String Function(String uid) usernameOf;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.only(top: 6, right: 12),
            child: Text(
              labelText,
              softWrap: true,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  tiles.map((t) {
                    final uname = usernameOf(t.uid);
                    final subtitle = _formatTooltip(uname, t.createdAt);
                    return Tooltip(
                      message: subtitle,
                      preferBelow: false,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: t.color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0x15000000)),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  String _formatTooltip(String uname, DateTime? dt) {
    final n = (uname.isEmpty) ? '(unknown)' : uname;
    if (dt == null) return n;
    String two(int v) => v.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final m = two(dt.month);
    final d = two(dt.day);
    final hh = two(dt.hour);
    final mm = two(dt.minute);
    return '$n • $y-$m-$d $hh:$mm';
  }
}

class _FpTile {
  _FpTile({required this.uid, required this.color, required this.createdAt});
  final String uid;
  final Color color;
  final DateTime? createdAt;
}
