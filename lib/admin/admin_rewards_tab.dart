// lib/admin/admin_rewards_tab.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:color_wallet/admin/rewards_admin_service.dart';

/// Keep this list in sync with the backend REWARD_THRESHOLDS.
const List<int> kRewardThresholds = <int>[
  10,
  20,
  30,
  50,
  80,
  130,
  210,
  340,
  550,
  890,
  1440,
];

class UserProgressRow {
  const UserProgressRow({
    required this.userId,
    required this.totalSentCount,
    required this.currentTier,
    required this.nextTier,
    required this.remainingToNext,
    required this.pctToNext,
    required this.unlockedCount,
    this.displayName,
    this.email,
  });

  final String userId;
  final String? displayName;
  final String? email;

  final int totalSentCount;

  final int currentTier; // threshold achieved (0 if none)
  final int? nextTier; // next threshold (null if maxed)
  final int? remainingToNext;
  final double pctToNext; // 0..1

  final int unlockedCount;

  static UserProgressRow fromUserSnap(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final d = snap.data() ?? <String, dynamic>{};

    final sentRaw = d['totalSentCount'] ?? 0;
    final sent = sentRaw is int ? sentRaw : int.tryParse('$sentRaw') ?? 0;

    final String? displayName =
        (d['displayName'] as String?) ??
        (d['username'] as String?) ??
        (d['name'] as String?);

    final String? email = d['email'] as String?;

    int currentTier = 0;
    for (final t in kRewardThresholds) {
      if (t <= sent) currentTier = t;
    }

    int? nextTier;
    for (final t in kRewardThresholds) {
      if (t > sent) {
        nextTier = t;
        break;
      }
    }

    final remaining = nextTier == null ? null : (nextTier - sent);

    final int unlockedCount = kRewardThresholds.where((t) => t <= sent).length;

    final double pctToNext;
    if (nextTier == null) {
      pctToNext = 1.0;
    } else {
      final denom = (nextTier - currentTier);
      pctToNext = denom <= 0 ? 0.0 : (sent - currentTier) / denom;
    }

    return UserProgressRow(
      userId: snap.id,
      displayName: displayName,
      email: email,
      totalSentCount: sent,
      currentTier: currentTier,
      nextTier: nextTier,
      remainingToNext: remaining,
      pctToNext: pctToNext.clamp(0.0, 1.0),
      unlockedCount: unlockedCount,
    );
  }
}

class AdminRewardsTab extends StatefulWidget {
  const AdminRewardsTab({super.key});

  @override
  State<AdminRewardsTab> createState() => _AdminRewardsTabState();
}

class _AdminRewardsTabState extends State<AdminRewardsTab> {
  final RewardsAdminService _service = RewardsAdminService();

  // “No filters by default” → show everything initially.
  String _statusFilter = 'all'; // all|pending|fulfilled|skipped
  int? _thresholdEquals;
  String _searchText = '';

