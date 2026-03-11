import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/fingerprint_questions.dart';
import '../state/fingerprint_state.dart';
import '../widgets/color_square.dart';
import '../widgets/primary_button.dart';

/// Summary screen showing all completed question answers
/// Requirements: 11.1, 11.2, 11.3
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FingerprintState>(
      builder: (context, fingerprintState, child) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Your Party Fingerprint',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),

                // Scrollable content with all questions and their palettes
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: kFingerprintTotalQuestions,
                    itemBuilder: (context, index) {
                      final answer = fingerprintState.getAnswer(index);
                      final questionText = kFingerprintQuestions[index];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Question text
                            Text(
                              'Question ${index + 1}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6366F1),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              questionText,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Color palette display
                            if (answer.swatches.isEmpty)
                              Text(
                                'No colors selected',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: answer.swatches.map((swatch) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ColorSquare(
                                        color: swatch.color,
                                        size: 60,
                                      ),
                                      if (swatch.title.isNotEmpty)
                                        SizedBox(
                                          width: 60,
                                          child: Text(
                                            swatch.title,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.black87,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  );
                                }).toList(),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Done button at the bottom
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: PrimaryButton(
                    label: 'Done',
                    fullWidth: true,
                    onPressed: () {
                      // Navigate to InitialLogoScreen - Requirement 11.3
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
