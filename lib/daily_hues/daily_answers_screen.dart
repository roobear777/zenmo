import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/analytics.dart';
import '../services/daily_clock.dart';

// Repos
import '../services/answer_repository.dart';
import '../services/firestore/answer_repository_firestore.dart';

// Models
import '../models/answer.dart';
import '../services/keep_repository.dart';
import '../services/firestore/keep_repository_firestore.dart';

// For jump to the daily scroll (this is the new navigation target)
import 'daily_scroll_screen.dart';

class DailyAnswersScreen extends StatefulWidget {
  const DailyAnswersScreen({super.key, required this.initialDay});
  final String initialDay; // YYYY-MM-DD (local)

  @override
  State<DailyAnswersScreen> createState() => _DailyAnswersScreenState();
}

class _DailyAnswersScreenState extends State<DailyAnswersScreen> {
  late final int _initialIndexFromToday;
  late final PageController _page; // initialized with initialPage
  int _index = 0;

  bool _overlayVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logEvent('daily_view_answers_scroll');
    _initialIndexFromToday = _offsetFromToday(widget.initialDay);
    _index = _initialIndexFromToday;
    _page = PageController(initialPage: _initialIndexFromToday);
    _showOverlayTemporarily();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _page.dispose();
    super.dispose();
  }

  int _offsetFromToday(String dayId) {
    final base = DailyClock().localDay; // today
    final a = DateTime.parse(base);
    final b = DateTime.parse(dayId);
    return a.difference(DateUtils.dateOnly(b)).inDays;
  }

  void _showOverlayTemporarily() {
    setState(() => _overlayVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  String _dayForOffset(int offsetDays) {
    final baseDay = DailyClock().localDay;
    final parts = baseDay.split('-');
    final base = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    ).subtract(Duration(days: offsetDays));
    final y = base.year.toString().padLeft(4, '0');
    final m = base.month.toString().padLeft(2, '0');
    final d = base.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final title =
        _index <= 1
            ? (_index == 0 ? 'Answers • Today' : 'Answers • Yesterday')
            : (() {
              final dayId = _dayForOffset(_index);
              final dt = DateTime.parse(dayId);
              final weekday = DateFormat('EEE').format(dt);
              final pretty = DateFormat('d MMM yyyy').format(dt);
              return 'Answers • $weekday • $pretty';
            })();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
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
                reverse: true, // ← past comes from the left
                onPageChanged: (i) {
                  setState(() => _index = i);
                  _showOverlayTemporarily();
                },
                itemCount: 365,
                itemBuilder: (_, i) => _AnswersDayList(dayId: _dayForOffset(i)),
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
                      _CircleChevron(
                        directionLeft: true,
                        onTap: () {
                          _page.animateToPage(
                            (_index + 1).clamp(0, 364),
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                          );
                        },
                      ),
                      _CircleChevron(
                        directionLeft: false,
                        onTap: () {
                          _page.animateToPage(
                            (_index - 1).clamp(0, 364),
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

class _AnswersDayList extends StatefulWidget {
  const _AnswersDayList({required this.dayId});
  final String dayId; // local YYYY-MM-DD

  @override
  State<_AnswersDayList> createState() => _AnswersDayListState();
}

class _AnswersDayListState extends State<_AnswersDayList>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  final AnswerRepository _answersRepo = AnswerRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );
  final KeepRepository _keepRepo = KeepRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  DateTime? _cursor;
  final _answers = <Answer>[];

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
  void didUpdateWidget(covariant _AnswersDayList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dayId != widget.dayId) {
      _resetAndReload();
    }
  }

  Future<void> _resetAndReload() async {
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = true;
      _cursor = null;
      _answers.clear();
    });
    await _loadInitial();
    if (mounted) _scroll.jumpTo(0);
  }

  /// Convert local YYYY-MM-DD to canonical UTC-day key YYYY-MM-DD (midnight UTC).
  String _toUtcDayFromLocal(String localYmd) {
    final local = DateTime.parse(localYmd);
    final utc = DateTime(local.year, local.month, local.day).toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}';
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    final dayUtc = _toUtcDayFromLocal(widget.dayId); // ← pass UTC to repo
    final page = await _answersRepo.getAnswersForDayPage(dayUtc, limit: 40);
    _answers
      ..clear()
      ..addAll(page.items);
    _cursor = page.nextCreatedAtCursor;
    _hasMore = page.hasMore;
    setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final dayUtc = _toUtcDayFromLocal(widget.dayId); // ← pass UTC to repo
    final page = await _answersRepo.getAnswersForDayPage(
      dayUtc,
      limit: 40,
      startAfterCreatedAt: _cursor,
    );
    _cursor = page.nextCreatedAtCursor;
    _hasMore = page.hasMore;
    _answers.addAll(page.items);
    setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _resetAndReload,
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _answers.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) {
          if (_loadingMore && i == _answers.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final a = _answers[i];
          return _AnswerSquareCard(
            dayId: widget.dayId, // ← pass the day to the card
            answer: a,
            keepRepo: _keepRepo,
          );
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

/// Stateful card so the hex can fill/unfill instantly on toggle.
class _AnswerSquareCard extends StatefulWidget {
  const _AnswerSquareCard({
    required this.dayId,
    required this.answer,
    required this.keepRepo,
  });
  final String dayId; // local YYYY-MM-DD (used for navigation target)
  final Answer answer;
  final KeepRepository keepRepo;

  @override
  State<_AnswerSquareCard> createState() => _AnswerSquareCardState();
}

class _AnswerSquareCardState extends State<_AnswerSquareCard> {
  bool _kept = false;
  bool _loadingKeep = true;

  // --- tiny cache for names to avoid duplicate reads ---
  static final Map<String, String> _uidToName = {};
  Future<String> _displayNameForUid(String? uid) async {
    if (uid == null || uid.isEmpty) return 'Anonymous';
    final cached = _uidToName[uid];
    if (cached != null) return cached;
    try {
      final u =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final name = (u.data()?['displayName'] as String?)?.trim();
      final resolved = (name == null || name.isEmpty) ? 'Anonymous' : name;
      _uidToName[uid] = resolved;
      return resolved;
    } catch (_) {
      return 'Anonymous';
    }
  }

  Future<String> _askerNameFor(Answer a) async {
    try {
      final q =
          await FirebaseFirestore.instance
              .collection('questions')
              .doc(a.questionId)
              .get();
      final authorId = q.data()?['authorId'] as String?;
      return _displayNameForUid(authorId);
    } catch (_) {
      return 'Anonymous';
    }
  }

  // NEW: resolve the creator from the answer's responderId
  Future<String> _creatorNameFor(Answer a) async {
    return _displayNameForUid(a.responderId);
  }
  // -----------------------------------------------------

  @override
  void initState() {
    super.initState();
    _primeKept();
  }

  Future<void> _primeKept() async {
    try {
      final k = await widget.keepRepo.isKept(widget.answer.id);
      if (mounted) setState(() => _kept = k);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingKeep = false);
    }
  }

  Future<void> _toggleKeep() async {
    if (_loadingKeep) return;
    setState(() => _loadingKeep = true);
    try {
      final now = await widget.keepRepo.toggleKeep(widget.answer.id);
      if (mounted) setState(() => _kept = now);
    } finally {
      if (mounted) setState(() => _loadingKeep = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseHex(widget.answer.colorHex);
    final createdText = DateFormat(
      'MMMM d, y, h:mm a',
    ).format(widget.answer.createdAt.toLocal());

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
            // Square color block — tap to jump to the daily scroll for THIS day
            AspectRatio(
              aspectRatio: 1,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => DailyScrollScreen(initialDay: widget.dayId),
                    ),
                  );
                },
                child: ColoredBox(color: color),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.answer.title.isEmpty
                              ? widget.answer.colorHex
                              : widget.answer.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'COLOR FOR: $createdText',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // COLOR ASKER
                        FutureBuilder<String>(
                          future: _askerNameFor(widget.answer),
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
                        const SizedBox(height: 2),
                        // CREATED BY
                        FutureBuilder<String>(
                          future: _creatorNameFor(widget.answer),
                          builder: (context, snap) {
                            final creator = (snap.data ?? 'Anonymous').trim();
                            return Text(
                              'CREATED BY: $creator',
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
                  // Hex keep (filled when kept). No snackbar.
                  Opacity(
                    opacity: _loadingKeep ? 0.5 : 1.0,
                    child: _KeepHexButton(
                      kept: _kept,
                      onPressed: _toggleKeep,
                      size: 28,
                    ),
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
    String h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final int? v = int.tryParse(h, radix: 16);
    return v == null ? Colors.grey : Color(v);
  }
}

class _CircleChevron extends StatelessWidget {
  const _CircleChevron({required this.directionLeft, required this.onTap});
  final bool directionLeft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withOpacity(0.38);
    final outline = Theme.of(
      context,
    ).colorScheme.outlineVariant.withOpacity(0.6);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: outline),
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
            onTap: onTap,
            child: Center(
              child: Transform.rotate(
                // Outward-facing chevrons
                angle: directionLeft ? math.pi / 2 : -math.pi / 2,
                child: const Icon(Icons.expand_more_rounded, size: 28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===== Shared widgets =====

/// Hex keep icon button (outline; fills when kept).
class _KeepHexButton extends StatelessWidget {
  final bool kept;
  final VoidCallback onPressed;
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
      onTap: onPressed,
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
