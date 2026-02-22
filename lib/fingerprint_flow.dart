import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:color_wallet/fingerprint_repo.dart';
import 'fingerprint_questions.dart';
import 'fingerprint_grid.dart';

// Use the wheel painter and the mosaic from the picker file
import 'color_picker_screen.dart' show HueValueDiscPainter, ColorMosaicScreen;

class FingerprintFlow extends StatefulWidget {
  const FingerprintFlow({
    super.key,
    this.initialAnswers,
    this.startAtIndex,
    this.redoCurrentMonth = false, // <— added
  });

  /// Dense prefix in question order
  final List<int>? initialAnswers;

  /// Question index to focus first
  final int? startAtIndex;

  /// When true, flow was launched from “Redo” for the current month.
  /// (Not strictly used yet; kept for future UI/logic branches.)
  final bool redoCurrentMonth; // <— added

  @override
  State<FingerprintFlow> createState() => _FingerprintFlowState();
}

class _FingerprintFlowState extends State<FingerprintFlow> {
  // “current” is what the wheel is set to (not committed yet)
  Color? current;

  // Question index → committed ARGB answer
  late Map<int, int> _answerMap; // qIndex -> ARGB

  // Queue of remaining question indices in the order to answer
  late List<int> _queue;

  bool _saving = false;

  static const double _pagePad = 20;

  final ScrollController _scrollController = ScrollController();

  int get _currentQIndex => _queue.isEmpty ? 0 : _queue.first;

  int get _totalQuestions => kFingerprintTotal;

  int get _answeredCount {
    int count = 0;
    for (int i = 0; i < _totalQuestions; i++) {
      if (_answerMap[i] == null) break;
      count++;
    }
    return count;
  }

