// lib/daily_hues/answer_question_shell.dart
import 'package:flutter/material.dart';

class AnswerQuestionShell extends StatelessWidget {
  final String questionId;
  const AnswerQuestionShell({super.key, required this.questionId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Answer')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Answer flow arrives in Sprint 2.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text('Question ID: $questionId'),
          ],
        ),
      ),
    );
  }
}
