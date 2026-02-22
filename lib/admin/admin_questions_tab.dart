import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// Admin UI tokens + helpers + name cache
import 'package:color_wallet/admin/admin_components.dart'
    show
        AdminNameCache,
        adminColorFromHex,
        kAdminMuted,
        kAdminText,
        kAdminDivider;

// Daily Scroll (deep-link)
import 'package:color_wallet/daily_hues/daily_scroll_screen.dart';

class AdminQuestionsTab extends StatefulWidget {
  const AdminQuestionsTab({
    super.key,
    required this.db,
    this.startUtc, // nullable; ignored by design (all-time)
    this.endUtc, // nullable; ignored by design (all-time)
    this.maxAnswersPerQuestion = 500, // per-question fetch cap
  });

  final FirebaseFirestore db;
  final Timestamp? startUtc; // optional (ignored)
  final Timestamp? endUtc; // optional (ignored)
  final int maxAnswersPerQuestion;

  @override
  State<AdminQuestionsTab> createState() => _AdminQuestionsTabState();
}

class _AdminQuestionsTabState extends State<AdminQuestionsTab>
    with AutomaticKeepAliveClientMixin {
  late final AdminNameCache _names;

  // Cached per-question minimal chips (hexes only) to keep the row light.
  final Map<String, List<String>> _answerHexes = {};

  // Cached per-question full answer rows for the dropdown.
  final Map<String, List<_AnswerMeta>> _answersMeta = {};

  // cache newest createdAt for deep link
  final Map<String, DateTime> _latestCreatedAt = {};

  // in-flight tracker to avoid duplicate fetches
  final Set<String> _fetching = {};

  @override
  void initState() {
    super.initState();
    _names = AdminNameCache(widget.db);
  }

  @override
  bool get wantKeepAlive => true;

  // --- Time helpers -----------------------------------------------------------

  // extract a timezone offset (in minutes) from a doc, if present
  int? _extractOffsetMin(Map<String, dynamic> m) {
    for (final k in const [
      'authorTzOffsetMin',
      'authorTzOffsetMinutes',
      'tzOffsetMin',
      'tzOffsetMinutes',
      'senderTzOffsetMin',
      'senderTzOffsetMinutes',
      'senderUtcOffsetMin',
    ]) {
      final v = m[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
    }
    return null;
  }

  // “3.25pm January 25, 2025” using the creator’s offset when available.
  String _fmtLocalDot(DateTime utc, {int? offsetMin}) {
    final dt = offsetMin != null ? utc.add(Duration(minutes: offsetMin)) : utc;
    final raw = DateFormat('h.mma MMMM d, y').format(dt);
    return raw.replaceAll('AM', 'am').replaceAll('PM', 'pm');
  }

  // ---------------------------------------------------------------------------

  // Pull answers for a given question once; cache result
  Future<void> _ensureAnswersFor(String questionId) async {
    if ((_answerHexes.containsKey(questionId) &&
            _answersMeta.containsKey(questionId)) ||
        _fetching.contains(questionId)) {
      return;
    }
    _fetching.add(questionId);
    try {
      // Answers live in ROOT 'answers'; sort by createdAt DESC
      final snap =
          await widget.db
              .collection('answers')
              .where('questionId', isEqualTo: questionId)
              .orderBy('createdAt', descending: true)
              .limit(widget.maxAnswersPerQuestion)
              .get();

      final chips = <String>[];
      final rows = <_AnswerMeta>[];
      DateTime? newest;

      final uids = <String>{};

      for (final d in snap.docs) {
        final m = d.data();
        final hex = ((m['colorHex'] ?? '') as String).trim();
        final title = ((m['title'] ?? '') as String).trim();
        final uid = ((m['responderId'] ?? m['uid'] ?? '') as String).trim();

        DateTime? created;
        final raw = m['createdAt'];
        if (raw is Timestamp) created = raw.toDate();
        if (raw is DateTime) created = raw;
        if (created != null) {
          final utc = created.toUtc();
          if (newest == null || utc.isAfter(newest)) newest = utc;
        }

        if (hex.isNotEmpty) {
          chips.add(hex);
          rows.add(
            _AnswerMeta(
              hex: hex,
              title: title.isEmpty ? hex : title,
              uid: uid,
              createdAtUtc: created?.toUtc(),
              offsetMin: _extractOffsetMin(m),
            ),
          );
          if (uid.isNotEmpty) uids.add(uid);
        }
      }

      // Resolve responder display names (cached).
      if (uids.isNotEmpty) {
        await _names.resolve(uids);
      }

      _answerHexes[questionId] = chips;
      _answersMeta[questionId] = rows;
      if (newest != null) _latestCreatedAt[questionId] = newest;
      if (mounted) setState(() {});
    } catch (_) {
      _answerHexes[questionId] = const <String>[];
      _answersMeta[questionId] = const <_AnswerMeta>[];
      if (mounted) setState(() {});
    } finally {
      _fetching.remove(questionId);
    }
  }

  // Choose initialUtcDay for deep link: latest answer.createdAt (UTC) else question.createdAt
  String _initialUtcDayFor(Map<String, dynamic> q, String qid) {
    DateTime? utc = _latestCreatedAt[qid];
    if (utc == null) {
      final ts = q['createdAt'];
      if (ts is Timestamp) utc = ts.toDate().toUtc();
      if (ts is DateTime) utc = ts.toUtc();
    }
    utc ??= DateTime.now().toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          widget.db
              .collection('questions')
              .orderBy('createdAt', descending: true)
              .limit(200) // keep fast; adjust if needed
              .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;

        // Resolve author names
        final uids = <String>{
          for (final d in docs)
            ((d.data()['uid'] ?? d.data()['authorId']) as String? ?? ''),
        }..removeWhere((e) => e.isEmpty);
        _names.resolve(uids).then((_) {
          if (mounted) setState(() {});
        });

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final d = docs[i];
            final m = d.data();
            final qid = d.id;

            // kick off answers load for this question (once)
            _ensureAnswersFor(qid);

            final title = (m['title'] ?? m['text'] ?? '').toString();
            final uid = (m['uid'] ?? m['authorId'] ?? '').toString();
            final author = _names.nameFor(uid);

            DateTime? created;
            final createdRaw = m['createdAt'];
            if (createdRaw is Timestamp) created = createdRaw.toDate().toUtc();
            if (createdRaw is DateTime) created = createdRaw.toUtc();
            final createdLabel =
                created == null
                    ? ''
                    : _fmtLocalDot(created, offsetMin: _extractOffsetMin(m));

            final chips = _answerHexes[qid];
            final details = _answersMeta[qid];
            final isLoading = chips == null || details == null;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x15000000)),
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title (click to open Daily Scroll on the relevant day)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      final initialUtcDay = _initialUtcDayFor(m, qid);
                      Navigator.of(context).pushNamed(
                        DailyScrollScreen.routeName,
                        arguments: {
                          'initialUtcDay': initialUtcDay,
                          'initialDay': initialUtcDay, // legacy fallback
                        },
                      );
                    },
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: kAdminText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Meta line: author • createdAt (creator local time); removed "status"
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          [
                            'by $author',
                            if (createdLabel.isNotEmpty) createdLabel,
                          ].join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: kAdminMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Inline color chips with tooltips (title); below them, an expand-for-details
                  if (isLoading)
                    const SizedBox(
                      height: 26,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    _QuestionAnswersBlock(
                      hexes: chips,
                      answers: details,
                      names: _names,
                      fmtLocalDot:
                          (utc, off) => _fmtLocalDot(utc, offsetMin: off),
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

class _AnswerMeta {
  _AnswerMeta({
    required this.hex,
    required this.title,
    required this.uid,
    required this.createdAtUtc,
    required this.offsetMin,
  });

  final String hex;
  final String title; // answer title (fallback to hex if empty)
  final String uid; // responder id
  final DateTime? createdAtUtc;
  final int? offsetMin; // creator offset minutes (if known)
}

// Inline chips + expandable details list.
class _QuestionAnswersBlock extends StatefulWidget {
  const _QuestionAnswersBlock({
    required this.hexes,
    required this.answers,
    required this.names,
    required this.fmtLocalDot,
  });

  final List<String> hexes;
  final List<_AnswerMeta> answers;
  final AdminNameCache names;
  // formatter that accepts UTC + optional offset minutes
  final String Function(DateTime, int?) fmtLocalDot;

  @override
  State<_QuestionAnswersBlock> createState() => _QuestionAnswersBlockState();
}

class _QuestionAnswersBlockState extends State<_QuestionAnswersBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    // Top row: chips with tooltips (title)
    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children:
          widget.hexes.map((h) {
            final color = adminColorFromHex(h);
            final meta = widget.answers.firstWhere(
              (a) => a.hex.toUpperCase() == h.toUpperCase(),
              orElse:
                  () => _AnswerMeta(
                    hex: h,
                    title: h,
                    uid: '',
                    createdAtUtc: null,
                    offsetMin: null,
                  ),
            );
            return Tooltip(
              message: meta.title,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0x15000000), width: 1),
                ),
              ),
            );
          }).toList(),
    );

    // Expanded details: each answer shows color, title, creator, createdAt
    final details =
        !_open
            ? const SizedBox.shrink()
            : Column(
              children: [
                const SizedBox(height: 10),
                const Divider(height: 1, color: kAdminDivider),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 10),
                  itemCount: widget.answers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final a = widget.answers[i];
                    final name = widget.names.nameFor(a.uid);
                    final timeLabel =
                        a.createdAtUtc == null
                            ? '–'
                            : widget.fmtLocalDot(a.createdAtUtc!, a.offsetMin);
                    return Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: adminColorFromHex(a.hex),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(0x15000000),
                              width: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            a.title.isEmpty ? a.hex : a.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: kAdminText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            name.isEmpty ? a.uid : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: kAdminMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: kAdminMuted,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chips,
        const SizedBox(height: 8),
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
          label: Text(_open ? 'Hide details' : 'Show details'),
        ),
        details,
      ],
    );
  }
}
