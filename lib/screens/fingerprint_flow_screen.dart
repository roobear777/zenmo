import 'package:flutter/material.dart';
import '../config/fingerprint_questions.dart';
import '../models/fingerprint_answer.dart';
import '../widgets/simple_color_picker.dart';

class FingerprintFlowScreen extends StatefulWidget {
  final List<FingerprintAnswer>? initialAnswers;
  final int? startAtIndex;

  const FingerprintFlowScreen({
    super.key,
    this.initialAnswers,
    this.startAtIndex,
  });

  @override
  State<FingerprintFlowScreen> createState() => _FingerprintFlowScreenState();
}

class _FingerprintFlowScreenState extends State<FingerprintFlowScreen> {
  late List<FingerprintAnswer> _answers;
  late int _currentIndex;

  Color _selectedColor = Colors.blue;
  List<Color> _pickedColors = [];
  final TextEditingController _titleController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _answers = widget.initialAnswers ?? [];
    _currentIndex = widget.startAtIndex ?? _answers.length;

    if (_currentIndex < kFingerprintTotalQuestions) {
      _loadQuestion(_currentIndex);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _loadQuestion(int index) {
    if (index >= _answers.length) {
      // New question - reset
      _pickedColors = [];
      _selectedColor = Colors.blue;
      _titleController.text = '';
      return;
    }

    // Load existing answer
    final answer = _answers[index];
    _pickedColors = answer.colors.map((c) => Color(c)).toList();
    _selectedColor = _pickedColors.isNotEmpty
        ? _pickedColors.last
        : Colors.blue;
    _titleController.text = answer.title;
    setState(() {});
  }

  void _addColor() {
    if (_pickedColors.length >= kMaxColorsPerQuestion) {
      _showMessage('Maximum $kMaxColorsPerQuestion colors per question');
      return;
    }

    if (_pickedColors.any((c) => c.value == _selectedColor.value)) {
      _showMessage('Color already added');
      return;
    }

    setState(() {
      _pickedColors = [..._pickedColors, _selectedColor];
    });
  }

  void _removeColor(int index) {
    setState(() {
      _pickedColors = List.from(_pickedColors)..removeAt(index);
      if (_pickedColors.isNotEmpty) {
        _selectedColor = _pickedColors.last;
      }
    });
  }

  bool _isCurrentQuestionValid() {
    return _titleController.text.trim().isNotEmpty && _pickedColors.isNotEmpty;
  }

  void _saveCurrentAnswer() {
    final answer = FingerprintAnswer(
      title: _titleController.text.trim(),
      colors: _pickedColors.map((c) => c.value).toList(),
      hexes: _pickedColors.map(_colorToHex).toList(),
    );

    if (_currentIndex < _answers.length) {
      _answers[_currentIndex] = answer;
    } else {
      _answers.add(answer);
    }
  }

  Future<void> _goNext() async {
    if (!_isCurrentQuestionValid()) {
      _showMessage('Please add at least one color and a title');
      return;
    }

    setState(() => _isSaving = true);

    try {
      _saveCurrentAnswer();

      // TODO: Save to database here
      await Future.delayed(const Duration(milliseconds: 300));

      if (_currentIndex == kFingerprintTotalQuestions - 1) {
        // Last question - go to summary
        _goToSummary();
      } else {
        // Next question
        setState(() {
          _currentIndex++;
          _loadQuestion(_currentIndex);
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _goBack() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _loadQuestion(_currentIndex);
      });
    }
  }

  void _goToSummary() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _SummaryScreen(answers: _answers)),
    );
  }

  Future<void> _saveAndQuit() async {
    setState(() => _isSaving = true);

    try {
      _saveCurrentAnswer();

      // TODO: Save draft to database
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _colorToHex(Color color) {
    return '#${(color.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    if (_currentIndex >= kFingerprintTotalQuestions) {
      return _SummaryScreen(answers: _answers);
    }

    final question = kFingerprintQuestions[_currentIndex];
    final progress = (_currentIndex + 1) / kFingerprintTotalQuestions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Fingerprint'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveAndQuit,
            child: const Text('Save & Quit'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Question ${_currentIndex + 1} of $kFingerprintTotalQuestions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Question text
                    Text(
                      question,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),

                    // Color picker (Marc will replace this)
                    SimpleColorPicker(
                      currentColor: _selectedColor,
                      onColorChanged: (color) {
                        setState(() => _selectedColor = color);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Add color button
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _addColor,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Color'),
                    ),
                    const SizedBox(height: 16),

                    // Selected colors
                    Text(
                      'Selected Colors (${_pickedColors.length}/$kMaxColorsPerQuestion)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),

                    if (_pickedColors.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'No colors added yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(_pickedColors.length, (index) {
                          final color = _pickedColors[index];
                          return Chip(
                            avatar: CircleAvatar(backgroundColor: color),
                            label: Text(_colorToHex(color)),
                            onDeleted: _isSaving
                                ? null
                                : () => _removeColor(index),
                          );
                        }),
                      ),

                    const SizedBox(height: 24),

                    // Title input
                    TextField(
                      controller: _titleController,
                      enabled: !_isSaving,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Title for this answer',
                        hintText: 'e.g., Childhood summers',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Navigation buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_currentIndex > 0)
                    OutlinedButton(
                      onPressed: _isSaving ? null : _goBack,
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _isSaving ? null : _goNext,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _currentIndex == kFingerprintTotalQuestions - 1
                                ? 'Finish'
                                : 'Next',
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
}

// Summary screen
class _SummaryScreen extends StatelessWidget {
  final List<FingerprintAnswer> answers;

  const _SummaryScreen({required this.answers});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fingerprint Complete')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: answers.length,
                itemBuilder: (context, index) {
                  final answer = answers[index];
                  final question = kFingerprintQuestions[index];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Question ${index + 1}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            question,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            answer.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: answer.colors.map((colorValue) {
                              final color = Color(colorValue);
                              return Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
