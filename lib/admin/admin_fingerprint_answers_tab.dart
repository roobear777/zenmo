import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart'; // combineLatest2
import 'package:color_wallet/fingerprint_questions.dart'; // kFingerprintQs, kFingerprintTotal
import 'package:color_wallet/admin/admin_components.dart' show AdminNameCache;
import 'package:color_wallet/admin/admin_fingerprints_tab.dart';

class _QuestionAgg {
  final Map<String, int> counts = <String, int>{}; // hex -> freq
  DateTime latest = DateTime.fromMillisecondsSinceEpoch(0);
  int get responses => counts.values.fold(0, (a, b) => a + b);
  List<String> colorsByFreq() {
    final list =
        counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.map((e) => e.key).toList();
  }
}

class AdminFingerprintAnswersTab extends StatefulWidget {
  const AdminFingerprintAnswersTab({
    super.key,
    required this.db,
    this.startUtc, // legacy/no-op
    this.endUtc, // legacy/no-op
    this.maxDocsForStats = 1000,
  });

  final FirebaseFirestore db;
  final Timestamp? startUtc;
  final Timestamp? endUtc;
  final int maxDocsForStats;

  @override
  State<AdminFingerprintAnswersTab> createState() =>
      _AdminFingerprintAnswersTabState();
}

