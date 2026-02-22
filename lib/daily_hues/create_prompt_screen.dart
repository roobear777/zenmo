import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/daily_clock.dart';
import '../services/analytics.dart';

// Repos
import '../services/question_repository.dart';
import '../services/firestore/question_repository_firestore.dart';

class CreatePromptScreen extends StatefulWidget {
  const CreatePromptScreen({super.key});
  static const routeName = '/createPrompt';

  @override
  State<CreatePromptScreen> createState() => _CreatePromptScreenState();
}

class _CreatePromptScreenState extends State<CreatePromptScreen> {
  final _clock = DailyClock();
  late final QuestionRepository _repo;

  final _ctrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _repo = QuestionRepositoryFirestore(firestore: FirebaseFirestore.instance);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || text.length > 150) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prompt must be 1–150 characters')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final id = await _repo.createQuestion(
        text: text,
        localDay: _clock.localDay,
      );
      AnalyticsService.logEvent(
        'question_create_submit',
        parameters: {'id': id},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Question posted')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final msg =
          (e is FirebaseException && e.code == 'permission-denied')
              ? 'You don’t have permission to post questions.'
              : 'Failed to post: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add a Question')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Find out what’s on your friends’ minds — your question will appear as a '?' tile today.",
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                maxLength: 150,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Question for the Daily Hues',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submitting ? null : _submit,
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
          ),
        ),
      ),
    );
  }
}
