import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:color_wallet/admin/admin_components.dart'
    show
        AdminNameCache,
        kAdminMuted,
        kAdminText,
        kAdminBorder,
        adminColorFromHex;
import 'package:color_wallet/fingerprint_questions.dart'; // <- for question texts

class AdminFingerprintsTab extends StatefulWidget {
  const AdminFingerprintsTab({
    super.key,
    required this.db,
    this.startUtc, // optional, ignored (all-time)
    this.endUtc, // optional, ignored (all-time)
    this.focusUid, // optional: bring this user to the front
  });

  final FirebaseFirestore db;
  final Timestamp? startUtc;
  final Timestamp? endUtc;
  final String? focusUid;

  @override
  State<AdminFingerprintsTab> createState() => _AdminFingerprintsTabState();
}

class _AdminFingerprintsTabState extends State<AdminFingerprintsTab> {
  // Page through ALL sent swatches and collect unique senders.
  static const int _kPageSize = 500;

  late Future<List<DocumentSnapshot<Map<String, dynamic>>>> _usersFut;
  late AdminNameCache _names;

  @override
  void initState() {
    super.initState();
    _names = AdminNameCache(widget.db);
    _usersFut = _loadActiveSenders();
  }

  @override
  void didUpdateWidget(covariant AdminFingerprintsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.db != widget.db || oldWidget.focusUid != widget.focusUid) {
      _names = AdminNameCache(widget.db);
      _usersFut = _loadActiveSenders();
      setState(() {});
    }
  }

  Future<List<DocumentSnapshot<Map<String, dynamic>>>>
  _loadActiveSenders() async {
    final base = widget.db
        .collectionGroup('userSwatches')
        .where('status', isEqualTo: 'sent')
        .where('sentAt', isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(0))
        .orderBy('sentAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);

    final seen = <String>{};
    final orderedIds = <String>[];

    Query<Map<String, dynamic>> q = base.limit(_kPageSize);

    while (true) {
      final qs = await q.get();
      if (qs.docs.isEmpty) break;

      for (final d in qs.docs) {
        final m = d.data();
        if ((m['status'] ?? 'draft') == 'sent') {
          final id = (m['senderId'] as String?) ?? '';
          if (id.isNotEmpty && seen.add(id)) {
            orderedIds.add(id);
          }
        }
      }

      if (qs.docs.length < _kPageSize) break;

      // Use BOTH fields for the cursor; documentId() value must be the FULL PATH STRING.
      final last = qs.docs.last;
      final lastData = last.data();
      final lastSentAt = lastData['sentAt'] as Timestamp?;
      if (lastSentAt == null) break;

      final lastPath = last.reference.path; // <-- full path string
      q = base.startAfter([lastSentAt, lastPath]).limit(_kPageSize);
    }

    final f = widget.focusUid;
    if (f != null && f.isNotEmpty) {
      orderedIds.removeWhere((e) => e == f);
      orderedIds.insert(0, f);
    }

    await _names.resolve(orderedIds.toSet());

    final futures = orderedIds.map(
      (id) => widget.db.collection('users').doc(id).get(),
    );
    return Future.wait(futures);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
      future: _usersFut,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Failed to load senders: ${snap.error}',
                style: const TextStyle(color: kAdminMuted),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = snap.data!.where((u) => u.exists).toList();
        if (users.isEmpty) {
          return const Center(
            child: Text(
              'No senders found.',
              style: TextStyle(color: kAdminMuted),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // NEW: super-simple engagement header
            _FpSlimHeader(db: widget.db),
            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Text(
                'Senders (${users.length})${widget.focusUid != null ? ' (focused on ${_names.nameFor(widget.focusUid!)} )' : ''}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: kAdminText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.2,
                ),
                itemCount: users.length,
                itemBuilder: (_, i) {
                  final u = users[i];
                  final m = u.data()!;
                  final uid = u.id;

                  final label = _names.nameFor(uid);
                  final email = (m['email'] ?? '') as String? ?? '';

                  return Card(
                    elevation: 0,
                    color: Colors.white,
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: kAdminBorder),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person, color: kAdminMuted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  label,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(color: kAdminText),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (email.isNotEmpty)
                                Text(
                                  email,
                                  style: const TextStyle(color: kAdminMuted),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _FingerprintGallery(db: widget.db, uid: uid),
                        ],
                      ),
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

// ----------------------------------------------------------------------------
// Per-user gallery: one mini-grid per submission + empty months between.
// ----------------------------------------------------------------------------

class _FpLoadResult {
  _FpLoadResult({
    required this.hexes,
    required this.isComplete,
    required this.source, // 'version' | 'draft' | 'missing'
    required this.lastUpdated,
    required this.monthId, // 'YYYY-MM'
    this.completedAt,
  });

  final List<String> hexes; // up to 36 (we display 25)
  final bool isComplete;
  final String source;
  final DateTime lastUpdated;
  final String monthId; // YYYY-MM
  final DateTime? completedAt;
}

class _FingerprintGallery extends StatelessWidget {
  const _FingerprintGallery({required this.db, required this.uid});
  final FirebaseFirestore db;
  final String uid;

  // ---- helpers ----
  String _toHexRgb(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = (argb) & 0xFF;
    String two(int v) => v.toRadixString(16).padLeft(2, '0');
    return '#${two(r)}${two(g)}${two(b)}'.toUpperCase();
  }

  List<String> _hexListFromAnswers(List<int> answers) =>
      answers.map(_toHexRgb).toList(growable: false);

  bool _markComplete(Map<String, dynamic> m, {required bool isVersion}) {
    if (isVersion) return true; // version docs are completed
    final completed = m['completed'] == true;
    final hasSeed = m['shuffleSeed'] is int; // finished via auto-shuffle
    final List a = (m['answers'] is List) ? (m['answers'] as List) : const [];
    final List hx =
        (m['answersHex'] is List) ? (m['answersHex'] as List) : const [];
    final inferred = a.length >= hx.length ? a.length : hx.length;
    final int total =
        (m['total'] is int && (m['total'] as int) > 0)
            ? m['total'] as int
            : inferred;
    final bool lenOk = total > 0 && (a.length >= total || hx.length >= total);
    return completed || hasSeed || lenOk;
  }

  DateTime _pickDate(List<dynamic> candidates) {
    for (final v in candidates) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _yyyyMm(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    if (dt.millisecondsSinceEpoch == 0) return '';
    return '${dt.year}-${two(dt.month)}';
  }

  String _monthOf(Map<String, dynamic> m, {required bool isVersion}) {
    final mid = (m['monthId'] is String) ? (m['monthId'] as String) : null;
    if (mid != null && mid.length >= 7) return mid.substring(0, 7);
    final dt = _pickDate(
      isVersion
          ? [m['createdAt'], m['completedAt'], m['updatedAt']]
          : [m['completedAt'], m['updatedAt'], m['createdAt']],
    );
    final s = _yyyyMm(dt);
    return s.isEmpty ? '---- --' : s;
  }

  Future<List<_FpLoadResult>> _loadAll() async {
    final out = <_FpLoadResult>[];

    DateTime? minMonth, maxMonth;

    // 1) NEW monthly docs: /fingerprints/{uid}/months/{YYYY-MM}
    final monthsSnap =
        await db
            .collection('fingerprints')
            .doc(uid)
            .collection('months')
            .orderBy('monthId', descending: false)
            .get();

    for (final d in monthsSnap.docs) {
      final m = d.data();

      // Extract colors: prefer explicit answers list, else numbered slots "0","1",...
      List<int> ints;
      if (m['answers'] is List) {
        ints = (m['answers'] as List).whereType<int>().toList(growable: false);
      } else {
        final int maxSlots;
        final totalField = m['total'];
        if (totalField is int && totalField > 0 && totalField <= 100) {
          maxSlots = totalField;
        } else {
          maxSlots = 36;
        }
        final tmp = <int>[];
        for (int i = 0; i < maxSlots; i++) {
          final v = m['$i'];
          if (v is int) {
            tmp.add(v);
          } else {
            break;
          }
        }
        ints = tmp;
      }

      if (ints.isEmpty) continue;

      final hexes = _hexListFromAnswers(ints);
      final capped = hexes.length > 36 ? hexes.sublist(0, 36) : hexes;

      final completedAt = _pickDate([
        m['completedAt'],
        m['updatedAt'],
        m['createdAt'],
      ]);
      final monthId = _monthOf(m, isVersion: true);
      final updated = _pickDate([m['updatedAt'], m['createdAt']]);

      out.add(
        _FpLoadResult(
          hexes: capped,
          isComplete: true,
          source: 'version',
          lastUpdated: updated,
          monthId: monthId,
          completedAt:
              completedAt.millisecondsSinceEpoch == 0 ? null : completedAt,
        ),
      );

      if (completedAt.millisecondsSinceEpoch != 0) {
        final firstOfMonth = DateTime(completedAt.year, completedAt.month, 1);
        minMonth ??= firstOfMonth;
        maxMonth ??= firstOfMonth;
        if (firstOfMonth.isBefore(minMonth)) minMonth = firstOfMonth;
        if (firstOfMonth.isAfter(maxMonth)) maxMonth = firstOfMonth;
      }
    }

    // 2) LEGACY completed versions: /users/{uid}/fingerprints/{doc}
    final legacyVersions =
        await db
            .collection('users')
            .doc(uid)
            .collection('fingerprints')
            .orderBy('createdAt', descending: false)
            .get();

    for (final d in legacyVersions.docs) {
      final m = d.data();
      final List<String>? hx =
          (m['answersHex'] is List)
              ? (m['answersHex'] as List).whereType<String>().toList()
              : null;
      final List<int> ints =
          (m['answers'] is List)
              ? (m['answers'] as List).whereType<int>().toList()
              : const <int>[];
      final hexes =
          (hx != null && hx.isNotEmpty) ? hx : _hexListFromAnswers(ints);
      final capped = hexes.length > 36 ? hexes.sublist(0, 36) : hexes;

      final completedAt = _pickDate([
        m['completedAt'],
        m['updatedAt'],
        m['createdAt'],
      ]);
      final monthId = _monthOf(m, isVersion: true);
      final updated = _pickDate([m['updatedAt'], m['createdAt']]);

      out.add(
        _FpLoadResult(
          hexes: capped,
          isComplete: true,
          source: 'version',
          lastUpdated: updated,
          monthId: monthId,
          completedAt:
              completedAt.millisecondsSinceEpoch == 0 ? null : completedAt,
        ),
      );

      if (completedAt.millisecondsSinceEpoch != 0) {
        final firstOfMonth = DateTime(completedAt.year, completedAt.month, 1);
        minMonth ??= firstOfMonth;
        maxMonth ??= firstOfMonth;
        if (firstOfMonth.isBefore(minMonth)) minMonth = firstOfMonth;
        if (firstOfMonth.isAfter(maxMonth)) maxMonth = firstOfMonth;
      }
    }

    // Current draft (if any) — unchanged.
    final draftDoc =
        await db
            .collection('users')
            .doc(uid)
            .collection('private')
            .doc('fingerprint')
            .get();

    if (draftDoc.exists) {
      final m = draftDoc.data() ?? <String, dynamic>{};
      final List<String> hx =
          (m['answersHex'] is List)
              ? (m['answersHex'] as List).whereType<String>().toList()
              : const <String>[];
      final List<int> ints =
          (m['answers'] is List)
              ? (m['answers'] as List).whereType<int>().toList()
              : const <int>[];
      final hexes = hx.isNotEmpty ? hx : _hexListFromAnswers(ints);
      final capped = hexes.length > 36 ? hexes.sublist(0, 36) : hexes;

      final updated = _pickDate([m['updatedAt'], m['createdAt']]);
      final monthId = _monthOf(m, isVersion: false);

      out.add(
        _FpLoadResult(
          hexes: capped,
          isComplete: _markComplete(m, isVersion: false),
          source: 'draft',
          lastUpdated: updated,
          monthId: monthId,
          completedAt:
              (m['completedAt'] is Timestamp)
                  ? (m['completedAt'] as Timestamp).toDate()
                  : null,
        ),
      );

      if (updated.millisecondsSinceEpoch != 0) {
        final firstOfMonth = DateTime(updated.year, updated.month, 1);
        minMonth ??= firstOfMonth;
        maxMonth ??= firstOfMonth;
        if (firstOfMonth.isBefore(minMonth)) minMonth = firstOfMonth;
        if (firstOfMonth.isAfter(maxMonth)) maxMonth = firstOfMonth;
      }
    }

    // Insert missing month placeholders between min and max.
    if (minMonth != null && maxMonth != null) {
      final existing = out.map((e) => e.monthId).toSet();
      DateTime cursor = DateTime(minMonth.year, minMonth.month, 1);
      final end = DateTime(maxMonth.year, maxMonth.month, 1);

      while (!cursor.isAfter(end)) {
        final mid = '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}';
        if (!existing.contains(mid)) {
          out.add(
            _FpLoadResult(
              hexes: const <String>[],
              isComplete: false,
              source: 'missing',
              lastUpdated: cursor,
              monthId: mid,
              completedAt: null,
            ),
          );
        }
        cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }
    }

    // --- Merge draft + version in the SAME month (unchanged) ---
    final Map<String, Map<String, int>> byMonthIdx =
        {}; // monthId -> {'draft': idx, 'version': idx}
    for (int i = 0; i < out.length; i++) {
      final it = out[i];
      if (it.source == 'missing') continue;
      if (it.source != 'draft' && it.source != 'version') continue;

      final m = byMonthIdx.putIfAbsent(it.monthId, () => <String, int>{});
      final existingIdx = m[it.source];
      if (existingIdx == null) {
        m[it.source] = i;
      } else {
        if (out[i].lastUpdated.isAfter(out[existingIdx].lastUpdated)) {
          m[it.source] = i;
        }
      }
    }

    final toDrop = <_FpLoadResult>{};
    byMonthIdx.forEach((monthId, m) {
      final di = m['draft'];
      final vi = m['version'];
      if (di != null && vi != null) {
        final d = out[di];
        final v = out[vi];
        final dts = d.lastUpdated;
        final vts = v.lastUpdated;

        final dropIdx =
            vts.isAtSameMomentAs(dts) ? di : (vts.isAfter(dts) ? di : vi);
        toDrop.add(out[dropIdx]);
      }
    });

    if (toDrop.isNotEmpty) {
      out.removeWhere((e) => toDrop.contains(e));
    }

    // Sort month ASC; within month show completed before draft, then recency
    out.sort((a, b) {
      final c = a.monthId.compareTo(b.monthId);
      if (c != 0) return c;
      if (a.source == 'missing' && b.source != 'missing') return 1;
      if (b.source == 'missing' && a.source != 'missing') return -1;
      if (a.isComplete != b.isComplete) return a.isComplete ? -1 : 1;
      return a.lastUpdated.compareTo(b.lastUpdated);
    });

    return out;
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null || dt.millisecondsSinceEpoch == 0) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_FpLoadResult>>(
      future: _loadAll(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Text(
            'Failed to load fingerprints.',
            style: TextStyle(color: kAdminMuted),
          );
        }
        if (!snap.hasData) {
          return const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return const Text(
            'No fingerprints yet.',
            style: TextStyle(color: kAdminMuted),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [for (final it in items) _MiniFingerprintCard(item: it)],
          ),
        );
      },
    );
  }
}

class _MiniFingerprintCard extends StatelessWidget {
  const _MiniFingerprintCard({required this.item});
  final _FpLoadResult item;

  @override
  Widget build(BuildContext context) {
    final hexes =
        item.hexes.length >= 25
            ? item.hexes.sublist(0, 25)
            : List<String>.from(item.hexes);

    const int cols = 5;
    const int total = 25;
    const light = Color(0xFFEDEDEF);
    const dark = Color(0xFFDCDDE2);

    final bool isMissing = item.source == 'missing';
    final bool hasAnyColor = item.hexes.isNotEmpty;

    final card = Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: kAdminBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [_Pill(text: item.monthId, tone: _PillTone.neutral)]),
          const SizedBox(height: 6),
          if (!isMissing)
            Text(
              item.source == 'version'
                  ? 'Completed: ${_fmtDate(item.completedAt)}'
                  : 'Updated: ${_fmtDate(item.lastUpdated)}',
              style: const TextStyle(fontSize: 11, color: kAdminMuted),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            height: 120,
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 0,
                crossAxisSpacing: 0,
                childAspectRatio: 1.0,
              ),
              itemCount: total,
              itemBuilder: (_, i) {
                if (!isMissing && i < hexes.length) {
                  return Container(color: adminColorFromHex(hexes[i]));
                }
                final row = i ~/ cols, col = i % cols;
                final bg = ((row + col) & 1) == 0 ? light : dark;
                return Container(color: bg);
              },
            ),
          ),
        ],
      ),
    );

    if (isMissing || !hasAnyColor) {
      return card;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showDetailsDialog(context),
      child: card,
    );
  }

  void _showDetailsDialog(BuildContext context) {
    const int maxQuestions = 25;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('${item.monthId} fingerprint'),
          content: SizedBox(
            width: 480,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: maxQuestions,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (_, i) {
                final questionText =
                    (i < kFingerprintQs.length)
                        ? kFingerprintQs[i]
                        : 'Question ${i + 1}';
                final hasHex =
                    i < item.hexes.length && item.hexes[i].trim().isNotEmpty;
                final hex = hasHex ? item.hexes[i].toUpperCase() : '—';
                final color =
                    hasHex
                        ? adminColorFromHex(item.hexes[i])
                        : const Color(0xFFE0E0E0);

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${i + 1}.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        questionText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: kAdminBorder),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hex,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final lines = <String>[];
                for (var i = 0; i < item.hexes.length; i++) {
                  final raw = item.hexes[i].trim();
                  final hex = raw.isEmpty ? '—' : raw.toUpperCase();
                  lines.add('${i + 1}. $hex');
                }

                await Clipboard.setData(ClipboardData(text: lines.join('\n')));

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Hex codes copied')),
                );
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy hex codes'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null || dt.millisecondsSinceEpoch == 0) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }
}

