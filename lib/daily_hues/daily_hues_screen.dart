import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:color_wallet/menu.dart';
import 'dart:async' show TimeoutException; // <-- TEMP: for timeouts

import '../models/daily_grid_tile.dart';
import '../services/analytics.dart';
import '../services/daily_clock.dart';
import '../services/daily_grid_composer.dart';

// Repos
import '../services/answer_repository.dart';
import '../services/question_repository.dart';
import '../services/firestore/answer_repository_firestore.dart';
import '../services/firestore/question_repository_firestore.dart';
import '../services/public_feed_repository.dart'; // PublicFeedItem/getForDay

// Models
import '../models/answer.dart';
import '../models/question.dart';

// Screens & UI
import 'answer_question_screen.dart';
import 'daily_scroll_screen.dart';
import 'create_prompt_screen.dart';
import '../color_picker_screen.dart';
import '../wallet_screen.dart';
import 'package:color_wallet/widgets/wallet_badge_icon.dart';

class DailyHuesScreen extends StatefulWidget {
  const DailyHuesScreen({super.key});
  static const routeName = '/dailyHues';

  @override
  State<DailyHuesScreen> createState() => _DailyHuesScreenState();
}

class _DailyHuesScreenState extends State<DailyHuesScreen> {
  final _clock = DailyClock();
  final _composer = const DailyGridComposer();

  late final AnswerRepository _answersRepo;
  late final QuestionRepository _questionsRepo;
  late final PublicFeedRepository _publicRepo;

  String? _localDay; // YYYY-MM-DD
  bool _loading = true;
  bool _archiveReady = false; // mount Archive after first paint
  List<DailyGridTile> _tiles = const [];

  // Staged loading: keep the latest feed to inject early
  List<PublicFeedItem> _latestFeed = const [];

