// lib/daily_scroll_screen.dart
// Daily Scroll: per-day feed + precise jump-to-swatch from Daily Hues

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async' show TimeoutException; // TEMP: prevent silent hangs

import '../services/analytics.dart';
import '../services/daily_clock.dart';

// Repos
import '../services/answer_repository.dart';
import '../services/question_repository.dart';
import '../services/keep_repository.dart';
import '../services/public_feed_repository.dart';
import '../services/firestore/answer_repository_firestore.dart';
import '../services/firestore/question_repository_firestore.dart';
import '../services/firestore/keep_repository_firestore.dart';

// Models
import '../models/answer.dart';
import '../models/question.dart';

import '../services/paged.dart';

// Screens
import 'answer_question_screen.dart';
import 'daily_answers_screen.dart';
import '../lineage_screen.dart'; // NEW: lineage view
import '../wallet_screen.dart'; // NEW: fallback target for back button

class DailyScrollScreen extends StatefulWidget {
  const DailyScrollScreen({
    super.key,
    this.initialDay,
    this.initialUtcDay,
    this.initialFeedId,
  });

  static const routeName = '/dailyScroll';

  /// Legacy local-day ("YYYY-MM-DD") – kept for old links.
  final String? initialDay;

  /// Canonical UTC-day ("YYYY-MM-DD", midnight UTC) – preferred going forward.
  final String? initialUtcDay;

  /// Optional public_feed id to auto-scroll to when opened from Daily Hues grid.
  final String? initialFeedId;

  @override
  State<DailyScrollScreen> createState() => _DailyScrollScreenState();
}

class _DailyScrollScreenState extends State<DailyScrollScreen> {
  // 0 = today (rightmost), 1 = yesterday, etc.
  late final PageController _page;
  late final int _initialIndexFromToday;
  late final String _startLocalDay;
  int _index = 0;

  bool _overlayVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logEvent('daily_view_scroll');

    // Resolve start local day from UTC-first, then legacy, then today
    final startDay = _resolveInitialLocalDay(
      widget.initialUtcDay,
      widget.initialDay,
    );
    _startLocalDay = startDay;

    _initialIndexFromToday = _offsetFromToday(startDay);
    _index = _initialIndexFromToday;
    _page = PageController(initialPage: _initialIndexFromToday);