  int _rewardRowsPerPage = PaginatedDataTable.defaultRowsPerPage;
  int _userRowsPerPage = 8;

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _buildProgressCard(context),
        const SizedBox(height: 16),
        _buildRewardsCard(context),
      ],
    );
  }

  Widget _buildProgressCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream:
              FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('totalSentCount', descending: true)
                  .limit(200)
                  .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return _ErrorBox(
                title: 'User progress stream error',
                error: snap.error,
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final rows =
                snap.data!.docs.map(UserProgressRow.fromUserSnap).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Progress to next reward tier',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                PaginatedDataTable(
                  header: const Text('Users'),
                  rowsPerPage: _userRowsPerPage,
                  availableRowsPerPage: const <int>[5, 8, 12, 20],
                  onRowsPerPageChanged: (v) {
                    if (v == null) return;
                    setState(() => _userRowsPerPage = v);
                  },
                  columns: const <DataColumn>[
                    DataColumn(label: Text('User')),
                    DataColumn(label: Text('Sent')),
                    DataColumn(label: Text('Unlocked')),
                    DataColumn(label: Text('Current tier')),
                    DataColumn(label: Text('Next tier')),
                    DataColumn(label: Text('To go')),
                    DataColumn(label: Text('Progress')),
                  ],
                  source: _UserProgressTableSource(rows),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRewardsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: StreamBuilder<List<RewardRow>>(
          stream: _service.streamRewards(
            statusFilter: _statusFilter,
            thresholdEquals: _thresholdEquals,
            searchText: _searchText.isEmpty ? null : _searchText,
            limit: 500,
          ),
          builder: (context, snap) {
            if (snap.hasError) {
              return _ErrorBox(
                title: 'Rewards stream error',
                error: snap.error,
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final rows = snap.data!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Unlocked rewards',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),

                // Filters are available but collapsed by default.
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Filters'),
                  children: <Widget>[
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        _buildStatusDropdown(),
                        _buildThresholdDropdown(),
                        SizedBox(
                          width: 320,
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Search (userId, email, label)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _applySearch(),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _applySearch,
                          child: const Text('Apply'),
                        ),
                        TextButton(
                          onPressed: _resetFilters,
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),

                PaginatedDataTable(
                  header: Text('${rows.length} reward(s)'),
                  rowsPerPage: _rewardRowsPerPage,
                  availableRowsPerPage: const <int>[5, 10, 20, 50],
                  onRowsPerPageChanged: (v) {
                    if (v == null) return;
                    setState(() => _rewardRowsPerPage = v);
                  },
                  columns: const <DataColumn>[
                    DataColumn(label: Text('Created')),
                    DataColumn(label: Text('User')),
                    DataColumn(label: Text('Threshold')),
                    DataColumn(label: Text('Label')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Updated')),
                    DataColumn(label: Text('Action')),
                  ],
                  source: _RewardsTableSource(
                    rows: rows,
                    onUpdateStatus: _updateStatus,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return DropdownButton<String>(
      value: _statusFilter,
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem(value: 'all', child: Text('All statuses')),
        DropdownMenuItem(value: 'pending', child: Text('Pending')),
        DropdownMenuItem(value: 'fulfilled', child: Text('Fulfilled')),
        DropdownMenuItem(value: 'skipped', child: Text('Skipped')),
      ],
      onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
    );
  }

  Widget _buildThresholdDropdown() {
    final items = <DropdownMenuItem<int?>>[
      const DropdownMenuItem<int?>(value: null, child: Text('All thresholds')),
      ...kRewardThresholds.map(
        (t) => DropdownMenuItem<int?>(value: t, child: Text('$t')),
      ),
    ];

    return DropdownButton<int?>(
      value: _thresholdEquals,
      items: items,
      onChanged: (v) => setState(() => _thresholdEquals = v),
    );
  }

  void _applySearch() {
    setState(() => _searchText = _searchCtrl.text.trim());
  }

  void _resetFilters() {
    setState(() {
      _statusFilter = 'all';
      _thresholdEquals = null;
      _searchText = '';
      _searchCtrl.text = '';
    });
  }

  Future<void> _updateStatus(RewardRow row, String newStatus) async {
    try {
      await _service.updateFulfilment(
        userId: row.userId,
        rewardId: row.rewardId,
        status: newStatus,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated ${row.userId}/${row.rewardId} → $newStatus'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }
}

class _UserProgressTableSource extends DataTableSource {
  _UserProgressTableSource(this.rows);

  final List<UserProgressRow> rows;

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= rows.length) return null;
    final r = rows[index];

    return DataRow.byIndex(
      index: index,
      cells: <DataCell>[
        DataCell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                r.displayName?.trim().isNotEmpty == true
                    ? r.displayName!
                    : r.userId,
              ),
              if (r.email?.trim().isNotEmpty == true)
                Text(
                  r.email!,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
            ],
          ),
        ),
        DataCell(Text('${r.totalSentCount}')),
        DataCell(Text('${r.unlockedCount}')),
        DataCell(Text('${r.currentTier}')),
        DataCell(Text(r.nextTier == null ? '—' : '${r.nextTier}')),
        DataCell(
          Text(r.remainingToNext == null ? '—' : '${r.remainingToNext}'),
        ),
        DataCell(
          SizedBox(
            width: 160,
            child: Row(
              children: <Widget>[
                Expanded(child: LinearProgressIndicator(value: r.pctToNext)),
                const SizedBox(width: 8),
                Text('${(r.pctToNext * 100).round()}%'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => rows.length;

  @override
  int get selectedRowCount => 0;
}

class _RewardsTableSource extends DataTableSource {
  _RewardsTableSource({required this.rows, required this.onUpdateStatus});

  final List<RewardRow> rows;
  final Future<void> Function(RewardRow row, String newStatus) onUpdateStatus;

  static String _fmtTs(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate().toUtc();
    final s = dt.toIso8601String();
    // YYYY-MM-DD HH:MM
    final basic = s.replaceFirst('T', ' ');
    return basic.length >= 16 ? '${basic.substring(0, 16)}Z' : '${basic}Z';
  }

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= rows.length) return null;
    final r = rows[index];

    return DataRow.byIndex(
      index: index,
      cells: <DataCell>[
        DataCell(Text(_fmtTs(r.createdAt))),
        DataCell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(r.userId.isEmpty ? '—' : r.userId),
              if ((r.email ?? '').trim().isNotEmpty)
                Text(
                  r.email!,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
            ],
          ),
        ),
        DataCell(Text('${r.threshold}')),
        DataCell(Text(r.label)),
        DataCell(Text(r.status)),
        DataCell(Text(_fmtTs(r.lastUpdatedAt))),
        DataCell(
          DropdownButton<String>(
            value: _normalizeStatus(r.status),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'fulfilled', child: Text('Fulfilled')),
              DropdownMenuItem(value: 'skipped', child: Text('Skipped')),
            ],
            onChanged: (v) {
              if (v == null) return;
              onUpdateStatus(r, v);
            },
          ),
        ),
      ],
    );
  }

  static String _normalizeStatus(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'fulfilled') return 'fulfilled';
    if (s == 'skipped') return 'skipped';
    return 'pending';
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => rows.length;

  @override
  int get selectedRowCount => 0;
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.title, required this.error});

  final String title;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final msg = '$error';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SelectableText(msg),
          const SizedBox(height: 8),
          const Text(
            'If this mentions an index, either switch filters back to “All” or create the Firestore composite index suggested in the error.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