  // ---- TEMP DIAGNOSTICS ----
  static const Duration _stageTimeout = Duration(seconds: 12);
  Future<T> _debugAwait<T>(String label, Future<T> f) async {
    _log('await<$label>: start');
    try {
      final r = await f.timeout(_stageTimeout);
      _log('await<$label>: ok');
      return r;
    } on TimeoutException {
      _log('await<$label>: TIMEOUT after ${_stageTimeout.inSeconds}s');
      rethrow;
    } catch (e, st) {
      _log('await<$label>: ERROR $e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }
  // --------------------------

  void _log(String msg) => debugPrint('[DailyHues] $msg');

  String _todayLocal() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  void initState() {
    super.initState();
    _log('initState');
    AnalyticsService.logEvent('daily_view_grid');

    final db = FirebaseFirestore.instance;
    _answersRepo = AnswerRepositoryFirestore(firestore: db);
    _questionsRepo = QuestionRepositoryFirestore(firestore: db);
    _publicRepo = PublicFeedRepositoryFirestore(firestore: db);
    _log('Repo=Firestore');

    // Set day synchronously so first build can paint the grid immediately
    final initialDay = _todayLocal();
    _localDay = initialDay;
    _load(initialDay);

    // Stream updates for day changes
    _clock.dayStream.listen(
      (day) {
        _log('dayStream emit: $day');
        if (!mounted) return;
        if (day == _localDay) return;
        setState(() => _localDay = day);
        _load(day);
      },
      onError: (e, st) {
        _log('dayStream ERROR: $e');
        debugPrintStack(stackTrace: st);
      },
    );
    _clock.start();

    // Defer heavy Archive widget until after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _archiveReady = true);
    });
  }

  Future<void> _load(String localDay) async {
    _log('Load begin for day=$localDay');
    if (!mounted) return;

    // Stage 0: immediately show fillers (ensures instant grid paint)
    setState(() {
      _loading = true;
      _tiles = List<DailyGridTile>.generate(49, (_) => DailyGridTile.filler());
      _latestFeed = const [];
    });

    // Kick off requests (with timeouts + logging)
    _log('kick<answers>');
    final answersF = _answersRepo
        .getAnswersForDay(localDay)
        .timeout(
          _stageTimeout,
          onTimeout: () {
            throw TimeoutException('answers getAnswersForDay timeout');
          },
        );

    _log('kick<questions>');
    final questionsF = _questionsRepo
        .getQuestionsForDay(localDay)
        .timeout(
          _stageTimeout,
          onTimeout: () {
            throw TimeoutException('questions getQuestionsForDay timeout');
          },
        );

    _log('kick<feed>');
    final feedF = _publicRepo
        .getForDay(localDay)
        .timeout(
          _stageTimeout,
          onTimeout: () {
            throw TimeoutException('feed getForDay timeout');
          },
        );

    // Stage 1: early FEED injection
    feedF
        .then((feed) {
          _log('early<feed>: ok len=${feed.length}');
          if (!mounted) return;
          _latestFeed = feed;
          final feedTiles =
              feed
                  .map(
                    (f) => DailyGridTile.color(
                      id: f.id, // <-- this id is what we’ll use to jump
                      colorHex: f.colorHex,
                    ),
                  )
                  .toList();

          final mergedEarly = _injectColorsIntoFillers(
            base: _tiles,
            colors: feedTiles,
            capacity: 49,
          );
          setState(() {
            _tiles = mergedEarly;
            // keep _loading true until base is composed
          });
        })
        .catchError((e, st) {
          _log('early<feed>: ERROR $e');
        });

    try {
      // Stage 2 (final): await all with labeled logs
      final results = await Future.wait([
        _debugAwait('answers', answersF),
        _debugAwait('questions', questionsF),
        _debugAwait('feed-final', feedF.catchError((_) => _latestFeed)),
      ]);

      final answers = results[0] as List<Answer>;
      final questions = results[1] as List<Question>;
      final feed = (results[2] as List<PublicFeedItem>?) ?? _latestFeed;
      _log(
        'compose: answers=${answers.length}, questions=${questions.length}, feed=${feed.length}',
      );

      // Compose base grid (questions + answers)
      final base = _composer.compose(
        answers: answers,
        questions: questions,
        minTilesTarget: 49,
        showFillers: true,
      );

      // Inject feed colors over fillers (final pass)
      final feedTiles =
          feed
              .map((f) => DailyGridTile.color(id: f.id, colorHex: f.colorHex))
              .toList();

      final mergedFinal = _injectColorsIntoFillers(
        base: base,
        colors: feedTiles,
        capacity: 49,
      );

      if (!mounted) return;
      setState(() {
        _tiles = mergedFinal;
        _loading = false;
      });
      _log('Load end (success) for day=$localDay');
    } on TimeoutException catch (e) {
      _log('TIMEOUT in _load: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Daily Hues timeout: ${e.message ?? e.toString()}'),
        ),
      );
    } catch (e, st) {
      _log('ERROR in _load: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load Daily Hues: $e')));
    }
  }

  // Replace grey fillers left→right with feed colors; cap at capacity.
  List<DailyGridTile> _injectColorsIntoFillers({
    required List<DailyGridTile> base,
    required List<DailyGridTile> colors,
    required int capacity,
  }) {
    if (colors.isEmpty) return base.take(capacity).toList();

    // Ensure base has at least capacity items
    final working = <DailyGridTile>[];
    for (var i = 0; i < capacity; i++) {
      working.add(i < base.length ? base[i] : DailyGridTile.filler());
    }

    var ci = 0;
    for (var i = 0; i < working.length && ci < colors.length; i++) {
      if (working[i].type == DailyGridTileType.filler) {
        working[i] = colors[ci++];
      }
    }
    return working;
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  // ---------- Day nav ----------
  void _goToRelativeDay(int deltaDays) {
    final d = _localDay ?? _todayLocal();
    final parts = d.split('-');
    final base = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    ).add(Duration(days: deltaDays));
    final y = base.year.toString().padLeft(4, '0');
    final m = base.month.toString().padLeft(2, '0');
    final dd = base.day.toString().padLeft(2, '0');
    final next = '$y-$m-$dd';
    setState(() => _localDay = next);
    _load(next);
  }

  String _formattedLongDate(String ymd) {
    final p = ymd.split('-');
    final dt = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    final loc = MaterialLocalizations.of(context);
    return loc.formatFullDate(dt);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      // Headline
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(
          'Hues of the Day',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),

      // 7x7 mosaic
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE7E4EC)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const rows = 7;
              const cols = 7;

              final cellSize = constraints.maxWidth / cols;
              final gridHeight = cellSize * rows;

              final tiles =
                  _tiles.isEmpty
                      ? List<DailyGridTile>.generate(
                        49,
                        (_) => DailyGridTile.filler(),
                      )
                      : _tiles;

              return SizedBox(
                height: gridHeight,
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: _CheckerboardBackground(
                        rows: rows,
                        cols: cols,
                        light: Color(0xFFF2F3F5),
                        dark: Color(0xFFE5E7EB),
                      ),
                    ),
                    GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: rows * cols,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 0,
                            crossAxisSpacing: 0,
                            childAspectRatio: 1,
                          ),
                      itemBuilder: (context, index) {
                        final tile =
                            index < tiles.length
                                ? tiles[index]
                                : DailyGridTile.filler();

                        return _TileView(
                          tile: tile,
                          onTap: () async {
                            switch (tile.type) {
                              case DailyGridTileType.color:
                                AnalyticsService.logEvent(
                                  'tile_tap_color',
                                  parameters: {'id': tile.id ?? ''},
                                );
                                if (!mounted) return;
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder:
                                        (_) => DailyScrollScreen(
                                          // local YYYY-MM-DD for this grid
                                          initialDay: _localDay,
                                          // target this specific swatch in scroll
                                          initialFeedId: tile.id,
                                        ),
                                  ),
                                );
                                break;

                              case DailyGridTileType.question:
                                AnalyticsService.logEvent(
                                  'tile_tap_question',
                                  parameters: {'id': tile.id ?? ''},
                                );
                                if (!mounted) return;
                                final id = tile.id ?? '';
                                if (id.isEmpty) return;
                                final result = await Navigator.of(
                                  context,
                                ).push<Map<String, dynamic>?>(
                                  MaterialPageRoute(
                                    builder:
                                        (_) => AnswerQuestionScreen(
                                          questionId: id,
                                        ),
                                  ),
                                );
                                if (result != null && _localDay != null) {
                                  _load(_localDay!);
                                }
                                break;

                              case DailyGridTileType.filler:
                                break;
                            }
                          },
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),

      // Date strip with chevrons
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous day',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _goToRelativeDay(-1),
            ),
            Expanded(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F1F4),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text(
                    _localDay == null ? '' : _formattedLongDate(_localDay!),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next day',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _goToRelativeDay(1),
            ),
          ],
        ),
      ),

      // Helper copy
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          'Each of these colors was sent or received by your fellow Zenmo users today. '
          '? tiles are mini-questions.',
          style: TextStyle(color: Colors.black87),
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          'Tap a color to jump into Todays Scroll. Some colors may reappear from recent days; big news travels.',
          style: TextStyle(color: Colors.black54),
        ),
      ),

      // Bottom primary
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Center(
          child: SizedBox(
            width: 280,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE9E4FF),
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () async {
                final posted = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const CreatePromptScreen()),
                );
                if (posted == true && _localDay != null) {
                  _load(_localDay!);
                }
              },
              child: const Text('Add a Question'),
            ),
          ),
        ),
      ),

      // === Monthly Archive ===
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(
          'Archive',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      if (_archiveReady)
        _MonthlyArchive(
          answersRepo: _answersRepo,
          questionsRepo: _questionsRepo,
          publicRepo: _publicRepo,
          composer: _composer,
          monthCount: 2,
        )
      else
        const SizedBox(height: 8),

      const SizedBox(height: 8),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFBF6FB),
      appBar: AppBar(
        title: const Text('Daily Hues'),
        centerTitle: true,
        automaticallyImplyLeading: false, // <- fixed typo
        actions: const [
          ZenmoMenuButton(isOnWallet: false, isOnColorPicker: false),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Colors.black12),
        ),
      ),
      body: SafeArea(
        child: ListView(padding: EdgeInsets.zero, children: children),
      ),
      bottomNavigationBar: _BottomNav(
        onTap: (i) {
          if (i == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const WalletScreen()),
            );
          } else if (i == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ColorPickerScreen()),
            );
          } else if (i == 2) {
            // already on Daily Hues
          }
        },
      ),
    );
  }
}

