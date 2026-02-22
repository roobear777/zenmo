// lib/admin/admin_swatches_tab.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:color_wallet/admin/admin_components.dart';
import 'package:intl/intl.dart';

class AdminSwatchesTab extends StatefulWidget {
  const AdminSwatchesTab({
    super.key,
    required this.db,
    this.startUtc, // optional, ignored (all-time)
    this.endUtc, // optional, ignored (all-time)
    required this.maxDocsForColorStats,
  });

  final FirebaseFirestore db;
  final Timestamp? startUtc; // legacy/no-op
  final Timestamp? endUtc; // legacy/no-op
  final int maxDocsForColorStats;

  @override
  State<AdminSwatchesTab> createState() => _AdminSwatchesTabState();
}

class _AdminSwatchesTabState extends State<AdminSwatchesTab>
    with TickerProviderStateMixin {
  static const TextStyle _subtle = TextStyle(
    fontSize: 12,
    color: Colors.black45,
  );

  late AdminNameCache _nameCache;

  // Month tabs (newest → oldest)
  late TabController _tabCtl;
  List<DateTime> _monthStarts = []; // UTC month starts
  bool _loadingMonths = true;

  // Current month’s docs
  bool _loadingList = false;
  final _rows = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

  // All-time docs for search
  final _allRows = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  bool _loadingAll = false;
  bool _hasLoadedAllForSearch = false;

  // --- Simple title search (case-insensitive, partial match) -----------------
  final TextEditingController _searchCtl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _nameCache = AdminNameCache(widget.db);
    _initMonths();
  }

  @override
  void didUpdateWidget(covariant AdminSwatchesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.db != widget.db) {
      _nameCache = AdminNameCache(widget.db);
      _initMonths();
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  // --- Month discovery -------------------------------------------------------

  Future<void> _initMonths() async {
    setState(() {
      _loadingMonths = true;
      _rows.clear();
    });

    DateTime nowUtc = DateTime.now().toUtc();
    DateTime thisMonth = DateTime.utc(nowUtc.year, nowUtc.month, 1);

    // Try to discover the earliest sentAt month in data (fast, 1 doc).
    DateTime? earliestMonth;
    try {
      final qs =
          await widget.db
              .collectionGroup('userSwatches')
              .where('status', isEqualTo: 'sent')
              .where(
                'sentAt',
                isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(0),
              )
              .orderBy('sentAt') // oldest first
              .limit(1)
              .get();

      if (qs.docs.isNotEmpty) {
        final ts = qs.docs.first.data()['sentAt'] as Timestamp?;
        if (ts != null) {
          final dt = ts.toDate().toUtc();
          earliestMonth = DateTime.utc(dt.year, dt.month, 1);
        }
      }
    } catch (_) {
      // If anything goes wrong, we’ll just default to last 12 months below.
    }

    // Build month list newest→oldest.
    final months = <DateTime>[];
    if (earliestMonth != null) {
      DateTime cur = thisMonth;
      while (!cur.isBefore(earliestMonth)) {
        months.add(cur);
        cur = _prevMonth(cur);
      }
    } else {
      // Fallback: last 12 months
      DateTime cur = thisMonth;
      for (int i = 0; i < 12; i++) {
        months.add(cur);
        cur = _prevMonth(cur);
      }
    }

    _monthStarts = months;
    _tabCtl = TabController(length: _monthStarts.length, vsync: this);
    _tabCtl.addListener(() {
      if (_tabCtl.indexIsChanging) return;
      _loadCurrentMonth();
    });

    setState(() {
      _loadingMonths = false;
    });

    // Load the newest month initially
    await _loadCurrentMonth();
  }

  DateTime _prevMonth(DateTime m) {
    final y = m.year;
    final mo = m.month;
    if (mo == 1) return DateTime.utc(y - 1, 12, 1);
    return DateTime.utc(y, mo - 1, 1);
  }

  DateTime _nextMonth(DateTime m) {
    final y = m.year;
    final mo = m.month;
    if (mo == 12) return DateTime.utc(y + 1, 1, 1);
    return DateTime.utc(y, mo + 1, 1);
  }

  // --- Data load for selected month -----------------------------------------

  Future<void> _loadCurrentMonth() async {
    if (_loadingMonths || _monthStarts.isEmpty) return;
    setState(() {
      _loadingList = true;
      _rows.clear();
    });

    final startUtc = _monthStarts[_tabCtl.index];
    final endUtc = _nextMonth(startUtc);

    try {
      final snap =
          await widget.db
              .collectionGroup('userSwatches')
              .where('status', isEqualTo: 'sent')
              .where(
                'sentAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startUtc),
              )
              .where('sentAt', isLessThan: Timestamp.fromDate(endUtc))
              .orderBy('sentAt', descending: true)
              // optional tie-breaker; no pagination, so not strictly necessary:
              .orderBy(FieldPath.documentId, descending: true)
              .get();

      _rows.addAll(snap.docs);
      await _refreshNamesForRows(_rows);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load swatches: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  // --- Data load for all-time search ----------------------------------------

  Future<void> _ensureAllRowsLoadedForSearch() async {
    if (_hasLoadedAllForSearch || _loadingAll) return;

    setState(() {
      _loadingAll = true;
      _allRows.clear();
    });

    try {
      final snap =
          await widget.db
              .collectionGroup('userSwatches')
              .where('status', isEqualTo: 'sent')
              .where(
                'sentAt',
                isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(0),
              )
              .orderBy('sentAt', descending: true)
              // optional tie-breaker; no pagination, so not strictly necessary:
              .orderBy(FieldPath.documentId, descending: true)
              .get();

      _allRows.addAll(snap.docs);
      await _refreshNamesForRows(_allRows);
      _hasLoadedAllForSearch = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load all swatches for search: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingAll = false;
        });
      }
    }
  }

  Future<void> _refreshNamesForRows(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final ids = <String>{};
    for (final d in docs) {
      final m = d.data();
      final s = (m['senderId'] as String?) ?? '';
      final r = (m['recipientId'] as String?) ?? '';
      if (s.isNotEmpty) ids.add(s);
      if (r.isNotEmpty) ids.add(r);
    }
    if (ids.isEmpty) return;
    await _nameCache.resolve(ids);
    if (mounted) setState(() {});
  }

  // --- Formatting helpers ----------------------------------------------------

  String _fmtMonth(DateTime m) => DateFormat('MMM yyyy').format(m);

  /// Returns a human-friendly timestamp like "3:22pm January 31 2025".
  String _formatNiceTime(Map<String, dynamic> m) {
    final DateTime? sentAt =
        (m['sentAt'] is Timestamp) ? (m['sentAt'] as Timestamp).toDate() : null;
    final DateTime? createdAt =
        (m['createdAt'] is Timestamp)
            ? (m['createdAt'] as Timestamp).toDate()
            : null;

    final DateTime base = (sentAt ?? createdAt ?? DateTime.now()).toUtc();

    const candidateKeys = <String>[
      'senderTzOffsetMin',
      'senderTzOffsetMinutes',
      'tzOffsetMin',
      'tzOffsetMinutes',
      'senderUtcOffsetMin',
    ];

    int? offsetMinutes;
    for (final k in candidateKeys) {
      final v = m[k];
      if (v is int) {
        offsetMinutes = v;
        break;
      }
      if (v is num) {
        offsetMinutes = v.toInt();
        break;
      }
    }

    DateTime dt = base;
    String suffix = ' UTC';
    if (offsetMinutes != null) {
      dt = base.add(Duration(minutes: offsetMinutes));
      suffix = '';
    }

    final raw = DateFormat('h:mma MMMM d y').format(dt);
    final lower = raw.replaceAll('AM', 'am').replaceAll('PM', 'pm');
    return '$lower$suffix';
  }

  String _buildTitle(String? title, String hex) {
    final safeTitle =
        (title == null || title.trim().isEmpty) ? '(untitled)' : title.trim();
    final safeHex = hex.isEmpty ? '' : hex;
    return safeHex.isEmpty ? safeTitle : '$safeTitle • $safeHex';
  }

  // Case-insensitive partial match on title.
  bool _matchesSearch(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;

    final data = doc.data();
    final rawTitle = (data['title'] as String?) ?? '';
    final title = rawTitle.toLowerCase();

    return title.contains(q);
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loadingMonths) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_monthStarts.isEmpty) {
      return const Center(
        child: Text('No months found.', style: TextStyle(color: kAdminMuted)),
      );
    }

    final tabs = _monthStarts.map((m) => Tab(text: _fmtMonth(m))).toList();

    final hasQuery = _searchQuery.trim().isNotEmpty;
    // When searching and all-time data is ready, use _allRows; otherwise use current month.
    final sourceRows = hasQuery && _hasLoadedAllForSearch ? _allRows : _rows;
    final visibleRows =
        _searchQuery.isEmpty
            ? _rows
            : sourceRows.where(_matchesSearch).toList();

    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            hasQuery
                ? "Searching titles across all sent swatches (all months)."
                : "Sent swatches by month (status=='sent' with sentAt). Select a month to view.",
            style: _subtle,
          ),
        ),
        Material(
          elevation: 1,
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabCtl,
            isScrollable: true,
            labelColor: kAdminText,
            unselectedLabelColor: kAdminMuted,
            tabs: tabs,
          ),
        ),
        // --- Search bar for title (case-insensitive, partial) ---
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _searchCtl,
            decoration: InputDecoration(
              labelText: 'Filter by title (all months)',
              hintText: 'Type part of a title…',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon:
                  hasQuery
                      ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchCtl.clear();
                          });
                        },
                      )
                      : null,
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
              if (value.trim().isNotEmpty) {
                _ensureAllRowsLoadedForSearch();
              }
            },
          ),
        ),
        if (_loadingAll && hasQuery)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Loading all swatches for search…',
                style: TextStyle(fontSize: 11, color: kAdminMuted),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _loadCurrentMonth(),
            child:
                _loadingList && visibleRows.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : (visibleRows.isEmpty
                        ? const Center(
                          child: Text(
                            'No swatches for this month.',
                            style: TextStyle(color: kAdminMuted),
                          ),
                        )
                        : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          itemCount: visibleRows.length,
                          separatorBuilder:
                              (_, __) => const Divider(
                                height: 1,
                                color: kAdminDivider,
                              ),
                          itemBuilder: (_, i) {
                            final m = visibleRows[i].data();

                            final hex = (m['colorHex'] as String?) ?? '';
                            final title =
                                (m['title'] as String?); // may be null
                            final sender = (m['senderId'] as String?) ?? '';
                            final recipient =
                                (m['recipientId'] as String?) ?? '';

                            final senderLabel =
                                sender.isEmpty
                                    ? ''
                                    : _nameCache.nameFor(sender);
                            final recipientLabel =
                                recipient.isNotEmpty
                                    ? _nameCache.nameFor(recipient)
                                    : '';

                            final niceTime = _formatNiceTime(m);

                            return ListTile(
                              leading:
                                  hex.isEmpty
                                      ? const SizedBox(width: 22, height: 22)
                                      : AdminColorChip(hex),
                              title: Text(
                                _buildTitle(title, hex),
                                style: const TextStyle(
                                  color: kAdminText,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  if (senderLabel.isNotEmpty)
                                    'from $senderLabel',
                                  if (recipientLabel.isNotEmpty)
                                    'to $recipientLabel',
                                  if (niceTime.isNotEmpty) niceTime,
                                ].join(' • '),
                                style: const TextStyle(color: kAdminMuted),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              dense: false,
                            );
                          },
                        )),
          ),
        ),
      ],
    );
  }
}
