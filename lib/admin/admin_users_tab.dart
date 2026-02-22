import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:color_wallet/admin/admin_components.dart'; // tokens+helpers
import 'package:intl/intl.dart';

class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({
    super.key,
    required this.db,
    required this.start,
    required this.end,
    required this.maxDocsForStats,
  });

  final FirebaseFirestore db;
  final Timestamp start;
  final Timestamp end;
  final int maxDocsForStats;

  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

// Added Last-login sort option; default remains joinedDesc.
enum _SortMode { joinedDesc, lastLoginDesc, alphaAsc }

class _AdminUsersTabState extends State<AdminUsersTab> {
  // We’ll just fetch everything once (you have ~50 users).
  static const int _fetchLimit = 2000;

  final TextEditingController _searchCtl = TextEditingController();

  bool _loadingAll = false;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _allUsers = [];

  _SortMode _sort = _SortMode.joinedDesc; // default per spec

  // --- Expansion + fingerprint lazy cache ------------------------------------
  final Set<String> _expanded = <String>{}; // which rows are open
  final Map<String, _FpInfo> _fpInfo = <String, _FpInfo>{}; // uid -> fp info
  final Map<String, Future<void>> _fpLoads =
      <String, Future<void>>{}; // inflight
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadAllUsers(); // single upfront fetch
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  // Normalize to lowercase, trimmed
  String _lc(Object? v) => (v ?? '').toString().trim().toLowerCase();

  // Case-insensitive substring match against multiple fields incl. UID
  bool _matchesUser(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
    String qRaw,
  ) {
    final q = _lc(qRaw);
    if (q.isEmpty) return true;

    final m = d.data();
    final id = _lc(d.id);
    final dn = _lc(m['displayName']);
    final un = _lc(m['username']);
    final em = _lc(m['email']);
    return id.contains(q) || dn.contains(q) || un.contains(q) || em.contains(q);
  }

  // Compute "joinedAt" from best available field (no schema change).
  // Priority: createdAt > migratedAt > passwordChangedAt > lastActive > Epoch(0)
  DateTime _joinedAt(Map<String, dynamic> m) {
    Timestamp? ts =
        (m['createdAt'] as Timestamp?) ??
        (m['migratedAt'] as Timestamp?) ??
        (m['passwordChangedAt'] as Timestamp?) ??
        (m['lastActive'] as Timestamp?);
    return (ts ?? Timestamp.fromMillisecondsSinceEpoch(0)).toDate();
  }