class _TileView extends StatelessWidget {
  const _TileView({required this.tile, required this.onTap});
  final DailyGridTile tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    switch (tile.type) {
      case DailyGridTileType.color:
        final hex = tile.colorHex ?? '#000000';
        final color = _hexToColor(hex);
        return InkWell(onTap: onTap, child: ColoredBox(color: color));

      case DailyGridTileType.question:
        return InkWell(
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: const Text(
              '?',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ),
        );

      case DailyGridTileType.filler:
        return const ColoredBox(color: Colors.transparent);
    }
  }

  Color _hexToColor(String hex) {
    final s = hex.replaceAll('#', '');
    final v = int.tryParse(s, radix: 16) ?? 0;
    final argb = s.length == 8 ? v : (0xFF000000 | v);
    return Color(argb);
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.onTap});
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 2,
      onTap: onTap,
      items: const [
        BottomNavigationBarItem(icon: WalletBadgeIcon(), label: 'Wallet'),
        BottomNavigationBarItem(icon: Icon(Icons.brush), label: 'Send Vibes'),
        BottomNavigationBarItem(
          icon: Icon(Icons.grid_view_rounded),
          label: 'Daily Hues',
        ),
      ],
    );
  }
}

/* ===========================
   Monthly Archive
   - Month headers (reverse-chronological)
   - Grid of day thumbnails
   - Each thumbnail is a 7x7 mosaic, no tap action
   =========================== */

