// lib/daily_hues/answer_question_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/daily_clock.dart';
import '../services/analytics.dart';
import '../services/moderation_service.dart';

// Repos
import '../services/question_repository.dart';
import '../services/firestore/question_repository_firestore.dart';
import '../services/firestore/answer_repository_firestore.dart';

// Picker screen (existing)
import '../color_picker_screen.dart';

class AnswerQuestionScreen extends StatefulWidget {
  final String questionId;
  const AnswerQuestionScreen({super.key, required this.questionId});

  @override
  State<AnswerQuestionScreen> createState() => _AnswerQuestionScreenState();
}

class _AnswerQuestionScreenState extends State<AnswerQuestionScreen> {
  final _clock = DailyClock();
  final QuestionRepository _qRepo = QuestionRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );
  final AnswerRepositoryFirestore _aRepo = AnswerRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );

  String? _promptText;
  bool _loading = true;

  Color? _pickedColor;
  final _titleCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = await _qRepo.getQuestionById(widget.questionId);
    setState(() {
      _promptText = q?.text ?? 'Prompt unavailable';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  String _colorToHex(Color c) =>
      '#${c.red.toRadixString(16).padLeft(2, '0')}${c.green.toRadixString(16).padLeft(2, '0')}${c.blue.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

  Future<void> _pickColor() async {
    final selected = await Navigator.of(context).push<Color>(
      MaterialPageRoute(
        builder: (_) => ColorPickerScreen(returnPickedColor: true),
      ),
    );
    if (selected != null) {
      setState(() => _pickedColor = selected);
    }
  }

  Future<void> _submit() async {
    if (_pickedColor == null) return;

    final title = _titleCtrl.text.trim();
    if (title.length > 25) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title must be ≤ 25 characters')),
      );
      return;
    }
    final modErr = ModerationService.validateTitle(title);
    if (modErr != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(modErr)));
      return;
    }

    // Precise per-user guard: only block if *my* doc exists.
    try {
      final already = await _aRepo.hasUserAnswered(widget.questionId);
      if (already) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You've already answered this one.")),
        );
        return;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to check prior answer: $e')),
      );
      return;
    }

    setState(() => _submitting = true);
    AnalyticsService.logEvent(
      'answer_submit',
      parameters: {'questionId': widget.questionId},
    );

    try {
      final id = await _aRepo.createAnswer(
        questionId: widget.questionId,
        colorHex: _colorToHex(_pickedColor!),
        title: title,
        localDay: _clock.localDay, // repo writes both localDay and utcDay
      );
      if (!mounted) return;
      Navigator.of(context).pop({
        'answerId': id,
        'questionId': widget.questionId,
        'colorHex': _colorToHex(_pickedColor!),
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);

      // Disambiguate duplicate guard from rules failures.
      if (e is FirebaseException && e.code == 'permission-denied') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Not allowed to submit this answer (permission-denied). '
              'This is a rules/config issue, not the duplicate guard.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to submit answer: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body =
        _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _promptText ?? '',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _pickedColor == null
                    ? OutlinedButton(
                      onPressed: _pickColor,
                      child: const Text('Pick a color'),
                    )
                    : _PreviewChip(color: _pickedColor!, onChange: _pickColor),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleCtrl,
                  maxLength: 25,
                  decoration: const InputDecoration(
                    labelText: 'Name this color (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed:
                      (_pickedColor != null && !_submitting) ? _submit : null,
                  child:
                      _submitting
                          ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('Submit'),
                ),
              ],
            );

    return Scaffold(
      appBar: AppBar(title: const Text('Answer')),
      body: SafeArea(child: body),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  final Color color;
  final VoidCallback onChange;
  const _PreviewChip({required this.color, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black26),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
        const Spacer(),
        TextButton(onPressed: onChange, child: const Text('Change')),
      ],
    );
  }
}
