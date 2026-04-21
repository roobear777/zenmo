import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/fingerprint_questions.dart';
import '../state/fingerprint_state.dart';
import '../widgets/color_square.dart';
import '../widgets/navigation_button.dart';

/// Summary screen showing all completed question answers.
/// Requirements: 11.1, 11.2, 11.3, 2.1, 2.2, 2.8, 2.9, 2.10
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {

  @override
  Widget build(BuildContext context) {
    return Consumer<FingerprintState>(
      builder: (context, fingerprintState, _) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: [
                // Back to hexagon screen
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: NavigationButton(
                      type: NavigationButtonType.hexagon,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),

                // Scrollable content
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: kFingerprintTotalQuestions,
                    itemBuilder: (context, index) {
                      final answer = fingerprintState.getAnswer(index);
                      final questionText = kFingerprintQuestions[index];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Question ${index + 1}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6366F1),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              questionText,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (answer.swatches.isEmpty)
                              const Text(
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                            style: const TextStyle(
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

              ],
            ),
          ),
        );
      },
    );
  }
}