class _AdminFingerprintAnswersTabState extends State<AdminFingerprintAnswersTab>
    with AutomaticKeepAliveClientMixin {
  late AdminNameCache _names;

  // Local index per question: hex -> set of uids
  // _hexToUidsByQ[i][hex] = {uid1, uid2, ...}
  List<Map<String, Set<String>>> _hexToUidsByQ = const [];

  @override
  void initState() {
    super.initState();
    _names = AdminNameCache(widget.db);
  }

  @override
  bool get wantKeepAlive => true;

  /// Completed versions + drafts (only /users/{uid}/private/fingerprint).
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fpStream() {
    final completed =
        widget.db
            .collectionGroup('fingerprints')
            .orderBy('createdAt', descending: true)
            .limit(widget.maxDocsForStats)
            .snapshots();

    final drafts =
        widget.db
            .collectionGroup('private')
            .limit(widget.maxDocsForStats)
            .snapshots();

    return Rx.combineLatest2<
      QuerySnapshot<Map<String, dynamic>>,
      QuerySnapshot<Map<String, dynamic>>,
      List<QueryDocumentSnapshot<Map<String, dynamic>>>
    >(completed, drafts, (a, b) {
      final all = <QueryDocumentSnapshot<Map<String, dynamic>>>[
        ...a.docs,
        ...b.docs,
      ];

      // Keep only /users/{uid}/private/fingerprint from the 'private' group
      final filtered =
          all.where((d) {
            try {
              final parent = d.reference.parent;
              if (parent.id == 'private' && d.id != 'fingerprint') return false;
            } catch (_) {}
            return true;
          }).toList();

      // Sort by lastUpdated DESC
      filtered.sort((l, r) {
        final luL = _lastUpdated(l.data());
        final luR = _lastUpdated(r.data());
        return luR.compareTo(luL);
      });

      return filtered;
    });
  }

  // Extract UID from any /users/{uid}/subcollection/... document
  String _ownerUidOf(DocumentSnapshot<Map<String, dynamic>> d) {
    try {
      final parent = d.reference.parent;
      final usersDoc = parent.parent;
      if (usersDoc != null) return usersDoc.id;
    } catch (_) {}
    return '';
  }

  static DateTime _lastUpdated(Map<String, dynamic> m) {
    final ts = (m['updatedAt'] ?? m['createdAt']);
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // Accepts "#RRGGBB"/"#AARRGGBB" or int RGB; returns Color
  static Color _toColorStatic(dynamic v) {
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

  static dynamic _extractAnswers(Map<String, dynamic> m) =>
      (m['answersHex'] ?? m['answers'] ?? m['colors']);

  static String _formatDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  // Normalize hex like "#abc"/"abc" → "#AABBCC" (uppercased)
  static String _normHex(dynamic raw) {
    if (raw == null) return '';
    if (raw is int) {
      final c = _toColorStatic(raw);
      return '#${c.red.toRadixString(16).padLeft(2, '0').toUpperCase()}'
          '${c.green.toRadixString(16).padLeft(2, '0').toUpperCase()}'
          '${c.blue.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    }
    if (raw is String) {
      var s = raw.startsWith('#') ? raw.substring(1) : raw;
      s = s.trim();
      if (s.length == 3) {
        final r = s[0], g = s[1], b = s[2];
        return '#$r$r$g$g$b$b'.toUpperCase();
      }
      if (s.length >= 6) {
        return '#${s.substring(0, 6)}'.toUpperCase();
      }
    }
    return '';
  }

  /// Build per-question aggregates **and** the local hex→uids index.
  List<_QuestionAgg> _aggregateAndIndex(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    // Always render the full fingerprint questionnaire.
    final int qCount = kFingerprintTotal; // <- key fix: ignore short drafts

    final aggs = List<_QuestionAgg>.generate(qCount, (_) => _QuestionAgg());
    final index = List<Map<String, Set<String>>>.generate(
      qCount,
      (_) => <String, Set<String>>{},
    );

    for (final d in docs) {
      final m = d.data();
      final answers = _extractAnswers(m);
      final lu = _lastUpdated(m);
      final uid = _ownerUidOf(d);

      if (answers is List && uid.isNotEmpty) {
        for (int i = 0; i < answers.length && i < aggs.length; i++) {
          final hex = _normHex(answers[i]);
          if (hex.isEmpty) continue;

          // aggregate counts
          aggs[i].counts[hex] = (aggs[i].counts[hex] ?? 0) + 1;
          if (lu.isAfter(aggs[i].latest)) aggs[i].latest = lu;

          // index hex → uid set
          final bucket = index[i].putIfAbsent(hex, () => <String>{});
          bucket.add(uid);
        }
      }
    }

    _hexToUidsByQ = index; // store for taps
    return aggs;
  }

  // Helper: case-insensitive lookup in the index
  Set<String> _uidsFor(int questionIndex, String hex) {
    if (_hexToUidsByQ.isEmpty || questionIndex >= _hexToUidsByQ.length) {
      return const <String>{};
    }
    final map = _hexToUidsByQ[questionIndex];
    if (map.containsKey(hex)) return map[hex] ?? const <String>{};
    final key = map.keys.firstWhere(
      (k) => k.toUpperCase() == hex.toUpperCase(),
      orElse: () => '',
    );
    return key.isEmpty ? const <String>{} : (map[key] ?? const <String>{});
  }

  Future<void> _pickUserAndJump({
    required BuildContext context,
    required int questionIndex,
    required String hex, // "#RRGGBB"
  }) async {
    // breadcrumb
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Q${questionIndex + 1}: finding users for $hex…')),
    );

    final uids = _uidsFor(questionIndex, hex);
    if (uids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No matching users for that color at this question.'),
        ),
      );
      return;
    }

    // If exactly one match → jump straight. More than one → show chooser.
    if (uids.length == 1) {
      final uid = uids.first;
      final nav = Navigator.of(context, rootNavigator: true);
      nav.push(
        MaterialPageRoute(
          builder:
              (_) => AdminFingerprintsTab(
                db: widget.db,
                startUtc: null,
                endUtc: null,
                focusUid: uid,
              ),
        ),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Opening fingerprints for $uid…')));
      return;
    }

    await _presentUserSheet(context, uids, hex, questionIndex);
  }

  Future<void> _presentUserSheet(
    BuildContext context,
    Set<String> uids,
    String hex,
    int questionIndex,
  ) async {
    await _names.resolve(uids);

    // Show counts BEFORE the sheet (avoids builder/lifecycle races).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Found ${uids.length} user(s) at Q${questionIndex + 1} for $hex',
        ),
      ),
    );

    final nav = Navigator.of(context, rootNavigator: true);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final list =
            uids.toList()..sort(
              (a, b) => _names
                  .nameFor(a)
                  .toLowerCase()
                  .compareTo(_names.nameFor(b).toLowerCase()),
            );

        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final uid = list[i];
              final name = _names.nameFor(uid);
              return ListTile(
                leading: const Icon(Icons.person),
                title: Text(name.isEmpty ? uid : name),
                subtitle: Text(
                  uid,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                trailing: const Icon(Icons.open_in_new),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  nav.push(
                    MaterialPageRoute(
                      builder:
                          (_) => AdminFingerprintsTab(
                            db: widget.db,
                            startUtc: null,
                            endUtc: null,
                            focusUid: uid,
                          ),
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Opening fingerprints for $uid…')),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _fpStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Data error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!;
        final uids = <String>{for (final d in docs) _ownerUidOf(d)};
        _names.resolve(uids).then((_) {
          if (mounted) setState(() {});
        });

        // Build aggregates + local index from the same docs
        final qAggs = _aggregateAndIndex(docs);

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.5,
          ),
          itemCount: qAggs.length,
          itemBuilder: (_, i) {
            final qa = qAggs[i];
            final colors = qa.colorsByFreq();
            final latest = qa.latest;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x15000000)),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message:
                              (i < kFingerprintQs.length)
                                  ? kFingerprintQs[i]
                                  : 'Question ${i + 1}',
                          child: Text(
                            (i < kFingerprintQs.length)
                                ? 'Q${i + 1}: ${kFingerprintQs[i]}'
                                : 'Question ${i + 1}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const _StatusPill(text: 'All users'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${qa.responses} responses',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDate(latest),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Tappable swatches with outline feedback
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(colors.length, (idx) {
                      final hex = colors[idx];
                      final color = _toColorStatic(hex);
                      return _ColorSwatchButton(
                        color: color,
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Finding Q${i + 1} users for $hex…',
                              ),
                            ),
                          );
                          _pickUserAndJump(
                            context: context,
                            questionIndex: i,
                            hex: hex,
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x10666666),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x20666666)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A small square color button that always receives taps,
/// shows a focus/hover outline, and ripples on click (web friendly).
class _ColorSwatchButton extends StatefulWidget {
  const _ColorSwatchButton({required this.color, required this.onTap});
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ColorSwatchButton> createState() => _ColorSwatchButtonState();
}

class _ColorSwatchButtonState extends State<_ColorSwatchButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                width: _pressed ? 2 : (_hover ? 1.5 : 1),
                color:
                    _pressed
                        ? Colors.black87
                        : (_hover ? Colors.black54 : const Color(0x15000000)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
