// lib/party_fingerprint_flow.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:color_wallet/fingerprint_grid.dart';
import 'package:color_wallet/party_fingerprint_questions.dart';
import 'package:color_wallet/party_fingerprint_repo.dart';

// Reuse wheel painter from the picker file
import 'color_picker_screen.dart' show HueValueDiscPainter;

class PartyFingerprintFlow extends StatefulWidget {
  const PartyFingerprintFlow({
    super.key,
    this.initialAnswers,
    this.startAtIndex,
  });

  final List<Map<String, dynamic>>? initialAnswers; // ordered prefix objects
  final int? startAtIndex;

  @override
  State<PartyFingerprintFlow> createState() => _PartyFingerprintFlowState();
}

class _PartyFingerprintFlowState extends State<PartyFingerprintFlow> {
  static const int _total = 5;
  static const double _pagePad = 18;
  static const int _maxColorsPerPrompt = 5;
  static final List<int> _spiral5x5 = _centerOutSpiral(rows: 5, cols: 5);

  final GlobalKey _wheelKey = GlobalKey();

  final TextEditingController _titleCtrl = TextEditingController();

  late List<Map<String, dynamic>> _answers; // ordered partial list length <= 5
  late int _index; // current prompt index 0..4, or 5 for summary
  bool _saving = false;

  Color _current = Colors.red;
  List<Color> _pickedColors = [];