    _showOverlayTemporarily();
  }

  /// Prefer UTC param if provided ("YYYY-MM-DD" at 00:00:00Z), convert to local YYYY-MM-DD.
  /// Else use legacy local param, else today's local day from DailyClock.
  String _resolveInitialLocalDay(
    String? initialUtcDay,
    String? legacyLocalDay,
  ) {
    if (initialUtcDay != null && initialUtcDay.isNotEmpty) {
      try {
        final utc = DateTime.parse('${initialUtcDay}T00:00:00Z');
        final local = utc.toLocal();
        String two(int v) => v.toString().padLeft(2, '0');
        return '${local.year}-${two(local.month)}-${two(local.day)}';
      } catch (_) {
        // fall through
      }
    }
    if (legacyLocalDay != null && legacyLocalDay.isNotEmpty) {
      return legacyLocalDay;
    }
    return DailyClock().localDay;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _page.dispose();
    super.dispose();
  }

  int _offsetFromToday(String dayId) {
    final base = DailyClock().localDay; // today in local tz
    final a = DateTime.parse(base);
    final b = DateTime.parse(dayId);
    // Use date-only to avoid tz/time noise
    return DateUtils.dateOnly(a).difference(DateUtils.dateOnly(b)).inDays;
  }

  void _showOverlayTemporarily() {
    setState(() => _overlayVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  // Build YYYY-MM-DD from DailyClock local day, then apply offset
  String _dayForOffset(int offsetDays) {
    final baseDay = DailyClock().localDay; // e.g., '2025-10-09'
    final parts = baseDay.split('-');
    final base = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    ).subtract(const Duration(days: 1)).add(Duration(days: 1 - offsetDays));
    // ^ keep same effect as original logic: base - offset
    final y = base.year.toString().padLeft(4, '0');
    final m = base.month.toString().padLeft(2, '0');
    final d = base.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Convert a local YYYY-MM-DD to canonical UTC-day key YYYY-MM-DD (midnight UTC).
  String _toUtcDayFromLocal(String localYmd) {
    final local = DateTime.parse(localYmd); // local midnight
    final utc = DateTime(local.year, local.month, local.day).toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final title =
        _index <= 1
            ? (_index == 0 ? 'Today’s Scroll' : 'Yesterday’s Scroll')
            : (() {
              final dayId = _dayForOffset(_index);
              final dt = DateTime.parse(dayId);
              final weekday = DateFormat('EEE').format(dt); // e.g., Thu
              final pretty = DateFormat('d MMM yyyy').format(dt); // 3 Oct 2025
              return '$weekday • $pretty';
            })();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(title, style: const TextStyle(color: Colors.black)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          tooltip: 'Back',
          onPressed: () {
            // Pop if possible; otherwise return to Wallet.
            final nav = Navigator.of(context, rootNavigator: false);
            if (nav.canPop()) {
              nav.pop();
              return;
            }
            final root = Navigator.of(context, rootNavigator: true);
            if (root.canPop()) {
              root.pop();
              return;
            }
            nav.pushReplacement(
              MaterialPageRoute(builder: (_) => const WalletScreen()),
            );
          },
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Colors.black26),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => _showOverlayTemporarily(),
              onPanDown: (_) => _showOverlayTemporarily(),
              onHorizontalDragStart: (_) => _showOverlayTemporarily(),
              child: PageView.builder(
                controller: _page,
                physics: const PageScrollPhysics(),
                // Older days come from the LEFT (reverse = true).
                reverse: true,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  _showOverlayTemporarily();
                },
                itemCount: 365, // 1 year
                itemBuilder: (context, i) {
                  final dayId = _dayForOffset(i); // local YYYY-MM-DD
                  return _DailyScrollDayView(
                    key: PageStorageKey<String>('daily_scroll_$dayId'),
                    dayId: dayId,
                    // Only the starting day gets the initialFeedId
                    initialFeedId:
                        (widget.initialFeedId != null &&
                                dayId == _startLocalDay)
                            ? widget.initialFeedId
                            : null,
                  );
                },
              ),
            ),

            // very thin edge swipe strips (optional)
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // LEFT edge  (tap/drag — past)
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (d) {
                      // With reverse: true, going to PAST should still advance index (+1)
                      if (d.primaryDelta != null &&
                          d.primaryDelta! < -12 &&
                          _index < 364) {
                        _page.animateToPage(
                          (_index + 1).clamp(0, 364), // past
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    child: const SizedBox(width: 24, height: double.infinity),
                  ),
                  // RIGHT edge (tap/drag — future/toward today)
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (d) {
                      if (d.primaryDelta != null &&
                          d.primaryDelta! > 12 &&
                          _index > 0) {
                        _page.animateToPage(
                          (_index - 1).clamp(0, 364), // future
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    child: const SizedBox(width: 24, height: double.infinity),
                  ),
                ],
              ),
            ),

            // overlay chevrons (auto-hide)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_overlayVisible,
                child: AnimatedOpacity(
                  opacity: _overlayVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SideChevron(
                        alignment: Alignment.centerLeft,
                        rotationRadians: math.pi / 2, // (left)
                        enabled: _index < 364,
                        onPressed: () {
                          _page.animateToPage(
                            (_index + 1).clamp(0, 364), // past
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                          );
                        },
                      ),
                      _SideChevron(
                        alignment: Alignment.centerRight,
                        rotationRadians: -math.pi / 2, // (right)
                        enabled: _index > 0,
                        onPressed: () {
                          _page.animateToPage(
                            (_index - 1).clamp(0, 364), // future/toward today
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                          );
                        },
                      ),
                    ],
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

// ===== Per-day view with GROUPED answers + orphan fallback =====
class _DailyScrollDayView extends StatefulWidget {
  const _DailyScrollDayView({
    super.key,
    required this.dayId,
    this.initialFeedId,
  });

  final String dayId; // local YYYY-MM-DD
  final String? initialFeedId; // public_feed id to auto-scroll to (optional)

  @override
  State<_DailyScrollDayView> createState() => _DailyScrollDayViewState();
}

class _DailyScrollDayViewState extends State<_DailyScrollDayView>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scroll = ScrollController();

  final AnswerRepository _answersRepo = AnswerRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );
  final QuestionRepository _questionsRepo = QuestionRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );
  final KeepRepository _keepRepo = KeepRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );
  final PublicFeedRepository _publicRepo = PublicFeedRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMoreAnswers = true;
  bool _hasMoreQuestions = true;

  DateTime? _ansCursor;
  DateTime? _qCursor;

  // Aggregate then compose — stable grouping when more data arrives
  final List<Answer> _allAnswers = [];
  final List<Question> _allQuestions = [];
  List<PublicFeedItem> _feed = [];

  final List<_Item> _items = [];

  bool _initialJumpScheduled = false;
  final Map<String, GlobalKey> _feedItemKeys = {}; // NEW

  // simple display-name cache like WalletScreen
  final Map<String, String> _userNameCache = {};
  Future<String> _displayNameFor(String? uid) async {
    if (uid == null || uid.isEmpty) return 'Anonymous';
    final cached = _userNameCache[uid];
    if (cached != null) return cached;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final name = (doc.data()?['displayName'] as String?)?.trim();
      final resolved = (name == null || name.isEmpty) ? 'Anonymous' : name;
      _userNameCache[uid] = resolved;
      return resolved;
    } catch (_) {
      return 'Anonymous';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _DailyScrollDayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dayId != widget.dayId) {
      _resetAndReload();
    }
  }

  Future<void> _resetAndReload() async {
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMoreAnswers = true;
      _hasMoreQuestions = true;
      _ansCursor = null;
      _qCursor = null;
      _allAnswers.clear();
      _allQuestions.clear();
      _feed = [];
      _items.clear();
      _feedItemKeys.clear(); // NEW
      _initialJumpScheduled = false;
    });
    await _loadInitial();
    if (mounted) _scroll.jumpTo(0);
  }

  /// Local helper for this state (kept here so references resolve).
  String _toUtcDayFromLocal(String localYmd) {
    final local = DateTime.parse(localYmd);
    final utc = DateTime(local.year, local.month, local.day).toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}';
  }

  Future<void> _loadInitial() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final dayLocal = widget.dayId;
    final dayUtc = _toUtcDayFromLocal(dayLocal); // pass UTC to repos

    // Per-stage hard timeout to avoid silent hangs (12s each).
    const stageTimeout = Duration(seconds: 12);

    try {
      debugPrint('[DailyScroll] loadInitial for local=$dayLocal utc=$dayUtc');

      final results = await Future.wait([
        _answersRepo
            .getAnswersForDayPage(dayUtc, limit: 30)
            .timeout(
              stageTimeout,
              onTimeout: () {
                throw TimeoutException(
                  'answers.getAnswersForDayPage timed out',
                );
              },
            ),
        _questionsRepo
            .getQuestionsForDayPage(dayUtc, limit: 20)
            .timeout(
              stageTimeout,
              onTimeout: () {
                throw TimeoutException(
                  'questions.getQuestionsForDayPage timed out',
                );
              },
            ),
        _publicRepo
            .getForDay(dayLocal)
            .timeout(
              stageTimeout,
              onTimeout: () {
                throw TimeoutException('feed.getForDay timed out');
              },
            ),
      ]);

      final ansPage = results[0] as Paged<Answer>;
      final qPage = results[1] as Paged<Question>;
      final feed = results[2] as List<PublicFeedItem>;

      debugPrint(
        '[DailyScroll] pages: answers=${ansPage.items.length} '
        'questions=${qPage.items.length} feed=${feed.length}',
      );

      _allAnswers
        ..clear()
        ..addAll(ansPage.items);
      _allQuestions
        ..clear()
        ..addAll(qPage.items);
      _feed = feed;

      _ansCursor = ansPage.nextCreatedAtCursor;
      _qCursor = qPage.nextCreatedAtCursor;
      _hasMoreAnswers = ansPage.hasMore;
      _hasMoreQuestions = qPage.hasMore;

      _composeItems();
      if (!mounted) return;
      setState(() => _loading = false);

      // Now that _items is ready, kick an initial jump towards the tapped swatch.
      _scheduleInitialJumpIfNeeded();
    } on TimeoutException catch (e) {
      debugPrint('[DailyScroll] TIMEOUT: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Daily Scroll timed out: ${e.message ?? e.toString()}'),
        ),
      );
    } catch (e, st) {
      debugPrint('[DailyScroll] ERROR: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Daily Scroll failed: $e')));
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore) return;
    if (!_hasMoreAnswers && !_hasMoreQuestions) return;

    setState(() => _loadingMore = true);
    final dayLocal = widget.dayId;
    final dayUtc = _toUtcDayFromLocal(dayLocal); // pass UTC to repos

    final futures = <Future>[];
    Paged<Answer>? ansPage;
    Paged<Question>? qPage;

    if (_hasMoreAnswers) {
      futures.add(
        _answersRepo
            .getAnswersForDayPage(
              dayUtc,
              limit: 30,
              startAfterCreatedAt: _ansCursor,
            )
            .then((p) => ansPage = p),
      );
    }
    if (_hasMoreQuestions) {
      futures.add(
        _questionsRepo
            .getQuestionsForDayPage(
              dayUtc,
              limit: 20,
              startAfterCreatedAt: _qCursor,
            )
            .then((p) => qPage = p),
      );
    }

    await Future.wait(futures);

    if (ansPage != null) {
      _ansCursor = ansPage!.nextCreatedAtCursor;
      _hasMoreAnswers = ansPage!.hasMore;
      _allAnswers.addAll(ansPage!.items);
    }
    if (qPage != null) {
      _qCursor = qPage!.nextCreatedAtCursor;
      _hasMoreQuestions = qPage!.hasMore;
      _allQuestions.addAll(qPage!.items);
    }

    _composeItems();

    setState(() => _loadingMore = false);
  }

  // Build grouped list: QuestionGroup items + Feed items + orphan Answer items; newest-first.
  void _composeItems() {
    final byQ = <String, List<Answer>>{};
    for (final a in _allAnswers) {
      final qid = a.questionId;
      if (qid.isEmpty) continue;
      byQ.putIfAbsent(qid, () => []).add(a);
    }

    final groups = <_Item>[];
    for (final q in _allQuestions) {
      final answers = byQ[q.id] ?? const <Answer>[];
      // treat "activity time" as latest answer (fallback = question createdAt)
      final latest =
          answers.isNotEmpty
              ? answers
                  .map((a) => a.createdAt)
                  .reduce((a, b) => a.isAfter(b) ? a : b)
              : q.createdAt;
      groups.add(_Item.group(question: q, answers: answers, at: latest));
    }

    // FALLBACK: any answers for which we didn't get the question in this page
    final questionIds = _allQuestions.map((q) => q.id).toSet();
    final orphanAnswers =
        _allAnswers.where((a) => !questionIds.contains(a.questionId)).toList();
    final orphanItems = orphanAnswers.map(_Item.answer).toList();

    final feedItems = _feed.map(_Item.feed).toList();

    final merged = <_Item>[...groups, ...orphanItems, ...feedItems]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _items
      ..clear()
      ..addAll(merged);
  }

  Future<void> _answerQuestion(Question q) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(builder: (_) => AnswerQuestionScreen(questionId: q.id)),
    );
    if (result != null) _resetAndReload();
  }

  Future<void> _toggleKeepForFeed(PublicFeedItem f) async {
    try {
      // Prefer canonical root/answer id; resolve once if missing.
      String? targetId =
          (f.rootId != null && f.rootId!.isNotEmpty) ? f.rootId : null;

      if (targetId == null || targetId.isEmpty) {
        // Resolve from public_feed doc id → rootId (don’t keep against public_feed id)
        final snap = await FirebaseFirestore.instance
            .collection('public_feed')
            .doc(f.id)
            .get(const GetOptions(source: Source.server));

        final data = snap.data();
        final resolvedRoot = (data?['rootId'] as String?)?.trim();
        if (snap.exists && resolvedRoot != null && resolvedRoot.isNotEmpty) {
          targetId = resolvedRoot;
        }
      }

      if (targetId == null || targetId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Can’t keep this item (missing root id).'),
          ),
        );
        return;
      }

      // Toggle against the ANSWER/ROOT id. Repo will build keeps/<uid>_<answerId>.
      final kept = await _keepRepo.toggleKeep(targetId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(kept ? 'Kept to Wallet' : 'Removed from Wallet'),
        ),
      );
      setState(() {}); // refresh icon
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Keep failed: $e')));
    }
  }

  /// Scroll so the tapped swatch is precisely aligned at the top
  /// of the scroll viewport (just under the header), once.
  /// Two-step scroll:
  /// 1) jump near the target index so it gets built
  /// 2) then precisely align it at the top of the viewport.
  void _scheduleInitialJumpIfNeeded() {
    if (_initialJumpScheduled) return;
    _initialJumpScheduled = true;

    final targetId = widget.initialFeedId;
    if (targetId == null || targetId.isEmpty) return;
    if (_items.isEmpty) return;

    final targetIndex = _items.indexWhere(
      (item) => item.type == _ItemType.feed && item.feed?.id == targetId,
    );
    if (targetIndex < 0) return;

    // First frame: rough jump by index so the item gets built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;

      final position = _scroll.position;
      final max = position.maxScrollExtent;
      final viewport = position.viewportDimension;
      if (max <= 0) return;

      final avgExtent = (max + viewport) / _items.length;
      final approxOffset = (targetIndex * avgExtent).clamp(0.0, max);

      _scroll.jumpTo(approxOffset);

      // Next frame: now the target tile should exist; align it exactly.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;

        final key = _feedItemKeys[targetId];
        final ctx = key?.currentContext;
        if (ctx == null) return;

        Scrollable.ensureVisible(
          ctx,
          alignment: 0.0, // top of tile at top of list
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      });
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Empty-state message when there's no activity for the day.
    if (!_loading && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No activity today',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.black.withOpacity(0.65),
              letterSpacing: 0.2,
            ),
          ),
        ),
      );
    }

    final body =
        _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
              onRefresh: _resetAndReload,
              child: ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _items.length + (_loadingMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  if (_loadingMore && i == _items.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final item = _items[i];
                  switch (item.type) {
                    case _ItemType.group:
                      return _QuestionGroupCard(
                        dayId: widget.dayId,
                        question: item.question!,
                        answers: item.answers!,
                        displayNameFor: _displayNameFor,
                        onAnswer: () => _answerQuestion(item.question!),
                      );
                    case _ItemType.feed:
                      final feed = item.feed!;
                      final key = _feedItemKeys.putIfAbsent(
                        feed.id,
                        () => GlobalKey(),
                      );
                      return Container(
                        key: key,
                        child: _FeedCard(
                          feed: feed,
                          onToggleKeep: () => _toggleKeepForFeed(feed),
                        ),
                      );

                    case _ItemType.answer:
                      return _AnswerCard(
                        answer: item.answer!,
                        displayNameFor: _displayNameFor,
                      );
                    case _ItemType.question:
                      return const SizedBox.shrink();
                  }
                },
              ),
            );

    return body;
  }

  @override
  bool get wantKeepAlive => true;
}