// ----------------------------------------------------------------------------
// Pills
// ----------------------------------------------------------------------------

enum _PillTone { good, neutral, muted }

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.tone});
  final String text;
  final _PillTone tone;

  Color get _bg {
    switch (tone) {
      case _PillTone.good:
        return const Color(0x1066BB66);
      case _PillTone.neutral:
        return const Color(0x10666666);
      case _PillTone.muted:
        return const Color(0x0F000000);
    }
  }

  Color get _border {
    switch (tone) {
      case _PillTone.good:
        return const Color(0x2066BB66);
      case _PillTone.neutral:
        return const Color(0x20666666);
      case _PillTone.muted:
        return const Color(0x15000000);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _border),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// SLIM header: latest-month engagement (super simple)
// ----------------------------------------------------------------------------

class _FpSlimHeader extends StatefulWidget {
  const _FpSlimHeader({required this.db});
  final FirebaseFirestore db;

  @override
  State<_FpSlimHeader> createState() => _FpSlimHeaderState();
}

class _FpSlimHeaderState extends State<_FpSlimHeader> {
  bool _loading = true;

  String _month = '—';
  int _activeUsers = 0;
  int _submissions = 0; // drafts + versions
  int _completed = 0; // versions only

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _yyyyMm(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    if (dt.millisecondsSinceEpoch == 0) return '';
    return '${dt.year}-${two(dt.month)}';
  }

  DateTime _pickDate(List<dynamic> cands) {
    for (final v in cands) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      // Pull all versions (completed) and the current drafts snapshot.
      // NOTE: still using collectionGroup('fingerprints') here so legacy data
      // continues to power the header; monthly docs are handled per-user above.
      final versionsFut = widget.db.collectionGroup('fingerprints').get();
      final privatesFut = widget.db.collectionGroup('private').get();

      final versions = await versionsFut;
      final privates = await privatesFut;

      final Map<String, Set<String>> activeByMonth = {};
      final Map<String, int> subsByMonth = {};
      final Map<String, int> completedByMonth = {};

      // Versions = completed submissions
      for (final d in versions.docs) {
        final m = d.data();
        final parent = d.reference.parent; // /users/{uid}/fingerprints
        final userDoc = parent.parent;
        final uid = userDoc?.id ?? '';
        if (uid.isEmpty) continue;

        final monthId =
            (m['monthId'] is String && (m['monthId'] as String).length >= 7)
                ? (m['monthId'] as String).substring(0, 7)
                : _yyyyMm(
                  _pickDate([m['completedAt'], m['createdAt'], m['updatedAt']]),
                );
        if (monthId.isEmpty) continue;

        activeByMonth.putIfAbsent(monthId, () => <String>{}).add(uid);
        subsByMonth[monthId] = (subsByMonth[monthId] ?? 0) + 1;
        completedByMonth[monthId] = (completedByMonth[monthId] ?? 0) + 1;
      }

      // Drafts = possible submissions
      for (final d in privates.docs) {
        if (d.id != 'fingerprint') continue; // keep only the draft doc
        final parent = d.reference.parent; // /users/{uid}/private
        final userDoc = parent.parent;
        final uid = userDoc?.id ?? '';
        if (uid.isEmpty) continue;

        final m = d.data() as Map<String, dynamic>? ?? const {};
        final monthId =
            (m['monthId'] is String && (m['monthId'] as String).length >= 7)
                ? (m['monthId'] as String).substring(0, 7)
                : _yyyyMm(_pickDate([m['updatedAt'], m['createdAt']]));
        if (monthId.isEmpty) continue;

        activeByMonth.putIfAbsent(monthId, () => <String>{}).add(uid);
        subsByMonth[monthId] = (subsByMonth[monthId] ?? 0) + 1;
        // not completed
      }

      if (activeByMonth.isEmpty && subsByMonth.isEmpty) {
        setState(() {
          _month = '—';
          _activeUsers = 0;
          _submissions = 0;
          _completed = 0;
          _loading = false;
        });
        return;
      }

      final months =
          <String>{...activeByMonth.keys, ...subsByMonth.keys}.toList()..sort();
      final latest = months.last;

      setState(() {
        _month = latest;
        _activeUsers = activeByMonth[latest]?.length ?? 0;
        _submissions = subsByMonth[latest] ?? 0;
        _completed = completedByMonth[latest] ?? 0;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _month = '—';
        _activeUsers = 0;
        _submissions = 0;
        _completed = 0;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 90,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final double completionPct =
        (_submissions <= 0) ? 0.0 : _completed / _submissions;

    return Card(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kAdminBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _TinyKpi(label: 'Month', value: _month),
            _TinyKpi(label: 'Active users', value: '$_activeUsers'),
            _TinyKpi(label: 'Submissions', value: '$_submissions'),
            _TinyKpi(
              label: 'Completed',
              value: '${(completionPct * 100).round()}%',
              hint: 'Versions ÷ (versions + drafts)',
            ),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(foregroundColor: kAdminText),
            ),
          ],
        ),
      ),
    );
  }
}

class _TinyKpi extends StatelessWidget {
  const _TinyKpi({required this.label, required this.value, this.hint});
  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: kAdminBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: kAdminMuted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: kAdminText,
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                hint!,
                style: const TextStyle(fontSize: 10, color: kAdminMuted),
              ),
            ),
        ],
      ),
    );
  }
}