class _MonthlyArchive extends StatelessWidget {
  const _MonthlyArchive({
    required this.answersRepo,
    required this.questionsRepo,
    required this.publicRepo,
    required this.composer,
    this.monthCount = 2,
  });

  final AnswerRepository answersRepo;
  final QuestionRepository questionsRepo;
  final PublicFeedRepository publicRepo;
  final DailyGridComposer composer;
  final int monthCount;

  List<DateTime> _monthStarts(int count) {
    final now = DateTime.now();
    final firstOfThisMonth = DateTime(now.year, now.month, 1);
    return List<DateTime>.generate(
      count,
      (i) => DateTime(firstOfThisMonth.year, firstOfThisMonth.month - i, 1),
    );
  }

  String _monthLabel(BuildContext ctx, DateTime monthStart) {
    final loc = MaterialLocalizations.of(ctx);
    return loc.formatMonthYear(monthStart);
  }

  List<String> _daysInMonthYMD(DateTime monthStart) {
    final nextMonth = DateTime(monthStart.year, monthStart.month + 1, 1);
    final lastDayOfMonth = nextMonth.subtract(const Duration(days: 1));

    // Clamp to "today" if we're building the current month.
    final now = DateTime.now();
    final isCurrentMonth =
        (monthStart.year == now.year && monthStart.month == now.month);
    final lastDayToShow = isCurrentMonth ? now.day : lastDayOfMonth.day;

    final days = <String>[];
    for (int d = lastDayToShow; d >= 1; d--) {
      final y = monthStart.year.toString().padLeft(4, '0');
      final m = monthStart.month.toString().padLeft(2, '0');
      final dd = d.toString().padLeft(2, '0');
      days.add('$y-$m-$dd');
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final months = _monthStarts(monthCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final monthStart in months) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              _monthLabel(context, monthStart),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          _MonthGrid(
            ymdDays: _daysInMonthYMD(monthStart),
            answersRepo: answersRepo,
            questionsRepo: questionsRepo,
            publicRepo: publicRepo,
            composer: composer,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.ymdDays,
    required this.answersRepo,
    required this.questionsRepo,
    required this.publicRepo,
    required this.composer,
  });

  final List<String> ymdDays; // reverse-chronological within a month
  final AnswerRepository answersRepo;
  final QuestionRepository questionsRepo;
  final PublicFeedRepository publicRepo;
  final DailyGridComposer composer;

  @override
  Widget build(BuildContext context) {
    // Compact tiles: 3 per row on phones
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // modest cache extent so only first rows mount immediately
        cacheExtent: 400,
        itemCount: ymdDays.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 12,
          childAspectRatio: 1, // square thumbnails
        ),
        itemBuilder: (context, i) {
          final dayId = ymdDays[i];
          return RepaintBoundary(
            child: _DayThumbnail(
              key: ValueKey(dayId), // stable identity for keep-alive
              dayId: dayId,
              answersRepo: answersRepo,
              questionsRepo: questionsRepo,
              publicRepo: publicRepo,
              composer: composer,
            ),
          );
        },
      ),
    );
  }
}

