// lib/account_screen.dart
import 'package:color_wallet/widgets/wallet_badge_icon.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:color_wallet/menu.dart';

// NEW (Party inline section needs these types + uid for logging)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'wallet_screen.dart';
import 'color_picker_screen.dart';
import 'daily_hues/daily_scroll_screen.dart'; // CHANGED: use scroll screen

// NEW: keepsake navigation target
import 'keepsake_options_screen.dart';

import 'fingerprint_grid.dart';
import 'fingerprint_flow.dart';
import 'fingerprint_questions.dart';
import 'fingerprint_repo.dart';
import 'package:color_wallet/fingerprint_intro_screen.dart'; // intro screen

// Party
import 'party_fingerprint_intro_screen.dart';
import 'party_fingerprint_repo.dart';

// Added: redo button + monthly note
import 'widgets/fingerprint_redo_button.dart';
import 'widgets/fingerprint_monthly_note.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen>
    with SingleTickerProviderStateMixin {
  static const _kToastKey = 'fingerprint_shuffle_toast_shown';
  final int _selectedIndex = 2;

  List<int> _answersLocal = const [];
  bool _prefsLoaded = false;
  bool _shuffleToastShown = false;

  static final List<int> _spiral5x5 = _centerOutSpiral(rows: 5, cols: 5);

  // Party debug (minimal + removable)
  bool _partyListenLogged = false;

  // Hoodie pulse (hero CTA)
  late final AnimationController _hoodiePulseCtrl;
  late final Animation<double> _hoodiePulse; // 1.0 → 1.05

  @override
  void initState() {
    super.initState();
    _loadToastFlag();
    _hoodiePulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..repeat(reverse: true);
    _hoodiePulse = Tween(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _hoodiePulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _hoodiePulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadToastFlag() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _shuffleToastShown = prefs.getBool(_kToastKey) ?? false;
      _prefsLoaded = true;
    });
  }

  Future<void> _markToastShown() async {
    _shuffleToastShown = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kToastKey, true);
  }

  void _onNavTapped(int index) {
    // Account isn't one of the three tab screens; always navigate.
    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WalletScreen()),
      );
    } else if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ColorPickerScreen()),
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DailyScrollScreen()),
      );
    }
  }

  Future<void> _startOrContinueFingerprint({
    required List<int> seed,
    int? focusIndex, // jump to a specific question first
  }) async {
    // If starting fresh (no answers, no focus), show the intro first.
    if (seed.isEmpty && focusIndex == null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FingerprintIntroScreen()),
      );
      // Intro pushes the flow and then pops back; stream will refresh.
      return;
    }

    final result = await Navigator.push<List<int>>(
      context,
      MaterialPageRoute(
        builder:
            (_) =>
                FingerprintFlow(initialAnswers: seed, startAtIndex: focusIndex),
      ),
    );
    if (result != null && mounted) setState(() => _answersLocal = result);
  }

  List<T> _shuffledWithSeed<T>(List<T> input, int seed) {
    final rnd = math.Random(seed);
    final list = List<T>.from(input);
    for (var i = list.length - 1; i > 0; i--) {
      final j = rnd.nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final total = kFingerprintTotal;

    return WillPopScope(
      onWillPop: () async {
        if (Navigator.of(context).canPop()) return true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const DailyScrollScreen(),
          ), // CHANGED
        );
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Fingerprint & Account'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const DailyScrollScreen(), // CHANGED
                  ),
                );
              }
            },
          ),
          actions: const [
            ZenmoMenuButton(isOnWallet: false, isOnColorPicker: false),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, thickness: 1, color: Colors.grey),
          ),
        ),
        body: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: SafeArea(
            child:
                !_prefsLoaded
                    ? const Center(child: CircularProgressIndicator())
                    : StreamBuilder<Map<String, dynamic>>(
                      stream: FingerprintRepo.fingerprintStream(),
                      builder: (context, snap) {
                        final data = snap.data ?? const <String, dynamic>{};

                        List<int> answersFromDb = const <int>[];
                        bool completed = false;
                        int? shuffleSeed;

                        final a = data['answers'];
                        if (a is List) {
                          answersFromDb = a.whereType<int>().toList();
                        }
                        completed = data['completed'] == true;
                        if (data['shuffleSeed'] is int) {
                          shuffleSeed = data['shuffleSeed'] as int;
                        }

                        final answers =
                            (answersFromDb.isNotEmpty)
                                ? answersFromDb
                                : _answersLocal;

                        if (completed && !_shuffleToastShown && mounted) {
                          WidgetsBinding.instance.addPostFrameCallback((
                            _,
                          ) async {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Your fingerprint is complete. Auto-shuffled.',
                                ),
                              ),
                            );
                            await _markToastShown();
                          });
                        }

                        final answered = answers.length.clamp(0, total);
                        final done = completed && answered >= total;

                        // Display colors (shuffled if done)
                        final displayAnswers =
                            (done && shuffleSeed != null)
                                ? _shuffledWithSeed<int>(answers, shuffleSeed)
                                : answers;

                        // Map from displayed list index -> original question index.
                        final List<int> indexMap =
                            (done && shuffleSeed != null)
                                ? _shuffledWithSeed<int>(
                                  List<int>.generate(answers.length, (i) => i),
                                  shuffleSeed,
                                )
                                : List<int>.generate(answers.length, (i) => i);

                        final buttonLabel =
                            done
                                ? 'Redo'
                                : (answered > 0 ? 'Continue' : 'Create');

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                          children: [
                            const SizedBox(height: 12),

                            // ✅ PARTY FINGERPRINT (added, minimal)
                            _buildPartyInlineSection(context),
                            const SizedBox(height: 24),

                            const Text(
                              'Your Color Fingerprint',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),

                            AspectRatio(
                              aspectRatio: 1,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  FingerprintGrid(
                                    answers: displayAnswers,
                                    total: total,
                                    borderColor: Colors.transparent,
                                    borderWidth: 0,
                                    cornerRadius: 8,
                                    gap: 0,
                                    forceCols: 5, // 5x5
                                    placementOrder: _spiral5x5,
                                    onTileTap: (cell, answerIndex) {
                                      if (answerIndex != null) {
                                        final int focus =
                                            (answerIndex >= 0 &&
                                                    answerIndex <
                                                        indexMap.length)
                                                ? indexMap[answerIndex]
                                                : answerIndex;
                                        _startOrContinueFingerprint(
                                          seed: answers,
                                          focusIndex: focus,
                                        );
                                      } else {
                                        _startOrContinueFingerprint(
                                          seed: answers,
                                        );
                                      }
                                    },
                                  ),
                                  if (!done)
                                    ElevatedButton(
                                      onPressed: () {
                                        _startOrContinueFingerprint(
                                          seed: answers,
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF5F6572,
                                        ),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 10,
                                        ),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
                                      child: Text(buttonLabel),
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 8),
                            Text(
                              done
                                  ? 'Complete • $total / $total'
                                  : 'Progress • $answered / $total',
                              style: const TextStyle(color: Colors.black54),
                            ),

                            // HERO: Hoodie big + pulsing (LEFT, Expanded), Redo small RIGHT (no pulse)
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                // LEFT — HERO hoodie CTA (Expanded + pulsing)
                                Expanded(
                                  child: DecoratedBox(
                                    decoration: const BoxDecoration(
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0x333A006A),
                                          blurRadius: 14,
                                          spreadRadius: 1,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: ScaleTransition(
                                      scale: _hoodiePulse,
                                      child: ElevatedButton(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (_) => KeepsakeOptionsScreen(
                                                    selectedColor: Colors.white,
                                                    title:
                                                        'Your Color Fingerprint',
                                                    fingerprintAnswers: answers,
                                                    fingerprintTotal: total,
                                                    fingerprintShuffleSeed:
                                                        shuffleSeed,
                                                    fingerprintCompleted: done,
                                                  ),
                                            ),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF3A006A,
                                          ),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 12,
                                          ),
                                          minimumSize: const Size(0, 44),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          elevation: 0,
                                        ),
                                        child: const Text('Fingerprint hoodie'),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // RIGHT — Redo (small, static)
                                FingerprintRedoButton(
                                  label: 'Redo fingerprint',
                                  answersProvider: () async {
                                    final List<int> current = answers;
                                    final int totalCount = total;
                                    return {
                                      'answers': current,
                                      'total': totalCount,
                                    };
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Note text — "Next available — DATE"
                            const FingerprintMonthlyNote(),

                            const SizedBox(height: 24),
                            const Text(
                              'Other User Settings (coming soon)',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const _BulletList(
                              items: [
                                'your name',
                                'password',
                                'credit card / billing info',
                                'default shipping address',
                              ],
                            ),
                          ],
                        );
                      },
                    ),
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onNavTapped,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
          items: const [
            BottomNavigationBarItem(icon: WalletBadgeIcon(), label: 'Wallet'),
            BottomNavigationBarItem(
              icon: Icon(Icons.brush),
              label: 'Send Vibes',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded),
              label: 'Daily Hues',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartyInlineSection(BuildContext context) {
    if (!_partyListenLogged) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        debugPrint('PF LISTEN -> users/$uid/private/partyFingerprint');
        _partyListenLogged = true;
      }
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: PartyFingerprintRepo.watch(),
      builder: (context, snap) {
        // Avoid a confusing "No party grid yet" flash while the first snapshot
        // is still loading (common right after login / cold start).
        final isLoading =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;

        if (snap.hasError) {
          debugPrint('PF SNAP error: ${snap.error}');
        }

        final data = snap.data?.data();
        final completed = (data?['completed'] == true);

        final rawAnswers = data?['answers'];
        final answers = <Map<String, dynamic>>[];
        if (rawAnswers is List) {
          for (final e in rawAnswers) {
            if (e is Map) {
              answers.add(Map<String, dynamic>.from(e as Map));
            }
          }
        }

        final colors = <int>[];
        final promptSummaries = <Map<String, dynamic>>[];

        // Each answer has `title` and either `colors: List<int>` (up to 5)
        // or legacy `colorInt` (single color).
        for (final m in answers.take(5)) {
          final title = (m['title'] ?? '') as String;

          final promptColors = <int>[];
          final cList = m['colors'];
          if (cList is List) {
            for (final v in cList) {
              if (v is int) {
                promptColors.add(v);
              } else if (v is num) {
                promptColors.add(v.toInt());
              }
            }
          } else {
            final v = m['colorInt'];
            if (v is int) {
              promptColors.add(v);
            } else if (v is num) {
              promptColors.add(v.toInt());
            }
          }

          // Keep the 5x5 grid fill behavior (up to 25 cells).
          for (final v in promptColors) {
            colors.add(v);
            if (colors.length >= 25) break;
          }

          final hasAnything =
              title.trim().isNotEmpty || promptColors.isNotEmpty;
          promptSummaries.add(<String, dynamic>{
            'title': title,
            'colors': promptColors,
            'hasAnything': hasAnything,
          });

          if (colors.length >= 25) break;
        }

        final answeredCount = promptSummaries
            .where((m) => m['hasAnything'] == true)
            .length
            .clamp(0, 5);
        final hasAnyProgress = answeredCount > 0;
        final hasFull = completed == true;
        final statusText =
            hasAnyProgress
                ? 'Party progress • $answeredCount / 5'
                : 'No party grid yet.';
        final actionText =
            hasFull
                ? 'Redo Party Qs'
                : (hasAnyProgress ? 'Continue' : 'Party Qs');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Party Fingerprint',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (snap.hasError)
              const Text('Could not load party fingerprint.')
            else if (isLoading)
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Loading party fingerprint…'),
                ],
              )
            else if (!hasAnyProgress)
              Row(
                children: [
                  Expanded(child: Text(statusText)),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => PartyFingerprintIntroScreen(
                                startFresh: hasFull,
                              ),
                        ),
                      );
                    },
                    child: Text(actionText),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: FingerprintGrid(
                      // Partial progress is OK: the grid will fill the first N cells.
                      answers: colors,
                      total: 25,
                      borderColor: Colors.transparent,
                      borderWidth: 0,
                      cornerRadius: 8,
                      gap: 0,
                      forceCols: 5,
                      placementOrder: _spiral5x5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < promptSummaries.length; i++)
                        if (promptSummaries[i]['hasAnything'] == true)
                          Builder(
                            builder: (_) {
                              final m = promptSummaries[i];
                              final title = (m['title'] ?? '') as String;
                              final cols = (m['colors'] as List).cast<int>();

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Prompt ${i + 1}: ${title.isEmpty ? '—' : title}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final v in cols)
                                          Container(
                                            width: 18,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              color: Color(v).withAlpha(0xFF),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: const Color(0x33000000),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(child: Text(statusText)),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => PartyFingerprintIntroScreen(
                                    startFresh: hasFull,
                                  ),
                            ),
                          );
                        },
                        child: Text(actionText),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  /// Center-out spiral order (row-major cell indices).
  static List<int> _centerOutSpiral({required int rows, required int cols}) {
    final total = rows * cols;
    final List<int> order = [];
    int r = rows ~/ 2, c = cols ~/ 2; // start at center
    order.add(r * cols + c);

    int step = 1;
    final dirs = <List<int>>[
      [1, 0], // right
      [0, 1], // down
      [-1, 0], // left
      [0, -1], // up
    ];
    int d = 0;

    while (order.length < total) {
      for (int rep = 0; rep < 2; rep++) {
        final dx = dirs[d % 4][0];
        final dy = dirs[d % 4][1];
        for (int s = 0; s < step; s++) {
          c += dx;
          r += dy;
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
}

class _BulletList extends StatelessWidget {
  final List<String> items;
  const _BulletList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          items
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(fontSize: 20, height: 1.4),
                      ),
                      Expanded(
                        child: Text(
                          item,
                          style: const TextStyle(fontSize: 15, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }
}
