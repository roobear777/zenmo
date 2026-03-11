import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/fingerprint_questions.dart';
import '../state/fingerprint_state.dart';
import '../state/color_creation_state.dart';
import '../widgets/navigation_button.dart';
import '../widgets/color_square.dart';
import '../widgets/primary_button.dart';
import '../widgets/saved_palette_card.dart';
import 'add_color_screen.dart';
import 'swatch_details_screen.dart';

/// Palette detail screen for managing colors for a specific question
/// Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9, 4.10, 4.11, 6.4, 9.1, 12.9, 16.1, 16.2, 16.3, 16.5
class PaletteDetailScreen extends StatelessWidget {
  final int questionIndex;

  const PaletteDetailScreen({
    super.key,
    required this.questionIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<FingerprintState>(
      builder: (context, fingerprintState, child) {
        final answer = fingerprintState.getAnswer(questionIndex);
        final swatches = answer.swatches;
        final hasColors = swatches.isNotEmpty;
        final canAddColor = swatches.length < kMaxColorsPerQuestion;

        return Scaffold(
          backgroundColor: Colors.white, // Requirement 12.9
          body: SafeArea(
            child: Column(
              children: [
                // Top bar with back button
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      // Back button - Requirement 4.1
                      NavigationButton(
                        type: NavigationButtonType.back,
                        onPressed: () {
                          // Navigate to UnderstandScreen - Requirement 4.9
                          Navigator.of(context).pop();
                        },
                      ),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ),

                // Question text - Requirement 4.2
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    kFingerprintQuestions[questionIndex],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 24),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Color palette grid - Requirement 4.3
                        if (hasColors)
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: swatches.map((swatch) {
                            return ColorSquare(
                              color: swatch.color,
                              size: 70,
                              onTap: () {
                                // Navigate to SwatchDetailsScreen - Requirement 9.1
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => DraggableScrollableSheet(
                                    initialChildSize: 0.9,
                                    minChildSize: 0.5,
                                    maxChildSize: 0.95,
                                    builder: (context, scrollController) => SwatchDetailsScreen(
                                      swatch: swatch,
                                    ),
                                  ),
                                );
                              },
                            );
                            }).toList(),
                          ),

                        const SizedBox(height: 24),

                        // "+ Add a color" button - Requirement 4.4, 6.4
                        PrimaryButton(
                          label: '+ Add a color',
                          fullWidth: true,
                          onPressed: canAddColor
                              ? () {
                                  // Navigate to AddColorScreen - Requirement 4.10
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => ChangeNotifierProvider(
                                        create: (_) => ColorCreationState(),
                                        child: AddColorScreen(
                                          questionIndex: questionIndex,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              : null, // Disabled when 5 colors exist
                        ),

                        const SizedBox(height: 32),

                        // Saved palettes section - Requirements 4.5, 4.6, 16.1, 16.2
                        if (!hasColors) ...[
                          // Show example palettes when empty - Requirement 16.1
                          const Text(
                            'Example Palettes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildExamplePalettesGrid(),
                        ],

                        const SizedBox(height: 80), // Space for home button
                      ],
                    ),
                  ),
                ),

                // Home button at bottom - Requirement 4.8
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: NavigationButton(
                    type: NavigationButtonType.home,
                    onPressed: () {
                      // Navigate to InitialLogoScreen - Requirement 4.11
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

  /// Builds the 3-column grid of example saved palettes
  /// Requirements: 16.1, 16.3, 16.5
  Widget _buildExamplePalettesGrid() {
    final examplePalettes = [
      _ExamplePalette(
        'Need more sleep',
        [
          const Color(0xFF2D3748),
          const Color(0xFF4A5568),
          const Color(0xFF718096),
        ],
      ),
      _ExamplePalette(
        'Passsssion',
        [
          const Color(0xFFE53E3E),
          const Color(0xFFF56565),
          const Color(0xFFFC8181),
        ],
      ),
      _ExamplePalette(
        'No thanks gran...',
        [
          const Color(0xFF38B2AC),
          const Color(0xFF4FD1C5),
          const Color(0xFF81E6D9),
        ],
      ),
      _ExamplePalette(
        'Spring Blooms A...',
        [
          const Color(0xFFED64A6),
          const Color(0xFFF687B3),
          const Color(0xFFFBB6CE),
        ],
      ),
      _ExamplePalette(
        'Deserunt ut ut dui',
        [
          const Color(0xFF9F7AEA),
          const Color(0xFFB794F4),
          const Color(0xFFD6BCFA),
        ],
      ),
      _ExamplePalette(
        '[add an answer]',
        [
          const Color(0xFFEDF2F7),
          const Color(0xFFE2E8F0),
          const Color(0xFFCBD5E0),
        ],
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, // 3-column grid - Requirement 16.3
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: examplePalettes.length,
      itemBuilder: (context, index) {
        final palette = examplePalettes[index];
        return SavedPaletteCard(
          title: palette.title,
          colors: palette.colors,
          onTap: () {
            // Example palettes are non-interactive - Requirement 16.5
          },
        );
      },
    );
  }
}

/// Helper class for example palette data
class _ExamplePalette {
  final String title;
  final List<Color> colors;

  _ExamplePalette(this.title, this.colors);
}
