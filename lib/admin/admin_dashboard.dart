// lib/admin/admin_dashboard.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Tabs
import 'package:color_wallet/admin/admin_components.dart';
import 'package:color_wallet/admin/admin_users_tab.dart';
import 'package:color_wallet/admin/admin_fingerprints_tab.dart';
import 'package:color_wallet/admin/admin_fingerprint_answers_tab.dart';
import 'package:color_wallet/admin/admin_questions_tab.dart';
import 'package:color_wallet/admin/admin_swatches_tab.dart';
import 'package:color_wallet/admin/admin_color_trends_tab.dart';
import 'package:color_wallet/admin/admin_rewards_tab.dart';
import 'package:color_wallet/admin/admin_party_results_tab.dart';

/// Zenmo — Admin/Insights Dashboard (split into multiple files)
/// Route + shell logic only.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  static const routeName = '/admin';

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

enum _AdminRange { today, last7d, last28d, custom }

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  // ---- Door code (optional, client-side only) -------------------------------
  static const String _kDoorCode = 'zenmo123';
  static const bool _kDoorUnlockBypassesClaim = bool.fromEnvironment(
    'ADMIN_DOOR_BYPASS',
    defaultValue: false,
  );

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _doorUnlocked = false;
  final TextEditingController _doorCtrl = TextEditingController();
  final ValueNotifier<bool> _doorObscure = ValueNotifier<bool>(true);

  bool _loadingAuthz = true;
  bool _isAdmin = false;

  late final TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  final _AdminRange _range = _AdminRange.last7d;
  DateTime? _customStartLocal;
  DateTime? _customEndLocal;

  static const int _kMaxDocsForColorStats = 2000;

  @override
  void initState() {
    super.initState();
    adminIsWide.value = true;
    _tabController = TabController(length: 8, vsync: this);
    // Rebuild when the active tab changes (to show/hide the range bar).
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _checkAdminClaim();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _doorCtrl.dispose();
    _doorObscure.dispose();
    adminIsWide.value = false;
    super.dispose();
  }

  Future<void> _checkAdminClaim() async {
    if (_kDoorUnlockBypassesClaim && _kDoorCode.isNotEmpty) {
      setState(() {
        _isAdmin = true;
        _loadingAuthz = false;
      });
      return;
    }
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isAdmin = false;
        _loadingAuthz = false;
      });
      return;
    }
    final token = await user.getIdTokenResult(true);
    setState(() {
      _isAdmin = token.claims?['admin'] == true;
      _loadingAuthz = false;
    });
  }

  ({Timestamp startUtc, Timestamp endUtc, String label}) _activeRangeUtc() {
    final nowLocal = DateTime.now();
    DateTime startLocal;
    DateTime endLocalExclusive;
    switch (_range) {
      case _AdminRange.today:
        startLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
        endLocalExclusive = startLocal.add(const Duration(days: 1));
        break;
      case _AdminRange.last7d:
        endLocalExclusive = DateTime(
          nowLocal.year,
          nowLocal.month,
          nowLocal.day,
        ).add(const Duration(days: 1));
        startLocal = endLocalExclusive.subtract(const Duration(days: 7));
        break;
      case _AdminRange.last28d:
        endLocalExclusive = DateTime(
          nowLocal.year,
          nowLocal.month,
          nowLocal.day,
        ).add(const Duration(days: 1));
        startLocal = endLocalExclusive.subtract(const Duration(days: 28));
        break;
      case _AdminRange.custom:
        startLocal =
            _customStartLocal ??
            DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
        endLocalExclusive =
            _customEndLocal ??
            DateTime(
              nowLocal.year,
              nowLocal.month,
              nowLocal.day,
            ).add(const Duration(days: 1));
        if (!endLocalExclusive.isAfter(startLocal)) {
          endLocalExclusive = startLocal.add(const Duration(days: 1));
        }
        break;
    }
    return (
      startUtc: Timestamp.fromDate(startLocal.toUtc()),
      endUtc: Timestamp.fromDate(endLocalExclusive.toUtc()),
      label: switch (_range) {
        _AdminRange.today => 'Today',
        _AdminRange.last7d => 'Last 7 days',
        _AdminRange.last28d => 'Last 28 days',
        _AdminRange.custom => 'Custom',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_kDoorCode.isNotEmpty && !_doorUnlocked) return _buildDoorGate(context);

    if (_loadingAuthz) {
      return const Scaffold(
        appBar: _SimpleAppBar(title: 'Admin'),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final gateOpen = _isAdmin || (_kDoorCode.isNotEmpty && _doorUnlocked);
    if (!gateOpen) {
      return const Scaffold(
        appBar: _SimpleAppBar(title: 'Admin'),
        body: Center(
          child: Card(
            margin: EdgeInsets.all(24),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Not authorized. Enter the admin access code.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final range = _activeRangeUtc();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zenmo Admin'),
        // Global search removed; keep helpers/fields as-is (harmless if unused).
        actions: const [],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Users'),
            Tab(text: 'Fingerprints'),
            Tab(text: 'FP Answers'),
            Tab(text: 'Questions'),
            Tab(text: 'Swatches'),
            Tab(text: 'Color Trends'),
            Tab(text: 'Rewards'),
            Tab(text: 'Party Results'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Users (keeps range)
                AdminUsersTab(
                  db: _db,
                  start: range.startUtc,
                  end: range.endUtc,
                  maxDocsForStats: _kMaxDocsForColorStats,
                ),

                // Non-Users tabs: all-time. Pass nulls to future-proof APIs.
                AdminFingerprintsTab(db: _db, startUtc: null, endUtc: null),
                AdminFingerprintAnswersTab(
                  db: _db,
                  startUtc: null,
                  endUtc: null,
                  maxDocsForStats: 2000,
                ),
                AdminQuestionsTab(db: _db, startUtc: null, endUtc: null),
                AdminSwatchesTab(
                  db: _db,
                  startUtc: null,
                  endUtc: null,
                  maxDocsForColorStats: _kMaxDocsForColorStats,
                ),
                AdminColorTrendsTab(
                  db: _db,
                  startUtc: null,
                  endUtc: null,
                  maxDocs: _kMaxDocsForColorStats,
                ),
                const AdminRewardsTab(),
                AdminPartyResultsTab(db: _db, eventKey: 'party'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Scaffold _buildDoorGate(BuildContext context) {
    final controller = _doorCtrl;
    return Scaffold(
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints:
                adminIsWide.value
                    ? const BoxConstraints()
                    : const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.admin_panel_settings, size: 48),
                  const SizedBox(height: 8),
                  const Text('Enter access code to continue'),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<bool>(
                    valueListenable: _doorObscure,
                    builder: (_, obscured, __) {
                      return TextField(
                        controller: controller,
                        obscureText: obscured,
                        decoration: InputDecoration(
                          labelText: 'Access code',
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscured
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () => _doorObscure.value = !obscured,
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _tryUnlock(),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _tryUnlock,
                      icon: const Icon(Icons.login),
                      label: const Text('Unlock'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _tryUnlock() {
    final input = _doorCtrl.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a code.')));
      return;
    }
    if (input == _kDoorCode) {
      setState(() => _doorUnlocked = true);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Incorrect code.')));
    }
  }

  DateTimeRange _initialDateRangeForCustom() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return DateTimeRange(
      start: _customStartLocal ?? todayStart.subtract(const Duration(days: 7)),
      end: _customEndLocal ?? todayStart.add(const Duration(days: 1)),
    );
  }

  // ---------------------------------------------------------------------------
  // SEARCH: username / UID / email (no HEX)
  // ---------------------------------------------------------------------------

  bool _looksLikeEmail(String s) {
    final t = s.trim();
    // permissive email pattern
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _usersByExact(
    String field,
    String value,
  ) async {
    final snap =
        await _db
            .collection('users')
            .where(field, isEqualTo: value)
            .limit(10)
            .get();
    return snap.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _usersByPrefix(
    String field,
    String prefix,
  ) async {
    try {
      final snap =
          await _db
              .collection('users')
              .orderBy(field)
              .startAt([prefix])
              .endAt(['$prefix\uf8ff'])
              .limit(10)
              .get();
      return snap.docs;
    } catch (_) {
      // If index/orderBy isn't available, just return empty.
      return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }
  }

  Future<void> _handleSearch(String q) async {
    final raw = q.trim();
    if (raw.isEmpty) return;

    final range = _activeRangeUtc();
    final noAt = raw.startsWith('@') ? raw.substring(1) : raw;
    final lower = noAt.toLowerCase();

    // 1) EMAIL — exact (case, lowercase, and emailLower if present)
    if (_looksLikeEmail(raw)) {
      final hits1 = await _usersByExact('email', raw);
      final hits2 =
          hits1.isNotEmpty ? hits1 : await _usersByExact('email', lower);
      final hits3 =
          hits2.isNotEmpty ? hits2 : await _usersByExact('emailLower', lower);
      final hits = hits3;

      if (!mounted) return;
      if (hits.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No users with that email.')),
        );
        return;
      }
      if (hits.length == 1) {
        final u = hits.first;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          constraints:
              adminIsWide.value
                  ? BoxConstraints(maxWidth: MediaQuery.of(context).size.width)
                  : null,
          builder:
              (_) => AdminUserQuickViewSheet(
                uid: u.id,
                userDoc: u,
                start: range.startUtc,
                end: range.endUtc,
                db: _db,
              ),
        );
        return;
      }
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder:
            (_) => _UserResultsSheet(
              results: hits,
              start: range.startUtc,
              end: range.endUtc,
              db: _db,
            ),
      );
      return;
    }

    // 2) UID — direct doc
    if (adminLooksLikeUid(noAt)) {
      final u = await _db.collection('users').doc(noAt).get();
      if (!mounted) return;
      if (!u.exists) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No user with that UID.')));
        return;
      }
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        constraints:
            adminIsWide.value
                ? BoxConstraints(maxWidth: MediaQuery.of(context).size.width)
                : null,
        builder:
            (_) => AdminUserQuickViewSheet(
              uid: u.id,
              userDoc: u,
              start: range.startUtc,
              end: range.endUtc,
              db: _db,
            ),
      );
      return;
    }

    // 3) USERNAME/DISPLAY — exact on a few fields (case + lower variants)
    List<QueryDocumentSnapshot<Map<String, dynamic>>> hits = [];
    hits = await _usersByExact('username', noAt);
    if (hits.isEmpty) hits = await _usersByExact('username', lower);
    if (hits.isEmpty) hits = await _usersByExact('usernameLower', lower);
    if (hits.isEmpty) hits = await _usersByExact('displayName', raw);
    if (hits.isEmpty) hits = await _usersByExact('displayNameLower', lower);

    // 4) Prefix fallback (partial search)
    if (hits.isEmpty) {
      hits = await _usersByPrefix('username', noAt);
      if (hits.isEmpty) hits = await _usersByPrefix('usernameLower', lower);
      if (hits.isEmpty) hits = await _usersByPrefix('displayName', raw);
      if (hits.isEmpty) hits = await _usersByPrefix('displayNameLower', lower);
    }

    if (!mounted) return;
    if (hits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No users matched that query.')),
      );
      return;
    }
    if (hits.length == 1) {
      final u = hits.first;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        constraints:
            adminIsWide.value
                ? BoxConstraints(maxWidth: MediaQuery.of(context).size.width)
                : null,
        builder:
            (_) => AdminUserQuickViewSheet(
              uid: u.id,
              userDoc: u,
              start: range.startUtc,
              end: range.endUtc,
              db: _db,
            ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => _UserResultsSheet(
            results: hits,
            start: range.startUtc,
            end: range.endUtc,
            db: _db,
          ),
    );
  }
}

// -----------------------------------------------------------------------------
// Smaller widgets + helpers used by this dashboard
// -----------------------------------------------------------------------------

class _SimpleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SimpleAppBar({required this.title});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: Colors.grey),
      ),
    );
  }
}

class _UserResultsSheet extends StatelessWidget {
  const _UserResultsSheet({
    required this.results,
    required this.start,
    required this.end,
    required this.db,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> results;
  final Timestamp start;
  final Timestamp end;
  final FirebaseFirestore db;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: results.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final u = results[i];
          final d = u.data();
          final username = (d['username'] ?? d['displayName'] ?? '').toString();
          final email = (d['email'] ?? '').toString();
          return ListTile(
            title: Text(username.isEmpty ? u.id : username),
            subtitle: Text(email),
            onTap: () {
              Navigator.of(context).pop();
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                constraints:
                    adminIsWide.value
                        ? BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width,
                        )
                        : null,
                builder:
                    (_) => AdminUserQuickViewSheet(
                      uid: u.id,
                      userDoc: u,
                      start: start,
                      end: end,
                      db: db,
                    ),
              );
            },
          );
        },
      ),
    );
  }
}