  // Last login time from lastActive (fallback none)
  DateTime? _lastLogin(Map<String, dynamic> m) {
    final ts = m['lastActive'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }

  Future<void> _loadAllUsers() async {
    if (_loadingAll) return;
    setState(() => _loadingAll = true);

    _allUsers.clear();
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    bool hasMore = true;

    while (hasMore && _allUsers.length < _fetchLimit) {
      Query<Map<String, dynamic>> q = widget.db
          .collection('users')
          // stable deterministic order to page deterministically
          .orderBy('displayName')
          .orderBy(FieldPath.documentId)
          .limit(200);

      if (cursor != null) q = q.startAfterDocument(cursor);

      final snap = await q.get();
      if (snap.docs.isNotEmpty) {
        _allUsers.addAll(snap.docs);
        cursor = snap.docs.last;
      }
      if (snap.docs.length < 200) hasMore = false;
    }

    if (mounted) setState(() => _loadingAll = false);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applySearchSortFilter() {
    // search
    var list =
        _allUsers.where((d) => _matchesUser(d, _searchCtl.text)).toList();

    // sort
    list.sort((a, b) {
      final aData = a.data();
      final bData = b.data();

      if (_sort == _SortMode.alphaAsc) {
        final an = ((aData['displayName'] as String?) ?? a.id).toLowerCase();
        final bn = ((bData['displayName'] as String?) ?? b.id).toLowerCase();
        final c = an.compareTo(bn);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      }

      if (_sort == _SortMode.lastLoginDesc) {
        // newest lastActive first; nulls at the end
        final aj = _lastLogin(aData) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bj = _lastLogin(bData) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final c = bj.compareTo(aj);
        if (c != 0) return c;
        // tie-breakers: joinedAt desc, then name, then id
        final ajoin = _joinedAt(aData);
        final bjoin = _joinedAt(bData);
        final c2 = bjoin.compareTo(ajoin);
        if (c2 != 0) return c2;
        final an = ((aData['displayName'] as String?) ?? a.id).toLowerCase();
        final bn = ((bData['displayName'] as String?) ?? b.id).toLowerCase();
        final c3 = an.compareTo(bn);
        if (c3 != 0) return c3;
        return a.id.compareTo(b.id);
      }

      // default: joinedDesc (newest first)
      final aj = _joinedAt(aData);
      final bj = _joinedAt(bData);
      final c = bj.compareTo(aj);
      if (c != 0) return c;
      // tie-breakers: name, then id
      final an = ((aData['displayName'] as String?) ?? a.id).toLowerCase();
      final bn = ((bData['displayName'] as String?) ?? b.id).toLowerCase();
      final c2 = an.compareTo(bn);
      if (c2 != 0) return c2;
      return a.id.compareTo(b.id);
    });

    return list;
  }

  String _fmtDate(DateTime dt) {
    // Example: "Jan 31, 2025 3:22 pm"
    final s = DateFormat('MMM d, y h:mma').format(dt);
    return s.replaceAll('AM', 'am').replaceAll('PM', 'pm');
  }

  // Better local-time label if offset info exists in document
  String _niceSentTime(Map<String, dynamic> m, DateTime sentAtUtc) {
    final keys = <String>[
      'senderTzOffsetMin',
      'senderTzOffsetMinutes',
      'tzOffsetMin',
      'tzOffsetMinutes',
      'senderUtcOffsetMin',
    ];
    int? off;
    for (final k in keys) {
      final v = m[k];
      if (v is int) {
        off = v;
        break;
      }
      if (v is num) {
        off = v.toInt();
        break;
      }
    }
    final dt = off != null ? sentAtUtc.add(Duration(minutes: off)) : sentAtUtc;
    return _fmtDate(dt);
  }

  // --- Fingerprint loader ----------------------------------------------------
  Future<void> _ensureFingerprintStatus(String uid) {
    if (_fpInfo.containsKey(uid)) return Future.value();
    if (_fpLoads[uid] != null) return _fpLoads[uid]!;

    int inferAnswered(Map<String, dynamic> m) {
      int? c;

      // common integer fields
      for (final key in const [
        'answersCount',
        'answered',
        'completedCount',
        'tilesCompleted',
        'count',
      ]) {
        final v = m[key];
        if (v is int) {
          c = v;
          break;
        }
        if (v is num) {
          c = v.toInt();
          break;
        }
      }

      // arrays / maps
      if (c == null) {
        final a = m['answers'];
        if (a is List) c = a.length;
        if (a is Map) c = a.length;
      }
      if (c == null) {
        final hx = m['answersHex'];
        if (hx is List) c = hx.length;
      }
      if (c == null) {
        final t = m['tiles'];
        if (t is List) c = t.length;
        if (t is Map) c = t.length;
      }

      return (c ?? 0).clamp(0, 25);
    }

    Future<_FpInfo> load() async {
      // 1) Latest version: /users/{uid}/fingerprints (ordered by createdAt desc)
      try {
        final ver =
            await widget.db
                .collection('users')
                .doc(uid)
                .collection('fingerprints')
                .orderBy('createdAt', descending: true)
                .limit(1)
                .get();
        if (ver.docs.isNotEmpty) {
          final m = ver.docs.first.data();
          final answered = inferAnswered(m);
          return _FpInfo(exists: true, answered: answered, completed: true);
        }
      } catch (_) {
        // ignore and try draft
      }

      // 2) Draft: /users/{uid}/private/fingerprint
      try {
        final d =
            await widget.db
                .collection('users')
                .doc(uid)
                .collection('private')
                .doc('fingerprint')
                .get();
        if (d.exists) {
          final m = d.data() ?? const <String, dynamic>{};
          final answered = inferAnswered(m);
          final completed = (m['completed'] == true) || answered >= 25;
          return _FpInfo(
            exists: true,
            answered: answered,
            completed: completed,
          );
        }
      } catch (_) {
        // ignore
      }

      // 3) Fallback: no info
      return const _FpInfo.none();
    }

    final fut = () async {
      _FpInfo info;
      try {
        info = await load();
      } catch (_) {
        info = const _FpInfo.unknown();
      }
      _fpInfo[uid] = info;
      _fpLoads.remove(uid);
      if (mounted) setState(() {});
    }();

    _fpLoads[uid] = fut;
    return fut;
  }
  // ---------------------------------------------------------------------------

  // Unified toggle that first clears keyboard focus, then expands/collapses.
  void _toggleRow(String uid) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (_expanded.contains(uid)) {
        _expanded.remove(uid);
      } else {
        _expanded.add(uid);
        _ensureFingerprintStatus(uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _applySearchSortFilter();

    return Column(
      children: [
        // Header row: title + actions
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Text(
                'Users Overview',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: kAdminText,
                ),
              ),
              const Spacer(),
              if (_loadingAll)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Text(
                    'Loading users…',
                    style: TextStyle(color: kAdminMuted),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _copyAllEmails,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kAdminText,
                  side: const BorderSide(color: kAdminBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                icon: const Icon(Icons.content_copy),
                label: const Text('Copy ALL emails'),
              ),
            ],
          ),
        ),

        // Filters row: single Search + unified Sort dropdown
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtl,
                  decoration: InputDecoration(
                    hintText: 'Search name / username / email / uid',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, color: kAdminMuted),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: kAdminBorder),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: kAdminBorder),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: kAdminBorder),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButton<_SortMode>(
                      value: _sort,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _sort = v);
                      },
                      items: const [
                        DropdownMenuItem(
                          value: _SortMode.joinedDesc,
                          child: Text('Sort: Joined (newest)'),
                        ),
                        DropdownMenuItem(
                          value: _SortMode.lastLoginDesc,
                          child: Text('Sort: Last login (newest)'),
                        ),
                        DropdownMenuItem(
                          value: _SortMode.alphaAsc,
                          child: Text('Sort: Alphabetical (A–Z)'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 0,
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: kAdminBorder),
              ),
              child:
                  (_allUsers.isEmpty && _loadingAll)
                      ? const Center(child: CircularProgressIndicator())
                      : (filtered.isEmpty
                          ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'No users match your search/filters.',
                                style: TextStyle(color: kAdminMuted),
                              ),
                            ),
                          )
                          : ListView.separated(
                            // add right padding so trailing chips never touch the edge
                            padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                            itemCount: filtered.length,
                            separatorBuilder:
                                (_, __) => const Divider(
                                  height: 1,
                                  color: kAdminDivider,
                                ),
                            itemBuilder: (context, i) {
                              final u = filtered[i];
                              final uid = u.id;
                              final data = u.data();
                              final displayName =
                                  (data['displayName'] ?? '') as String? ?? '';
                              final email =
                                  (data['email'] ?? '') as String? ?? '';

                              final joinedAt = _joinedAt(data);
                              final lastLogin = _lastLogin(data);
                              final isExpanded = _expanded.contains(uid);

                              return FutureBuilder<_UserRowStats>(
                                future: _computeUserStats(uid),
                                builder: (context, snap) {
                                  final waiting =
                                      snap.connectionState ==
                                      ConnectionState.waiting;
                                  final stats = snap.data;

                                  // Preload FP status so the chip resolves even when collapsed.
                                  _ensureFingerprintStatus(uid);
                                  final fp = _fpInfo[uid];

                                  final chips = <Widget>[
                                    _Tag(
                                      waiting
                                          ? '… sent'
                                          : '${stats?.sent ?? 0} sent',
                                    ),
                                    _Tag(
                                      waiting
                                          ? '… received'
                                          : '${stats?.received ?? 0} received',
                                    ),
                                    _Tag(
                                      waiting
                                          ? '… keep'
                                          : '${_pct(stats?.kept ?? 0, stats?.sent ?? 0)} keep',
                                    ),
                                    _Tag(
                                      fp == null
                                          ? 'FP …'
                                          : fp.completed
                                          ? 'FP ✓ ${fp.answered}/25'
                                          : (fp.exists
                                              ? 'FP ${fp.answered}/25'
                                              : 'FP —'),
                                    ),
                                  ];

                                  final header = _UserHeaderRow(
                                    onTap: () => _toggleRow(uid),
                                    leading: const Icon(
                                      Icons.person,
                                      color: kAdminMuted,
                                    ),
                                    titleText:
                                        displayName.isEmpty ? uid : displayName,
                                    subtitleText: [
                                      if (email.isNotEmpty) email,
                                      'UID: $uid',
                                      'Joined ${_fmtDate(joinedAt)}',
                                      if (lastLogin != null)
                                        'Last login ${_fmtDate(lastLogin)}',
                                    ].join(' • '),
                                    chips: chips,
                                  );

                                  // Inline expanded panel
                                  final expandedPanel = Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.fromLTRB(
                                      44, // aligns under avatar
                                      0,
                                      16,
                                      12,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF9FAFB),
                                      border: Border.all(color: kAdminBorder),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 8,
                                          children: [
                                            AdminKpiCard(
                                              label: 'Sent',
                                              value:
                                                  waiting
                                                      ? '…'
                                                      : '${stats?.sent ?? 0}',
                                            ),
                                            AdminKpiCard(
                                              label: 'Received',
                                              value:
                                                  waiting
                                                      ? '…'
                                                      : '${stats?.received ?? 0}',
                                            ),
                                            AdminKpiCard(
                                              label: 'Keep',
                                              value:
                                                  waiting
                                                      ? '…'
                                                      : _pct(
                                                        stats?.kept ?? 0,
                                                        stats?.sent ?? 0,
                                                      ),
                                            ),
                                            AdminKpiCard(
                                              label: 'FP answers',
                                              value:
                                                  (fp == null)
                                                      ? '…'
                                                      : '${fp.answered}/25',
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),

                                        _SwatchSection(
                                          db: widget.db,
                                          uid: uid,
                                          title: 'Sent',
                                          role: _Role.sender,
                                          keptOnly: false,
                                          niceTime: _niceSentTime,
                                        ),
                                        const SizedBox(height: 8),

                                        _SwatchSection(
                                          db: widget.db,
                                          uid: uid,
                                          title: 'Received',
                                          role: _Role.recipient,
                                          keptOnly: false,
                                          niceTime: _niceSentTime,
                                        ),
                                        const SizedBox(height: 8),

                                        _SwatchSection(
                                          db: widget.db,
                                          uid: uid,
                                          title: 'Kept (of sent)',
                                          role: _Role.sender,
                                          keptOnly: true,
                                          niceTime: _niceSentTime,
                                        ),
                                        const SizedBox(height: 12),

                                        const Text(
                                          'Fingerprint colors',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: kAdminText,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        UserFingerprintGrid25(
                                          db: widget.db,
                                          uid: uid,
                                        ),
                                      ],
                                    ),
                                  );

                                  return Column(
                                    children: [
                                      header,
                                      AnimatedCrossFade(
                                        firstChild: const SizedBox.shrink(),
                                        secondChild: expandedPanel,
                                        crossFadeState:
                                            isExpanded
                                                ? CrossFadeState.showSecond
                                                : CrossFadeState.showFirst,
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          )),
            ),
          ),
        ),

        // Tiny refresh button
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextButton.icon(
            onPressed: _loadingAll ? null : _loadAllUsers,
            icon: const Icon(Icons.refresh),
            label: const Text('Reload users'),
            style: TextButton.styleFrom(foregroundColor: kAdminText),
          ),
        ),
      ],
    );
  }

  Future<_UserRowStats> _computeUserStats(String uid) async {
    final sentQ = widget.db
        .collectionGroup('userSwatches')
        .where('senderId', isEqualTo: uid)
        .where('status', isEqualTo: 'sent');

    final keptQ = widget.db
        .collectionGroup('userSwatches')
        .where('senderId', isEqualTo: uid)
        .where('status', isEqualTo: 'sent')
        .where('kept', isEqualTo: true);

    final recvQ = widget.db
        .collectionGroup('userSwatches')
        .where('recipientId', isEqualTo: uid)
        .where('status', isEqualTo: 'sent');

    final sentAgg = await sentQ.count().get();
    final keptAgg = await keptQ.count().get();
    final recvAgg = await recvQ.count().get();

    return _UserRowStats(
      sent: sentAgg.count ?? 0,
      kept: keptAgg.count ?? 0,
      received: recvAgg.count ?? 0,
    );
  }

  static String _pct(int part, int total) {
    if (total <= 0) return '0%';
    return '${((part / total) * 100).round()}%';
  }

  /// Copy ALL user emails (ignores activity/time range).
  Future<void> _copyAllEmails() async {
    // Prefer already-loaded list; if empty, fetch once.
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users = _allUsers;
    if (users.isEmpty && !_loadingAll) {
      final snap = await widget.db.collection('users').get();
      users = snap.docs;
    }

    final emails = <String>{};
    for (final d in users) {
      final e = (d.data()['email'] as String?)?.trim() ?? '';
      if (e.isNotEmpty) emails.add(e);
    }

    if (emails.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No emails found.')));
      }
      return;
    }

    final list =
        emails.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final joined = list.join(', ');

    await adminCopyToClipboard(
      context,
      joined,
      successMessage: 'Copied ${list.length} emails.',
    );
  }
}

