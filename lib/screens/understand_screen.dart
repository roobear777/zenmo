import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/fingerprint_questions.dart';
import '../state/fingerprint_state.dart';
import '../state/question_progress_tracker.dart';
import '../widgets/navigation_button.dart';
import '../widgets/question_card.dart';
import 'palette_detail_screen.dart';
import 'summary_screen.dart';

/// Questions overview screen showing all 5 questions with expandable cards
/// Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 3.2, 3.4, 12.9, 15.1, 15.3, 15.5
class UnderstandScreen extends StatefulWidget {
  const UnderstandScreen({super.key});

  @override
  State<UnderstandScreen> createState() => _UnderstandScreenState();
}

class _UnderstandScreenState extends State<UnderstandScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<FingerprintState>(
      builder: (context, fingerprintState, child) {
        final currentQuestionIndex = fingerprintState.currentQuestionIndex;
        final allComplete = fingerprintState.allQuestionsComplete;
        final progressTracker = QuestionProgressTracker(fingerprintState);

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: [
                // Top bar with back button and title
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      // Back button - Requirement 2.1
                      NavigationButton(
                        type: NavigationButtonType.back,
                        onPressed: () {
                          // Navigate to InitialLogoScreen - Requirement 2.8
                          Navigator.of(context).pop();
                        },
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Party Questions', // Requirement 2.2
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      // Spacer to balance the back button
                      const SizedBox(width: 48),
                    ],
                  ),
                ),

                // Question cards - Requirement 2.3
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: kFingerprintTotalQuestions,
                    itemBuilder: (context, index) {
                      final answer = fingerprintState.getAnswer(index);
                      final isCompleted = fingerprintState.isQuestionComplete(index);
                      final isExpanded = index == currentQuestionIndex;
                      final canAccess = progressTracker.canAccessQuestion(index);
                      
                      // Get palette preview colors (up to 4)
                      final palettePreview = answer.swatches
                          .take(4)
                          .map((swatch) => swatch.color)
                          .toList();

                      return QuestionCard(
                        questionIndex: index,
                        questionText: kFingerprintQuestions[index],
                        isExpanded: isExpanded, // Requirement 2.4, 2.5, 15.3
                        isCompleted: isCompleted, // Requirement 15.1, 15.5
                        palettePreview: palettePreview,
                        onTap: () {
                          // Enforce sequential access - Requirement 3.1, 3.5
                          if (!canAccess) {
                            // Show message that previous question must be completed first
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Please complete Question $index first',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                            return;
                          }
                          
                          // Update current question index
                          fingerprintState.currentQuestionIndex = index;
                          
                          // Navigate to PaletteDetailScreen - Requirement 3.2
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => PaletteDetailScreen(
                                questionIndex: index,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                // Bottom section with chevron and home icon
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Chevron down icon - Requirement 2.6
                      if (!allComplete)
                        const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.grey,
                          size: 32,
                        ),
                      
                      // Navigate to Summary button when all complete - Requirement 3.4
                      if (allComplete)
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const SummaryScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('View Summary'),
                        ),
                      
                      const SizedBox(height: 8),
                      
                      // Home icon - Requirement 2.7
                      NavigationButton(
                        type: NavigationButtonType.home,
                        onPressed: () {
                          // Navigate to InitialLogoScreen - Requirement 2.9
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        },
                      ),
                    ],
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