// ---------- item model ----------
enum _ItemType { answer, question, feed, group }

class _Item {
  final _ItemType type;
  final Answer? answer;
  final Question? question;
  final PublicFeedItem? feed;
  final List<Answer>? answers; // for group
  final DateTime createdAt;

  _Item.answer(Answer a)
    : type = _ItemType.answer,
      answer = a,
      question = null,
      feed = null,
      answers = null,
      createdAt = a.createdAt;

  _Item.question(Question q)
    : type = _ItemType.question,
      answer = null,
      question = q,
      feed = null,
      answers = null,
      createdAt = q.createdAt;

  _Item.feed(PublicFeedItem f)
    : type = _ItemType.feed,
      answer = null,
      question = null,
      feed = f,
      answers = null,
      createdAt = f.sentAt ?? DateTime.now();

  _Item.group({
    required Question question,
    required List<Answer> answers,
    required DateTime at,
  }) : type = _ItemType.group,
       answer = null,
       question = question,
       feed = null,
       answers = answers,
       createdAt = at;
}

// ---------- Grouped Question card (inline, no outer card) ----------
class _QuestionGroupCard extends StatelessWidget {
  final String dayId;
  final Question question;
  final List<Answer> answers;
  final VoidCallback onAnswer;
  final Future<String> Function(String?) displayNameFor;