  @override
  void initState() {
    super.initState();

    _answers = _normalizeAnswersList(widget.initialAnswers);
    _index = (widget.startAtIndex ?? _answers.length).clamp(0, _total);
    if (_index < _total) {
      _loadStateForIndex(_index);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  static List<int> _centerOutSpiral({required int rows, required int cols}) {
    final total = rows * cols;
    final result = <int>[];

    int r = rows ~/ 2;
    int c = cols ~/ 2;

    result.add(r * cols + c);

    int stepLen = 1;
    int added = 1;

    bool inBounds(int rr, int cc) =>
        rr >= 0 && rr < rows && cc >= 0 && cc < cols;

    void tryAdd(int rr, int cc) {
      if (inBounds(rr, cc)) {
        result.add(rr * cols + cc);
        added += 1;
      }
    }

    while (added < total) {
      for (int i = 0; i < stepLen && added < total; i++) {
        c += 1;
        tryAdd(r, c);
      }
      for (int i = 0; i < stepLen && added < total; i++) {
        r += 1;
        tryAdd(r, c);
      }
      stepLen += 1;

      for (int i = 0; i < stepLen && added < total; i++) {
        c -= 1;
        tryAdd(r, c);
      }
      for (int i = 0; i < stepLen && added < total; i++) {
        r -= 1;
        tryAdd(r, c);
      }
      stepLen += 1;
    }

    return result.take(total).toList();
  }

  static List<Map<String, dynamic>> _normalizeAnswersList(
    List<Map<String, dynamic>>? raw,
  ) {
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];

    final out = <Map<String, dynamic>>[];

    for (final a in raw) {
      final title = (a['title'] ?? '').toString();

      final colorsRaw =
          (a['colors'] is List) ? (a['colors'] as List) : const [];
      final hexesRaw = (a['hexes'] is List) ? (a['hexes'] as List) : const [];

      final colors = <int>[];
      for (final v in colorsRaw) {
        if (v is int) colors.add(v);
      }

      final hexes = <String>[];
      for (final v in hexesRaw) {
        if (v is String) hexes.add(v);
      }

      while (hexes.length < colors.length) {
        hexes.add(_hexFromColorValue(colors[hexes.length]));
      }

      out.add({
        'title': title,
        'colors': colors.take(_maxColorsPerPrompt).toList(),
        'hexes': hexes.take(_maxColorsPerPrompt).toList(),
      });

      if (out.length >= _total) break;
    }

    return out;
  }

  static String _hexFromColorValue(int colorValue) {
    final rgb = colorValue & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static String _hexFromColor(Color c) => _hexFromColorValue(c.toARGB32());

  Color _colorFromInt(int v) {
    final vv = (v & 0xFF000000) == 0 ? (0xFF000000 | v) : v;
    return Color(vv);
  }

  void _loadStateForIndex(int i) {
    _pickedColors = [];
    _current = Colors.red;
    _titleCtrl.text = '';

    if (i < 0 || i >= _total) return;
    if (i >= _answers.length) return;

    final a = _answers[i];
    final title = (a['title'] ?? '').toString();
    final colorsRaw = (a['colors'] is List) ? (a['colors'] as List) : const [];

    final colors = <Color>[];
    for (final v in colorsRaw) {
      if (v is int) colors.add(_colorFromInt(v));
    }

    _pickedColors = colors.take(_maxColorsPerPrompt).toList();
    if (_pickedColors.isNotEmpty) {
      _current = _pickedColors.last;
    }
    _titleCtrl.text = title;
    setState(() {});
  }

  Map<String, dynamic> _buildCurrentAnswer() {
    final colors = _pickedColors
        .map((c) => c.toARGB32())
        .toList(growable: false);
    final hexes = _pickedColors.map(_hexFromColor).toList(growable: false);

    return {'title': _titleCtrl.text.trim(), 'colors': colors, 'hexes': hexes};
  }

  bool _currentPromptValid() {
    if (_pickedColors.isEmpty) return false;
    if (_titleCtrl.text.trim().isEmpty) return false;
    return true;
  }

  void _writeCurrentIntoAnswers() {
    final ans = _buildCurrentAnswer();

    if (_index < _answers.length) {
      _answers[_index] = ans;
    } else if (_index == _answers.length) {
      _answers.add(ans);
    } else {
      while (_answers.length < _index) {
        _answers.add({'title': '', 'colors': <int>[], 'hexes': <String>[]});
      }
      _answers.add(ans);
    }
  }

  Future<void> _persistDraft({required bool completed}) async {
    final now = Timestamp.now();

    final normalized = _normalizeAnswersList(_answers);

    final payload = <String, dynamic>{
      'answers': normalized,
      'total': _total,
      'completed': completed,
      'version': 1,
      'updatedAt': now,
    };

    if (completed) {
      payload['completedAt'] = now;
    }

await PartyFingerprintRepo.saveDraft(
  answers: normalized,
  total: _total,
);

    // Keep timestamp fields aligned with rules/reads
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('partyFingerprint');

      final snap = await ref.get();
      if (!snap.exists) {
        payload['createdAt'] = now;
        await ref.set(payload);
      } else {
        await ref.set(payload, SetOptions(merge: true));
      }
    }
  }

  Future<void> _persistCanonicalCompleted() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final now = Timestamp.now();
    final normalized = _normalizeAnswersList(_answers);

    final ref = FirebaseFirestore.instance
        .collection('events')
        .doc('party')
        .collection('fingerprints')
        .doc(uid);

    final snap = await ref.get();

    final payload = <String, dynamic>{
      'eventId': 'party',
      'answers': normalized,
      'total': _total,
      'completed': true,
      'version': 1,
      'updatedAt': now,
      'completedAt': now,
    };

    if (!snap.exists) {
      payload['createdAt'] = now;
      await ref.set(payload);
    } else {
      // preserve createdAt if present
      final existing = snap.data();
      if (existing != null && existing['createdAt'] != null) {
        payload['createdAt'] = existing['createdAt'];
      }
      await ref.set(payload, SetOptions(merge: true));
    }
  }