class _DayThumbnail extends StatefulWidget {
  const _DayThumbnail({
    required this.dayId,
    required this.answersRepo,
    required this.questionsRepo,
    required this.publicRepo,
    required this.composer,
    super.key,
  });

  final String dayId;
  final AnswerRepository answersRepo;
  final QuestionRepository questionsRepo;
  final PublicFeedRepository publicRepo;
  final DailyGridComposer composer;

  @override
  State<_DayThumbnail> createState() => _DayThumbnailState();
}

class _DayThumbnailState extends State<_DayThumbnail>
    with AutomaticKeepAliveClientMixin<_DayThumbnail> {
  static final Map<String, List<DailyGridTile>> _cache = {};

  // ---- simple global throttle for archive loads ----
  static const int _maxConcurrent = 4;
  static int _activeLoads = 0;
  static final List<_DayThumbnailState> _waitQueue = <_DayThumbnailState>[];
  static void _pumpQueue() {
    while (_activeLoads < _maxConcurrent && _waitQueue.isNotEmpty) {
      final s = _waitQueue.removeAt(0);
      if (!s.mounted) continue;
      _activeLoads++;
      s._doLoad().whenComplete(() {
        _activeLoads = (_activeLoads - 1).clamp(0, _maxConcurrent);
        _pumpQueue();
      });
    }
  }

  void _scheduleLoad() {
    _waitQueue.add(this);
    _pumpQueue();
  }
  // --------------------------------------------------

  List<DailyGridTile>? _tiles;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final cached = _cache[widget.dayId];
    if (cached != null) {
      _tiles = cached;
      _loading = false;
    } else {
      // Paint immediate fillers; queue the network fetch after first frame.
      _tiles = List<DailyGridTile>.generate(49, (_) => DailyGridTile.filler());
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleLoad();
      });
    }
  }

  Future<void> _doLoad() async {
    try {
      // Fetch FEED + QUESTIONS concurrently (answers not needed in thumbnails)
      final results = await Future.wait([
        widget.publicRepo.getForDay(widget.dayId),
        widget.questionsRepo.getQuestionsForDay(widget.dayId),
      ]);

      final feed = results[0] as List<PublicFeedItem>;
      final questions = results[1] as List<Question>;

      // Base from questions => adds '?' tiles where applicable
      final base = widget.composer.compose(
        answers: const <Answer>[],
        questions: questions,
        minTilesTarget: 49,
        showFillers: true,
      );

      // Overlay feed colors into fillers
      final feedTiles =
          feed
              .map((f) => DailyGridTile.color(id: f.id, colorHex: f.colorHex))
              .toList();

      final merged = _injectColorsIntoFillers(
        base: base,
        colors: feedTiles,
        capacity: 49, // 7x7
      );

      if (!mounted) return;
      _cache[widget.dayId] = merged;
      setState(() {
        _tiles = merged;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // Backward compatibility: _load() kept for readability
  Future<void> _load() => _doLoad();

  List<DailyGridTile> _injectColorsIntoFillers({
    required List<DailyGridTile> base,
    required List<DailyGridTile> colors,
    required int capacity,
  }) {
    if (colors.isEmpty) return base.take(capacity).toList();

    final result = <DailyGridTile>[];
    var ci = 0;

    for (final t in base) {
      if (result.length >= capacity) break;
      if (t.type == DailyGridTileType.filler && ci < colors.length) {
        result.add(colors[ci++]);
      } else {
        result.add(t);
      }
    }

    while (result.length < capacity && ci < colors.length) {
      result.add(colors[ci++]);
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required with keep-alive mixin

    // Card with square 7x7 mosaic and a subtle outline
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE7E4EC)),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.all(2),
        child: LayoutBuilder(
          builder: (context, c) {
            const rows = 7;
            const cols = 7;

            final tiles =
                _tiles ??
                List<DailyGridTile>.generate(49, (_) => DailyGridTile.filler());

            return GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: rows * cols,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 0,
                crossAxisSpacing: 0,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, i) {
                final tile =
                    i < tiles.length ? tiles[i] : DailyGridTile.filler();
                return _MiniTile(tile: tile);
              },
            );
          },
        ),
      ),
    );
  }
}