class _UserRowStats {
  final int sent;
  final int kept;
  final int received;
  _UserRowStats({
    required this.sent,
    required this.kept,
    required this.received,
  });
}

class _FpInfo {
  final bool exists;
  final int answered; // 0..25
  final bool completed;
  const _FpInfo({
    required this.exists,
    required this.answered,
    required this.completed,
  });

  const _FpInfo.none() : exists = false, answered = 0, completed = false;

  const _FpInfo.unknown()
    : exists = true, // treat as exists but unknown progress
      answered = 0,
      completed = false;
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      // tiny bump so “FP —” never kisses the border
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: kAdminChipBg,
        border: Border.all(color: kAdminBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: kAdminText),
      ),
    );
  }
}

// ---------------- Manual row to avoid ListTile.trailing tight constraints.
class _UserHeaderRow extends StatelessWidget {
  const _UserHeaderRow({
    required this.onTap,
    required this.leading,
    required this.titleText,
    required this.subtitleText,
    required this.chips,
  });

  final VoidCallback onTap;
  final Widget leading;
  final String titleText;
  final String subtitleText;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 20, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 12),

            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: kAdminText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    subtitleText,
                    maxLines: 2,
                    style: const TextStyle(
                      color: kAdminMuted,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Chips lane: take remaining width; cap max width; reserve two-row height.
            Flexible(
              fit: FlexFit.loose,
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: 64,
                    maxWidth:
                        MediaQuery.of(context).size.width <= 1100 ? 340 : 420,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: chips,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact section widget that shows a short list of swatches with color, title,
/// counterparty name (To/From), and sent time.
enum _Role { sender, recipient }

class _SwatchSection extends StatelessWidget {
  const _SwatchSection({
    required this.db,
    required this.uid,
    required this.title,
    required this.role,
    required this.keptOnly,
    required this.niceTime,
  });

  final FirebaseFirestore db;
  final String uid;
  final String title;
  final _Role role; // sender or recipient
  final bool keptOnly; // only for role == sender
  final String Function(Map<String, dynamic>, DateTime) niceTime;

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _query() async {
    Query<Map<String, dynamic>> q = db
        .collectionGroup('userSwatches')
        .where('status', isEqualTo: 'sent');

    if (role == _Role.sender) {
      q = q.where('senderId', isEqualTo: uid);
      if (keptOnly) q = q.where('kept', isEqualTo: true);
    } else {
      q = q.where('recipientId', isEqualTo: uid);
    }

    q = q.orderBy('sentAt', descending: true).limit(10);
    final snap = await q.get();
    return snap.docs;
  }

  Future<List<_SwatchView>> _loadViews() async {
    final docs = await _query();
    final cache = AdminNameCache(db);

    // Gather counterpart ids
    final ids = <String>{};
    for (final d in docs) {
      final m = d.data();
      final sid = (m['senderId'] as String?) ?? '';
      final rid = (m['recipientId'] as String?) ?? '';
      if (role == _Role.sender) {
        if (rid.isNotEmpty) ids.add(rid);
      } else {
        if (sid.isNotEmpty) ids.add(sid);
      }
    }
    if (ids.isNotEmpty) await cache.resolve(ids);

    final out = <_SwatchView>[];
    for (final d in docs) {
      final m = d.data();
      final hex = (m['colorHex'] as String?) ?? '';
      final title =
          (m['title'] as String?) ?? (m['swatchTitle'] as String?) ?? '';
      final sentAt = (m['sentAt'] as Timestamp?)?.toDate();
      final sid = (m['senderId'] as String?) ?? '';
      final rid = (m['recipientId'] as String?) ?? '';
      final counterpartId = role == _Role.sender ? rid : sid;
      final counterpart =
          counterpartId.isEmpty
              ? ''
              : (cache.nameFor(counterpartId).isNotEmpty
                  ? cache.nameFor(counterpartId)
                  : counterpartId);
      out.add(
        _SwatchView(
          hex: hex,
          title: title,
          counterpartLabel:
              role == _Role.sender ? 'To $counterpart' : 'From $counterpart',
          timeLabel: sentAt == null ? '' : niceTime(m, sentAt.toUtc()),
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_SwatchView>>(
      future: _loadViews(),
      builder: (context, snap) {
        final views = snap.data ?? const <_SwatchView>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: kAdminText,
              ),
            ),
            const SizedBox(height: 6),
            if (!snap.hasData)
              const SizedBox(
                height: 40,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (views.isEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 2, bottom: 4),
                child: Text('No items.', style: TextStyle(color: kAdminMuted)),
              )
            else
              ListView.separated(
                itemCount: views.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                separatorBuilder:
                    (_, __) => const Divider(height: 1, color: kAdminDivider),
                itemBuilder: (_, i) {
                  final v = views[i];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    leading: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color:
                            v.hex.isEmpty
                                ? Colors.white
                                : adminColorFromHex(v.hex),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                    title: Text(
                      v.title.isEmpty ? '(untitled)' : v.title,
                      style: const TextStyle(color: kAdminText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        v.counterpartLabel,
                        v.timeLabel,
                      ].where((s) => s.isNotEmpty).join(' • '),
                      style: const TextStyle(color: kAdminMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _SwatchView {
  final String hex;
  final String title;
  final String counterpartLabel;
  final String timeLabel;
  _SwatchView({
    required this.hex,
    required this.title,
    required this.counterpartLabel,
    required this.timeLabel,
  });
}

// --------------------------- Bottom sheets & auxiliary -----------------------

class AdminUserQuickViewSheet extends StatelessWidget {
  const AdminUserQuickViewSheet({
    super.key,
    required this.uid,
    required this.userDoc,
    required this.start,
    required this.end,
    required this.db,
  });

  final String uid;
  final DocumentSnapshot<Map<String, dynamic>>? userDoc;
  final Timestamp start;
  final Timestamp end;
  final FirebaseFirestore db;

  @override
  Widget build(BuildContext context) {
    final displayName = userDoc?.data()?['displayName'] as String? ?? '';
    final email = userDoc?.data()?['email'] as String? ?? '';

    return DraggableScrollableSheet(
      expand: false,
      builder: (context, controller) {
        return Material(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              controller: controller,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, color: kAdminMuted),
                    const SizedBox(width: 8),
                    Text(
                      displayName.isEmpty ? uid : displayName,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: kAdminText),
                    ),
                    const Spacer(),
                    Text(email, style: const TextStyle(color: kAdminMuted)),
                  ],
                ),
                const SizedBox(height: 12),
                FutureBuilder<_UserRowStats>(
                  future: _userStats(uid),
                  builder: (context, snap) {
                    final s = snap.data;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        AdminKpiCard(
                          label: 'Sent',
                          value: s == null ? '…' : '${s.sent}',
                        ),
                        AdminKpiCard(
                          label: 'Received',
                          value: s == null ? '…' : '${s.received}',
                        ),
                        AdminKpiCard(
                          label: 'Keep rate',
                          value:
                              s == null
                                  ? '…'
                                  : _AdminUsersTabState._pct(s.kept, s.sent),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Recent Activity',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                UserActivityList(db: db, uid: uid, start: start, end: end),
                const SizedBox(height: 16),
                Text(
                  'Fingerprint Preview',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                UserFingerprintGrid25(db: db, uid: uid), // 5×5 grid
              ],
            ),
          ),
        );
      },
    );
  }

  Future<_UserRowStats> _userStats(String uid) async {
    final sentAgg =
        await db
            .collectionGroup('userSwatches')
            .where('senderId', isEqualTo: uid)
            .where('status', isEqualTo: 'sent')
            .count()
            .get();

    final keptAgg =
        await db
            .collectionGroup('userSwatches')
            .where('senderId', isEqualTo: uid)
            .where('status', isEqualTo: 'sent')
            .where('kept', isEqualTo: true)
            .count()
            .get();

    final recvAgg =
        await db
            .collectionGroup('userSwatches')
            .where('recipientId', isEqualTo: uid)
            .where('status', isEqualTo: 'sent')
            .count()
            .get();

    return _UserRowStats(
      sent: (sentAgg.count ?? 0),
      kept: (keptAgg.count ?? 0),
      received: (recvAgg.count ?? 0),
    );
  }
}

/// 5×5 fingerprint preview grid that loads colors from the preferred sources:
/// 1) /users/{uid}/fingerprints (latest version)
/// 2) /users/{uid}/private/fingerprint (draft)
/// Falls back to empty checkerboard.
class UserFingerprintGrid25 extends StatelessWidget {
  const UserFingerprintGrid25({super.key, required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  // Normalize any value into hex string, or ''.
  String _hexFrom(dynamic v) {
    if (v is String) return v;
    if (v is Map) {
      final a = v['hex'] ?? v['colorHex'] ?? v['value'];
      return a is String ? a : '';
    }
    return '';
  }

  Future<List<String>> _loadHexes() async {
    List<String> out = [];

    // 1) Latest version
    try {
      final ver =
          await db
              .collection('users')
              .doc(uid)
              .collection('fingerprints')
              .orderBy('createdAt', descending: true)
              .limit(1)
              .get();
      if (ver.docs.isNotEmpty) {
        final m = ver.docs.first.data();
        if (m['answersHex'] is List) {
          out =
              (m['answersHex'] as List)
                  .map(_hexFrom)
                  .where((s) => s.isNotEmpty)
                  .cast<String>()
                  .toList();
        } else if (m['answers'] is List) {
          out =
              (m['answers'] as List)
                  .map(_hexFrom)
                  .where((s) => s.isNotEmpty)
                  .cast<String>()
                  .toList();
        } else if (m['tiles'] is List) {
          out =
              (m['tiles'] as List)
                  .map(_hexFrom)
                  .where((s) => s.isNotEmpty)
                  .cast<String>()
                  .toList();
        }
      }
    } catch (_) {
      // ignore
    }

    // 2) Draft
    if (out.isEmpty) {
      try {
        final d =
            await db
                .collection('users')
                .doc(uid)
                .collection('private')
                .doc('fingerprint')
                .get();
        final m = d.data() ?? const <String, dynamic>{};
        if (m['answersHex'] is List) {
          out =
              (m['answersHex'] as List)
                  .map(_hexFrom)
                  .where((s) => s.isNotEmpty)
                  .cast<String>()
                  .toList();
        } else if (m['answers'] is List) {
          out =
              (m['answers'] as List)
                  .map(_hexFrom)
                  .where((s) => s.isNotEmpty)
                  .cast<String>()
                  .toList();
        } else if (m['tiles'] is List) {
          out =
              (m['tiles'] as List)
                  .map(_hexFrom)
                  .where((s) => s.isNotEmpty)
                  .cast<String>()
                  .toList();
        }
      } catch (_) {
        // ignore
      }
    }

    if (out.length > 25) out = out.sublist(0, 25);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _loadHexes(),
      builder: (context, snap) {
        final hexes = snap.data ?? const <String>[];
        return _FingerprintGrid25(hexColors: hexes, cellSize: 28, gap: 6);
      },
    );
  }
}

/// Presentation-only 5×5 grid. Fills with hexColors; remaining cells are a
/// proper checkerboard across the grid (no 2×2 mini-squares per cell).
class _FingerprintGrid25 extends StatelessWidget {
  const _FingerprintGrid25({
    required this.hexColors,
    this.cellSize = 24,
    this.gap = 6,
  });

  final List<String> hexColors;
  final double cellSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    const int cols = 5;
    const int total = 25;
    final int filled = hexColors.length.clamp(0, total);
    const light = Color(0xFFEDEDEF);
    const dark = Color(0xFFDCDDE2);

    List<Widget> cells = [];
    for (int i = 0; i < total; i++) {
      if (i < filled) {
        final hex = hexColors[i];
        final color = adminColorFromHex(hex);
        cells.add(
          Container(
            width: cellSize,
            height: cellSize,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.black12, width: 0.5),
            ),
          ),
        );
      } else {
        final row = i ~/ cols;
        final col = i % cols;
        final bg = ((row + col) & 1) == 0 ? light : dark; // true checkerboard
        cells.add(
          Container(
            width: cellSize,
            height: cellSize,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.black12, width: 0.5),
            ),
          ),
        );
      }
    }

    return SizedBox(
      width: (cellSize * 5) + (gap * 4),
      child: Wrap(spacing: gap, runSpacing: gap, children: cells),
    );
  }
}

/// Compact list of this user’s activity (all-time) with From/To + nice time.
class UserActivityList extends StatelessWidget {
  const UserActivityList({
    super.key,
    required this.db,
    required this.uid,
    required this.start,
    required this.end,
  });

  final FirebaseFirestore db;
  final String uid;
  final Timestamp start; // kept for API compatibility
  final Timestamp end; // kept for API compatibility

  // "3:22pm January 31 2025" (uses sender offset if available; otherwise UTC)
  String _formatNiceTime(Map<String, dynamic> m, DateTime sentAtUtc) {
    final keys = <String>[
      'senderTzOffsetMin',
      'senderTzOffsetMinutes',
      'tzOffsetMin',
      'tzOffsetMinutes',
      'senderUtcOffsetMin',
    ];
    int? off;
    for (final k in keys) {
      final v = m[k];
      if (v is int) {
        off = v;
        break;
      }
      if (v is num) {
        off = v.toInt();
        break;
      }
    }
    final dt = off != null ? sentAtUtc.add(Duration(minutes: off)) : sentAtUtc;
    final raw = DateFormat('h:mma MMMM d y').format(dt);
    return raw.replaceAll('AM', 'am').replaceAll('PM', 'pm');
  }

  String _buildTitle(String? title, String hex) {
    final t =
        (title == null || title.trim().isEmpty) ? '(untitled)' : title.trim();
    return hex.isEmpty ? t : '$t • $hex';
  }

  @override
  Widget build(BuildContext context) {
    final nameCache = AdminNameCache(db);

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> load() async {
      final qs = await Future.wait([
        db
            .collectionGroup('userSwatches')
            .where('senderId', isEqualTo: uid)
            .where('status', isEqualTo: 'sent')
            .orderBy('sentAt', descending: true)
            .limit(20)
            .get(),
        db
            .collectionGroup('userSwatches')
            .where('recipientId', isEqualTo: uid)
            .where('status', isEqualTo: 'sent')
            .orderBy('sentAt', descending: true)
            .limit(20)
            .get(),
      ]);

      final combined = <QueryDocumentSnapshot<Map<String, dynamic>>>[
        ...qs[0].docs,
        ...qs[1].docs,
      ];
      combined.sort((a, b) {
        final ta = (a.data()['sentAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        final tb = (b.data()['sentAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        return tb.compareTo(ta);
      });

      final ids = <String>{
        for (final d in combined) ...[
          (d.data()['senderId'] as String?) ?? '',
          (d.data()['recipientId'] as String?) ?? '',
        ],
      }..removeWhere((e) => e.isEmpty);
      if (ids.isNotEmpty) {
        await nameCache.resolve(ids);
      }

      return combined.length > 30 ? combined.sublist(0, 30) : combined;
    }

    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: load(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data!;
        if (docs.isEmpty) {
          return const SizedBox(
            height: 40,
            child: Center(
              child: Text(
                'No activity yet.',
                style: TextStyle(color: kAdminMuted),
              ),
            ),
          );
        }

        String nameOrUid(String id) {
          if (id.isEmpty) return '';
          final n = nameCache.nameFor(id);
          return n.isNotEmpty ? n : id;
        }

        return SizedBox(
          height: 220,
          child: ListView.separated(
            itemCount: docs.length,
            separatorBuilder:
                (_, __) => const Divider(height: 1, color: kAdminDivider),
            itemBuilder: (context, i) {
              final m = docs[i].data();
              final sentAt = (m['sentAt'] as Timestamp?)?.toDate();
              final hex = (m['colorHex'] as String?) ?? '';
              final title =
                  (m['title'] as String?) ??
                  (m['swatchTitle'] as String?) ??
                  '';
              final senderId = (m['senderId'] as String?) ?? '';
              final recipientId = (m['recipientId'] as String?) ?? '';

              final senderLabel = nameOrUid(senderId);
              final recipientLabel = nameOrUid(recipientId);
              final niceTime =
                  sentAt == null ? '' : _formatNiceTime(m, sentAt.toUtc());

              return ListTile(
                dense: true,
                leading: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: hex.isEmpty ? Colors.white : adminColorFromHex(hex),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.black12),
                  ),
                ),
                title: Text(
                  _buildTitle(title, hex),
                  style: const TextStyle(color: kAdminText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if (senderLabel.isNotEmpty) 'From $senderLabel',
                    if (recipientLabel.isNotEmpty) 'To $recipientLabel',
                    if (niceTime.isNotEmpty) niceTime,
                  ].join(' • '),
                  style: const TextStyle(color: kAdminMuted),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