  const _QuestionGroupCard({
    required this.dayId,
    required this.question,
    required this.answers,
    required this.onAnswer,
    required this.displayNameFor,
  });

  @override
  Widget build(BuildContext context) {
    // Show up to 6 swatches (2 x 3). If more, last cell shows +N overlay.
    final shown = answers.take(6).toList();
    final extra = answers.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 2 x 3 grid of color answers (inline; no outer card)
        LayoutBuilder(
          builder: (context, c) {
            final double w = c.maxWidth;
            final double cell = (w - 2) / 3; // 3 cols with 1px gaps
            return SizedBox(
              height: cell * 2 + 1, // 2 rows + 1px divider
              child: GridView.builder(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 1,
                  mainAxisSpacing: 1,
                  childAspectRatio: 1,
                ),
                itemCount: math.min(shown.length, 6),
                itemBuilder: (_, i) {
                  final a = shown[i];
                  final color = _parseHex(a.colorHex);
                  final isLastShown = (i == shown.length - 1) && extra > 0;
                  return InkWell(
                    onTap: () {
                      final _ = _toUtcDayFromLocal(
                        dayId,
                      ); // kept if needed later
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DailyAnswersScreen(initialDay: dayId),
                          // If/when DailyAnswersScreen accepts UTC explicitly:
                          // builder: (_) => DailyAnswersScreen(initialUtcDay: _),
                        ),
                      );
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: color),
                        if (isLastShown)
                          Container(
                            color: Colors.black.withOpacity(0.25),
                            alignment: Alignment.center,
                            child: Text(
                              '+$extra',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),

        const SizedBox(height: 8),

        // Question banner (tap to answer)
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onAnswer,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E9EF), // light grey fill
                border: Border.all(
                  color: const Color(0xFF9AA0A6), // darker outline
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question.text,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.black,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Show "Color Asker • <display name>"
                  FutureBuilder<String>(
                    future: displayNameFor(question.authorId),
                    builder: (context, snap) {
                      final asker = (snap.data ?? 'Anonymous').trim();
                      return Text(
                        'Color Asker • $asker',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                          letterSpacing: 0.2,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        if (answers.isNotEmpty) ...[
          const Text(
            '{Tap squares above to see answers from others}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.black54,
              letterSpacing: 0.2,
            ),
          ),
        ] else ...[
          GestureDetector(
            onTap: onAnswer,
            child: const Text(
              'Be the first to answer with a color',
              style: TextStyle(
                fontSize: 12,
                color: Colors.black54,
                letterSpacing: 0.2,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Color _parseHex(String hex) {
    final cleaned = hex.replaceAll('#', '');
    final value = int.parse('FF$cleaned', radix: 16);
    return Color(value);
  }

  /// Local helper for this widget scope (avoids reaching up the tree).
  String _toUtcDayFromLocal(String localYmd) {
    final local = DateTime.parse(localYmd);
    final utc = DateTime(local.year, local.month, local.day).toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}';
  }
}

// ---------- Orphan Answer card (shown when question isn’t fetched) ----------
class _AnswerCard extends StatelessWidget {
  final Answer answer;
  final Future<String> Function(String?) displayNameFor;

  const _AnswerCard({required this.answer, required this.displayNameFor});

  /// NEW: Resolve the question’s author and return their display name.
  Future<String> _askerName() async {
    try {
      if (answer.questionId.isEmpty) return 'Anonymous';
      final doc =
          await FirebaseFirestore.instance
              .collection('questions')
              .doc(answer.questionId)
              .get();
      final authorId = doc.data()?['authorId'] as String?;
      return await displayNameFor(authorId);
    } catch (_) {
      return 'Anonymous';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseHex(answer.colorHex);
    final when = DateFormat(
      'MMMM d, y, h:mm a',
    ).format(answer.createdAt.toLocal());

    final String title =
        (answer.title.isEmpty ? answer.colorHex : answer.title).trim();

    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E2E2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // square artwork (fixed)
            AspectRatio(aspectRatio: 1, child: Container(color: color)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<String>(
                    future: displayNameFor(answer.responderId),
                    builder: (context, snap) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              title.isEmpty ? answer.colorHex : title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'ANSWERED: $when',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Responder
                  FutureBuilder<String>(
                    future: displayNameFor(answer.responderId),
                    builder: (context, snap) {
                      final who = (snap.data ?? 'Anonymous').trim();
                      return Text(
                        'BY: $who',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          letterSpacing: 0.2,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 2),
                  // NEW: Question creator / Color Asker
                  FutureBuilder<String>(
                    future: _askerName(),
                    builder: (context, snap) {
                      final asker = (snap.data ?? 'Anonymous').trim();
                      return Text(
                        'COLOR ASKER: $asker',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          letterSpacing: 0.2,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _parseHex(String hex) {
    final cleaned = hex.replaceAll('#', '');
    final value = int.parse('FF$cleaned', radix: 16);
    return Color(value);
  }
}

// ---------- Feed card (square artwork + hex keep + LINEAGE pill) ----------
class _FeedCard extends StatefulWidget {
  final PublicFeedItem feed;
  final Future<void> Function() onToggleKeep; // awaitable

  const _FeedCard({required this.feed, required this.onToggleKeep});

  @override
  State<_FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<_FeedCard> {
  final KeepRepository _keepRepo = KeepRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );

  bool _kept = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _prime();
  }

  Future<void> _prime() async {
    final keepId =
        (widget.feed.rootId != null && widget.feed.rootId!.isNotEmpty)
            ? widget.feed.rootId!
            : widget.feed.id;
    try {
      final k = await _keepRepo.isKept(keepId);
      if (mounted) setState(() => _kept = k);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openLineage() {
    final f = widget.feed;
    final rootId = f.rootId;
    if (rootId == null || rootId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lineage unavailable for this swatch')),
      );
      return;
    }

    final color = _parseHex(f.colorHex);
    final fromName = f.creatorName.isEmpty ? 'Anonymous' : f.creatorName;
    final title = (f.title.isEmpty ? f.colorHex : f.title).trim();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => LineageScreen(
              rootId: rootId,
              swatchColor: color,
              title: title,
              fromName: fromName,
              swatchId: null,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.feed;
    final color = _parseHex(f.colorHex);
    final when =
        f.sentAt != null
            ? DateFormat('MMMM d, y, h:mm a').format(f.sentAt!)
            : 'Today';
    final String title = (f.title.isEmpty ? f.colorHex : f.title).trim();

    final bool showLineagePill =
        (f.rootId != null && f.rootId!.isNotEmpty); // only if lineage exists

    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E2E2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // square artwork (fixed)
            AspectRatio(aspectRatio: 1, child: Container(color: color)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          title.isEmpty ? f.colorHex : title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Opacity(
                        opacity: _loading ? 0.5 : 1.0,
                        child: _KeepHexButton(
                          kept: _kept,
                          onPressed: () async {
                            await widget.onToggleKeep();
                            _prime(); // refresh local icon state
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'COLOR FOR: $when',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'CREATOR: ${f.creatorName.isEmpty ? "Anonymous" : f.creatorName}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            letterSpacing: 0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showLineagePill) ...[
                        const SizedBox(width: 8),
                        _LineagePill(onTap: _openLineage),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _parseHex(String hex) {
    final cleaned = hex.replaceAll('#', '');
    final value = int.parse('FF$cleaned', radix: 16);
    return Color(value);
  }
}

/// Small rounded black pill labeled “LINEAGE”
class _LineagePill extends StatelessWidget {
  final VoidCallback onTap;
  const _LineagePill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'LINEAGE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Minimal side chevron (bold caret)
class _SideChevron extends StatelessWidget {
  final Alignment alignment;
  final double rotationRadians; // -pi/2 (right) or +pi/2 (left)
  final bool enabled;
  final VoidCallback onPressed;

  const _SideChevron({
    required this.alignment,
    required this.rotationRadians,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withOpacity(0.38);
    final Color fg = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(enabled ? 0.84 : 0.4);

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withOpacity(0.6),
              ),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 10,
                  offset: Offset(0, 2),
                  color: Color(0x1F000000),
                ),
              ],
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onPressed : null,
              child: Center(
                child: Transform.rotate(
                  angle: rotationRadians,
                  child: Icon(Icons.expand_more_rounded, size: 28, color: fg),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===== Shared widgets =====

class _KeepHexButton extends StatelessWidget {
  final bool kept;
  final FutureOr<void> Function() onPressed;
  final double size;

  const _KeepHexButton({
    required this.kept,
    required this.onPressed,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final fill = kept ? onSurface.withOpacity(0.14) : Colors.transparent;
    final stroke = onSurface.withOpacity(kept ? 0.9 : 0.6);

    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () {
        onPressed(); // allow sync or async
      },
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _HexPainter(stroke: stroke, fill: fill)),
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  final Color stroke;
  final Color fill;
  _HexPainter({required this.stroke, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = _hexPath(rect.deflate(3));
    final pFill =
        Paint()
          ..style = PaintingStyle.fill
          ..color = fill;
    canvas.drawPath(path, pFill);
    final pStroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = stroke
          ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, pStroke);
  }

  Path _hexPath(Rect r) {
    final cx = r.center.dx;
    final cy = r.center.dy;
    final radius = math.min(r.width, r.height) / 2;
    final points = List<Offset>.generate(6, (i) {
      final angle = (math.pi / 3) * i + math.pi / 6; // flat top
      return Offset(
        cx + radius * math.cos(angle),
        cy + radius * math.sin(angle),
      );
    });
    final p = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      p.lineTo(points[i].dx, points[i].dy);
    }
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant _HexPainter oldDelegate) =>
      oldDelegate.stroke != stroke || oldDelegate.fill != fill;
}