  Future<void> _saveAndQuit() async {
    if (_saving) return;

    setState(() => _saving = true);
    try {
      // Save current in-progress prompt too (even if incomplete) so user keeps progress
      _writeCurrentIntoAnswers();

      await _persistDraft(completed: false);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      _showError('Save failed (${e.code}): ${e.message ?? 'Unknown error'}');
    } catch (e) {
      if (!mounted) return;
      _showError('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _commitPromptAndNext() async {
    if (_saving) return;

    if (!_currentPromptValid()) {
      _showError('Please add at least 1 color and a title before continuing.');
      return;
    }

    setState(() => _saving = true);
    try {
      _writeCurrentIntoAnswers();
      await _persistDraft(completed: false);

      setState(() {
        _index += 1;
      });

      if (_index < _total) {
        _loadStateForIndex(_index);
      }
    } on FirebaseException catch (e) {
      _showError(
        'Could not continue (${e.code}): ${e.message ?? 'Unknown error'}',
      );
    } catch (e) {
      _showError('Could not continue: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finishAndSave() async {
    if (_saving) return;

    if (!_currentPromptValid()) {
      _showError('Please add at least 1 color and a title before finishing.');
      return;
    }

    setState(() => _saving = true);
    try {
      _writeCurrentIntoAnswers();

      final normalized = _normalizeAnswersList(_answers);
      final missing = _incompletePromptNumbers(normalized);
      if (missing.isNotEmpty) {
        throw StateError('Missing prompt(s): ${missing.join(', ')}');
      }

      await _persistDraft(completed: true);
      await _persistCanonicalCompleted();

      if (!mounted) return;

      setState(() {
        _index = _total; // summary screen
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      _showError('Finish failed (${e.code}): ${e.message ?? 'Unknown error'}');
    } catch (e) {
      if (!mounted) return;
      _showError('Finish failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<int> _incompletePromptNumbers(List<Map<String, dynamic>> answers) {
    final missing = <int>[];
    if (answers.length != _total) {
      for (int i = answers.length; i < _total; i++) {
        missing.add(i + 1);
      }
    }
    for (int i = 0; i < answers.length && i < _total; i++) {
      final a = answers[i];
      final title = (a['title'] ?? '').toString().trim();
      final colors = (a['colors'] is List) ? (a['colors'] as List) : const [];
      if (title.isEmpty || colors.isEmpty) {
        if (!missing.contains(i + 1)) missing.add(i + 1);
      }
    }
    missing.sort();
    return missing;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _addCurrentColor() {
    if (_pickedColors.length >= _maxColorsPerPrompt) {
      _showError(
        'You can add up to $_maxColorsPerPrompt colors for this prompt.',
      );
      return;
    }

    final currentInt = _current.toARGB32();
    final alreadyExists = _pickedColors.any((c) => c.toARGB32() == currentInt);
    if (alreadyExists) {
      _showError('That color is already added for this prompt.');
      return;
    }

    setState(() {
      _pickedColors = [..._pickedColors, _current];
    });
  }

  void _removeColorAt(int index) {
    if (index < 0 || index >= _pickedColors.length) return;
    setState(() {
      final copy = [..._pickedColors];
      copy.removeAt(index);
      _pickedColors = copy;
      if (_pickedColors.isNotEmpty) {
        _current = _pickedColors.last;
      }
    });
  }

  void _goBack() {
    if (_index <= 0) return;
    setState(() {
      _index -= 1;
    });
    _loadStateForIndex(_index);
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= _total) {
      return _buildSummary(context);
    }

    final prompt = kPartyFingerprintPrompts[_index];

    final header = 'Prompt ${_index + 1}';
    final showPromptInBody = prompt.trim() != header;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Party Fingerprint'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveAndQuit,
            child: const Text('Save & Quit'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(_pagePad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopProgressHeader(
                        currentPromptNumber: _index + 1,
                        total: _total,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        header,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (showPromptInBody) ...[
                        const SizedBox(height: 8),
                        Text(
                          prompt,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                      const SizedBox(height: 14),
                      _ColorWheelCard(
                        wheelKey: _wheelKey,
                        current: _current,
                        onColorChanged: (c) => setState(() => _current = c),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Selected colors (${_pickedColors.length}/$_maxColorsPerPrompt)',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed:
                                (_saving ||
                                        _pickedColors.length >=
                                            _maxColorsPerPrompt)
                                    ? null
                                    : _addCurrentColor,
                            child: const Text('Add color'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _ColorChipsWrap(
                        colors: _pickedColors,
                        onRemove: _saving ? null : _removeColorAt,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _titleCtrl,
                        enabled: !_saving,
                        maxLength: 140,
                        decoration: const InputDecoration(
                          labelText: 'Title for this prompt',
                          hintText:
                              'e.g. Bright welcome / Dancefloor / Calm corner',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: (_saving || _index == 0) ? null : _goBack,
                    child: const Text('Back'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed:
                        _saving
                            ? null
                            : (_index == _total - 1
                                ? _finishAndSave
                                : _commitPromptAndNext),
                    child:
                        _saving
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : Text(_index == _total - 1 ? 'Finish' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final normalized = _normalizeAnswersList(_answers);
    final missing = _incompletePromptNumbers(normalized);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Party Fingerprint'),
        actions: [
          TextButton(
            onPressed:
                _saving
                    ? null
                    : () {
                      Navigator.of(context).pop(true);
                    },
            child: const Text('Done'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(_pagePad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Party Fingerprint saved',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                missing.isEmpty
                    ? 'All 5 prompts are complete.'
                    : 'Missing prompts: ${missing.join(', ')}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (int i = 0; i < normalized.length && i < _total; i++)
                        _SummaryCard(
                          promptNumber: i + 1,
                          promptText: kPartyFingerprintPrompts[i],
                          title: (normalized[i]['title'] ?? '').toString(),
                          colors:
                              ((normalized[i]['colors'] is List)
                                      ? (normalized[i]['colors'] as List)
                                      : const [])
                                  .whereType<int>()
                                  .map(_colorFromInt)
                                  .toList(),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed:
                    _saving
                        ? null
                        : () {
                          Navigator.of(context).pop(true);
                        },
                child: const Text('Back to account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopProgressHeader extends StatelessWidget {
  const _TopProgressHeader({
    required this.currentPromptNumber,
    required this.total,
  });

  final int currentPromptNumber;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress =
        total == 0 ? 0.0 : (currentPromptNumber / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$currentPromptNumber out of $total',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: progress, minHeight: 8),
        ),
      ],
    );
  }
}

class _ColorWheelCard extends StatefulWidget {
  const _ColorWheelCard({
    required this.wheelKey,
    required this.current,
    required this.onColorChanged,
  });

  final GlobalKey wheelKey;
  final Color current;
  final ValueChanged<Color> onColorChanged;

  @override
  State<_ColorWheelCard> createState() => _ColorWheelCardState();
}

class _ColorWheelCardState extends State<_ColorWheelCard> {
  HSVColor _hsv = const HSVColor.fromAHSV(1, 0, 1, 1);

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant _ColorWheelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current.toARGB32() != widget.current.toARGB32()) {
      _syncFromWidget();
    }
  }

  void _syncFromWidget() {
    _hsv = HSVColor.fromColor(widget.current);
    if (_hsv.saturation == 0) {
      _hsv = _hsv.withSaturation(1);
    }
    if (_hsv.value == 0) {
      _hsv = _hsv.withValue(1);
    }
  }

  void _handleTapOrDrag(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;

    final radius = math.min(size.width, size.height) / 2;
    final dist = math.sqrt(dx * dx + dy * dy);

    if (dist > radius) return;

    double angle = math.atan2(dy, dx) * 180 / math.pi;
    if (angle < 0) angle += 360;

    final saturation = (dist / radius).clamp(0.0, 1.0);
    final value = _hsv.value;

    final next = HSVColor.fromAHSV(1, angle, saturation, value);
    setState(() => _hsv = next);
    widget.onColorChanged(next.toColor());
  }

  void _handleValueSlider(double v) {
    final next = _hsv.withValue(v.clamp(0.0, 1.0));
    setState(() => _hsv = next);
    widget.onColorChanged(next.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final preview = _hsv.toColor();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final size = math.min(constraints.maxWidth, 320.0);
                return Center(
                  child: GestureDetector(
                    onPanDown:
                        (d) => _handleTapOrDrag(
                          d.localPosition,
                          Size.square(size),
                        ),
                    onPanUpdate:
                        (d) => _handleTapOrDrag(
                          d.localPosition,
                          Size.square(size),
                        ),
                    child: CustomPaint(
                      key: widget.wheelKey,
                      size: Size.square(size),
                      painter: HueValueDiscPainter(
painter: HueValueDiscPainter(),
                      foregroundPainter: _WheelSelectionPainter(
                        hue: _hsv.hue,
                        saturation: _hsv.saturation,
                        value: _hsv.value,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: preview,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _hexFromArgb(preview.toARGB32()),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(width: 56, child: Text('Light')),
                Expanded(
                  child: Slider(
                    value: _hsv.value.clamp(0.0, 1.0),
                    min: 0,
                    max: 1,
                    onChanged: _handleValueSlider,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _hexFromArgb(int colorValue) {
    final rgb = colorValue & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

class _WheelSelectionPainter extends CustomPainter {
  const _WheelSelectionPainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  final double hue;
  final double saturation;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2;
    final center = Offset(size.width / 2, size.height / 2);

    final angleRad = hue * math.pi / 180.0;
    final r = radius * saturation;

    final p = Offset(
      center.dx + math.cos(angleRad) * r,
      center.dy + math.sin(angleRad) * r,
    );

    final outer =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white;

    final inner =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.black87;

    canvas.drawCircle(p, 10, outer);
    canvas.drawCircle(p, 10, inner);

    // center dot preview marker (tiny)
    final preview = HSVColor.fromAHSV(1, hue, saturation, value).toColor();
    final fill = Paint()..color = preview;
    canvas.drawCircle(p, 7, fill);
  }

  @override
  bool shouldRepaint(covariant _WheelSelectionPainter oldDelegate) {
    return oldDelegate.hue != hue ||
        oldDelegate.saturation != saturation ||
        oldDelegate.value != value;
  }
}

class _ColorChipsWrap extends StatelessWidget {
  const _ColorChipsWrap({required this.colors, required this.onRemove});

  final List<Color> colors;
  final void Function(int index)? onRemove;

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'No colors added yet',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < colors.length; i++)
          _ColorChip(
            color: colors[i],
            onRemove: onRemove == null ? null : () => onRemove!(i),
          ),
      ],
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({required this.color, this.onRemove});

  final Color color;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final hex =
        '#${(color.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
        color: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black12),
            ),
          ),
          const SizedBox(width: 8),
          Text(hex),
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.promptNumber,
    required this.promptText,
    required this.title,
    required this.colors,
  });

  final int promptNumber;
  final String promptText;
  final String title;
  final List<Color> colors;

  List<String> _buildGridHexes() {
    final slots = List<String>.filled(25, '#FFFFFF');
    final hexes =
        colors
            .map(
              (c) =>
                  '#${(c.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
            )
            .toList();

    for (int i = 0; i < hexes.length && i < _spiral5x5.length; i++) {
      slots[_spiral5x5[i]] = hexes[i];
    }
    return slots;
  }

  static final List<int> _spiral5x5 = _PartyFingerprintFlowState._spiral5x5;

  @override
  Widget build(BuildContext context) {
    final gridHexes = _buildGridHexes();

    return SizedBox(
      width: 320,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Prompt $promptNumber',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(promptText, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                title.isEmpty ? '(No title)' : title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
FingerprintGrid(
  answers: gridHexes,
  total: 5,
),            ],
          ),
        ),
      ),
    );
  }
}