class _MiniTile extends StatelessWidget {
  const _MiniTile({required this.tile});
  final DailyGridTile tile;

  @override
  Widget build(BuildContext context) {
    switch (tile.type) {
      case DailyGridTileType.color:
        final hex = tile.colorHex ?? '#000000';
        return ColoredBox(color: _hexToColor(hex));
      case DailyGridTileType.question:
        // Small question box: grey border, white fill, tiny '?'
        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: const FittedBox(
            child: Text('?', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        );
      case DailyGridTileType.filler:
        // Keep simple grey in thumbnails; main grid shows checkerboard.
        return const ColoredBox(color: Color(0xFFF1F1F4));
    }
  }

  Color _hexToColor(String hex) {
    final s = hex.replaceAll('#', '');
    final v = int.tryParse(s, radix: 16) ?? 0;
    final argb = s.length == 8 ? v : (0xFF000000 | v);
    return Color(argb);
  }
}

class _CheckerboardBackground extends StatelessWidget {
  const _CheckerboardBackground({
    this.light = const Color(0xFFF2F3F5),
    this.dark = const Color(0xFFE5E7EB),
    this.rows = 7,
    this.cols = 7,
  });

  final Color light;
  final Color dark;
  final int rows;
  final int cols;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckerboardPainter(
        light: light,
        dark: dark,
        rows: rows,
        cols: cols,
      ),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  _CheckerboardPainter({
    required this.light,
    required this.dark,
    required this.rows,
    required this.cols,
  });

  final Color light;
  final Color dark;
  final int rows;
  final int cols;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final lightPaint = Paint()..color = light;
    final darkPaint = Paint()..color = dark;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final isDark = ((r + c) % 2 == 1);
        final paint = isDark ? darkPaint : lightPaint;
        final rect = Rect.fromLTWH(c * cellW, r * cellH, cellW, cellH);
        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter old) {
    return old.light != light ||
        old.dark != dark ||
        old.rows != rows ||
        old.cols != cols;
  }
}