  @override
  void initState() {
    super.initState();
    final int total = kFingerprintTotal;
    _queue = List<int>.generate(total, (i) => i);
    _answerMap = {};

    // Seed answers (dense prefix in question order)
    final init = widget.initialAnswers ?? const [];
    for (int i = 0; i < init.length && i < total; i++) {
      _answerMap[i] = init[i];
    }

    // If startAtIndex provided, move that qIndex to the front.
    final focus = widget.startAtIndex;
    if (focus != null) {
      final f = focus.clamp(0, total - 1);
      _queue.removeWhere((i) => (i < init.length) && i != f);
      _queue.remove(f);
      _queue.insert(0, f);
    } else {
      // default behavior: only unanswered remain in the queue
      _queue.removeWhere((i) => i < init.length);
    }

    // Set current swatch to the first queued answer if any, else null.
    if (_queue.isNotEmpty) {
      current =
          _answerMap.containsKey(_currentQIndex)
              ? Color(_answerMap[_currentQIndex]!)
              : null;
      if (current != null) current = current!.withAlpha(0xFF);
    }

    if (_queue.isNotEmpty && _answerMap.containsKey(_currentQIndex)) {
      current = Color(_answerMap[_currentQIndex]!).withAlpha(0xFF);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<int> _densePrefixForDraft() {
    final out = <int>[];
    for (int i = 0; i < _totalQuestions; i++) {
      final v = _answerMap[i];
      if (v == null) break;
      out.add(v);
    }
    return out;
  }

  List<int> _fullOrderedAnswers() => List<int>.generate(
    _totalQuestions,
    (i) => _answerMap[i]!,
    growable: false,
  );

  // ---------- Wheel picking ----------
  final GlobalKey _wheelKey = GlobalKey();

  void _handleWheelTapDown(Offset globalPos) {
    final box = _wheelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final local = box.globalToLocal(globalPos);
    final size = box.size;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final dx = (local.dx - cx) / cx;
    final dy = (local.dy - cy) / cy;

    final r = math.sqrt(dx * dx + dy * dy);

    // Ignore taps outside the disc.
    if (r > 1.0) return;

    final angleRadians = math.atan2(dy, dx);
    final angleDegrees = (angleRadians * 180 / math.pi + 360 + 90) % 360;
    final hue = angleDegrees;

    // Map radius to value similarly to the rendered rings (brighter near centre).
    final value = (1.0 - (r * 0.75)).clamp(0.2, 1.0);
    final hsv = HSVColor.fromAHSV(1.0, hue, 0.95, value);
    setState(() => current = hsv.toColor().withAlpha(0xFF));
  }

  void _handleWheelDrag(Offset globalPos) {
    _handleWheelTapDown(globalPos);
  }

  // ---------- Draft saving ----------
  Future<void> _saveDraftSilently() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await FingerprintRepo.saveDraft(
        answers: _densePrefixForDraft(),
        total: _totalQuestions,
      );
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  // ---------- Commit answer + advance ----------
  Future<void> _commitAndNext() async {
    if (_queue.isEmpty) return;
    final color = current;
    if (color == null) return;

    // Ensure stored answer is fully opaque
    _answerMap[_currentQIndex] = color.withAlpha(0xFF).value;
    setState(() {
      _queue.removeAt(0);
      current = null;
    });

    await _saveDraftSilently();

    if (_queue.isEmpty) {
      await _finishFlow();
      return;
    }

    // Scroll back to top for next question
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _skipToEnd() {
    if (_queue.length <= 1) return;
    setState(() {
      final head = _queue.removeAt(0);
      _queue.add(head);
      final nextIdx = _currentQIndex;
      current =
          _answerMap.containsKey(nextIdx) ? Color(_answerMap[nextIdx]!) : null;
      if (current != null) current = current!.withAlpha(0xFF);
    });
  }

  Future<void> _finishFlow() async {
    if (_answerMap.length != _totalQuestions) return;
    try {
      // Save to monthly path using the repo helper
      await FingerprintRepo.saveCurrentMonthFromAnswers(
        db: FirebaseFirestore.instance,
        uid: FirebaseAuth.instance.currentUser!.uid,
        answers: _fullOrderedAnswers(),
      );
    } catch (_) {}
    if (!mounted) return;

    Navigator.pop(context, _fullOrderedAnswers());
  }

  Future<void> _saveAndQuit() async {
    if (_saving) return;

    // Commit current selection for this question before saving
    if (_queue.isNotEmpty && current != null) {
      _answerMap[_currentQIndex] = current!.withAlpha(0xFF).value;
    }

    await _saveDraftSilently();
    if (!mounted) return;

    // Return the dense prefix so Account can update immediately
    Navigator.pop(context, _densePrefixForDraft());
  }

  @override
  Widget build(BuildContext context) {
    final qIndex = _currentQIndex;

    // Defensive: clamp qIndex to available question list
    final int safeQIndex;
    if (qIndex < 0 || qIndex >= kFingerprintQs.length) {
      safeQIndex = qIndex.clamp(0, kFingerprintQs.length - 1);
    } else {
      safeQIndex = qIndex;
    }

    final swatch =
        current ??
        (_answerMap[qIndex] != null ? Color(_answerMap[qIndex]!) : null);

    final size = MediaQuery.of(context).size;
    final double wheelSize = math.min(size.width - (_pagePad * 2), 320);
    final double swatchSize = math.min(140, wheelSize * 0.28); // ~120–140

    // Progress for big visual bar (answered / total). Clamp to [0,1].
    final double progress = (_answeredCount / _totalQuestions).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => Navigator.pop(context, _densePrefixForDraft()),
        ),
        title: Text('Fingerprint Qs: ${qIndex + 1} / $_totalQuestions'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(12),
          child: Column(
            children: [
              const Divider(height: 1, thickness: 1, color: Colors.black12),
              // Thick, obvious progress bar
              SizedBox(
                height: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress, // 0.0–1.0
                    backgroundColor: const Color(0xFFE6E8ED),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(_pagePad, 20, _pagePad, 28),
        children: [
          _QuestionBanner(
            number: qIndex + 1,
            text:
                (kFingerprintQs.isNotEmpty &&
                        safeQIndex >= 0 &&
                        safeQIndex < kFingerprintQs.length)
                    ? kFingerprintQs[safeQIndex]
                    : 'Question ${qIndex + 1}',
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.center,
            child: Container(
              height: swatchSize,
              width: swatchSize,
              decoration: BoxDecoration(
                color: swatch ?? Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black26),
              ),
              child: null,
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: wheelSize,
              height: wheelSize,
              child: GestureDetector(
                onTapDown: (d) => _handleWheelTapDown(d.globalPosition),
                onPanUpdate: (d) => _handleWheelDrag(d.globalPosition),
                child: Container(
                  key: _wheelKey,
                  // Clip to circle so only painted pixels show.
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: Padding(
                    // Small inset so the painted disc doesn’t get clipped at the edge
                    padding: const EdgeInsets.all(4.0),
                    child: CustomPaint(painter: HueValueDiscPainter()),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          Center(
            child: ElevatedButton(
              onPressed:
                  (_queue.isEmpty || swatch == null) ? null : _commitAndNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5F6572),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(
                (_answeredCount + 1 < _totalQuestions)
                    ? 'Continue to next question'
                    : 'Finish',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _queue.isNotEmpty ? _skipToEnd : null,
                child: const Text('Skip'),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed:
                    (swatch == null)
                        ? null
                        : () async {
                          // Quick “mosaic” view (existing component)
                          final picked = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder:
                                  (_) => ColorMosaicScreen(
                                    baseHue: 0,
                                    ringIndex: 0,
                                    returnPickedColor: true,
                                  ),
                            ),
                          );
                          if (!mounted) return;
                          if (picked is Color) {
                            setState(() => current = picked.withAlpha(0xFF));
                          }
                        },
                child: const Text('Mosaic'),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: _saving ? null : _saveAndQuit,
                child: const Text('Save & Quit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuestionBanner extends StatelessWidget {
  final int number;
  final String text;
  const _QuestionBanner({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE9EDF3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number.',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
