import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/color_creation_state.dart';
import '../state/fingerprint_state.dart';
import '../widgets/navigation_button.dart';
import '../widgets/color_square.dart';
import '../widgets/primary_button.dart';
import '../widgets/color_picker/color_picker_widget.dart';
import 'color_adjuster_screen.dart';

/// Screen for creating a new color with title and note
/// Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 5.10, 5.11, 5.12, 6.1, 6.2, 6.3, 8.1, 8.2, 8.3, 8.5, 12.9, 18.4
class AddColorScreen extends StatefulWidget {
  final int questionIndex;

  const AddColorScreen({
    super.key,
    required this.questionIndex,
  });

  @override
  State<AddColorScreen> createState() => _AddColorScreenState();
}

class _AddColorScreenState extends State<AddColorScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  String? _titleError;

  @override
  void initState() {
    super.initState();
    // Initialize controllers with current state
    final colorCreationState = context.read<ColorCreationState>();
    _titleController.text = colorCreationState.title;
    _noteController.text = colorCreationState.note;

    // Listen to controller changes and update state
    _titleController.addListener(() {
      colorCreationState.updateTitle(_titleController.text);
      if (_titleError != null && _titleController.text.trim().isNotEmpty) {
        setState(() {
          _titleError = null;
        });
      }
    });

    _noteController.addListener(() {
      colorCreationState.updateNote(_noteController.text);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _openColorPicker() {
    final colorCreationState = context.read<ColorCreationState>();
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select a Color',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 300,
                height: 300,
                child: ColorPickerWidget(
                  currentColor: colorCreationState.selectedColor,
                  onColorChanged: (color) {
                    colorCreationState.updateColor(color);
                  },
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Done',
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToColorAdjuster() {
    // Navigate to ColorAdjusterScreen - Requirement 5.10
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ColorAdjusterScreen(),
      ),
    );
  }

  void _saveColor() {
    final colorCreationState = context.read<ColorCreationState>();
    
    // Validate title - Requirement 6.1
    if (!colorCreationState.isValid) {
      setState(() {
        _titleError = 'Title is required';
      });
      return;
    }

    // Save color to question palette - Requirement 6.2
    final fingerprintState = context.read<FingerprintState>();
    final swatch = colorCreationState.toColorSwatch();
    fingerprintState.addColorToQuestion(widget.questionIndex, swatch);

    // Reset state for next color creation
    colorCreationState.reset();

    // Navigate back to PaletteDetailScreen - Requirement 6.3
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorCreationState>(
      builder: (context, colorCreationState, child) {
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
                      // Back button - Requirement 5.1
                      NavigationButton(
                        type: NavigationButtonType.back,
                        onPressed: () {
                          // Navigate to PaletteDetailScreen (discard changes) - Requirement 5.11
                          Navigator.of(context).pop();
                        },
                      ),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ),

                // Title - Requirement 5.2
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    'Adding a Color',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title input - Requirement 5.3
                        const Text(
                          'Title (required)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            hintText: 'Enter color title',
                            errorText: _titleError,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Two-column layout - Requirement 5.4
                        Row(
                          children: [
                            // Left: Color preview - Requirement 5.5
                            Expanded(
                              child: GestureDetector(
                                onTap: _navigateToColorAdjuster,
                                child: Column(
                                  children: [
                                    ColorSquare(
                                      color: colorCreationState.selectedColor,
                                      size: 120,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'PREVIEW',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Tap to fine tune\nyour color',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(width: 16),

                            // Right: Color wheel - Requirement 5.6
                            Expanded(
                              child: GestureDetector(
                                onTap: _openColorPicker,
                                child: Column(
                                  children: [
                                    Container(
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(60),
                                        border: Border.all(
                                          color: Colors.grey[300]!,
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.palette,
                                        size: 48,
                                        color: Colors.grey[400],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Color Wheel',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Drag to Select',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Note textarea - Requirement 5.7
                        const Text(
                          'Note to Self (Optional/ for your eyes only)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _noteController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Add a note...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // SAVE button - Requirement 5.8
                        PrimaryButton(
                          label: 'SAVE',
                          fullWidth: true,
                          onPressed: _saveColor,
                        ),

                        const SizedBox(height: 80), // Space for home button
                      ],
                    ),
                  ),
                ),

                // Home button at bottom - Requirement 5.9
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: NavigationButton(
                    type: NavigationButtonType.home,
                    onPressed: () {
                      // Navigate to InitialLogoScreen (preserve draft state) - Requirement 5.12, 18.4
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
