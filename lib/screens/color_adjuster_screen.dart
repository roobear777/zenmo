import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/color_creation_state.dart';
import '../widgets/navigation_button.dart';
import '../widgets/color_square.dart';
import '../widgets/primary_button.dart';

/// Screen for fine-tuning color using HSB sliders
/// Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 7.10, 8.4, 12.9
class ColorAdjusterScreen extends StatefulWidget {
  const ColorAdjusterScreen({super.key});

  @override
  State<ColorAdjusterScreen> createState() => _ColorAdjusterScreenState();
}

class _ColorAdjusterScreenState extends State<ColorAdjusterScreen> {
  late double _hue;
  late double _saturation;
  late double _brightness;

  @override
  void initState() {
    super.initState();
    // Initialize HSB values from current color - Requirement 8.4
    final colorCreationState = context.read<ColorCreationState>();
    _hue = colorCreationState.hue;
    _saturation = colorCreationState.saturation;
    _brightness = colorCreationState.brightness;
  }

  void _updateColor() {
    // Update ColorCreationState from HSB values - Requirement 7.7, 8.4
    final colorCreationState = context.read<ColorCreationState>();
    colorCreationState.updateFromHSB(_hue, _saturation, _brightness);
  }

  void _saveAndNavigateBack() {
    // Save adjusted color values and navigate to AddColorScreen - Requirement 7.8, 7.9
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorCreationState>(
      builder: (context, colorCreationState, child) {
        return Scaffold(
          backgroundColor: Colors.white, // Requirement 12.9
          body: SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      // Top bar with back button
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            // Back button - Requirement 7.1
                            NavigationButton(
                              type: NavigationButtonType.back,
                              onPressed: _saveAndNavigateBack, // Requirement 7.9
                            ),
                            const Expanded(child: SizedBox()),
                          ],
                        ),
                      ),

                      // Header with color title - Requirement 7.2
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(
                          'ADJUST: ${colorCreationState.title.isEmpty ? 'Color' : colorCreationState.title}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Large color preview square - Requirement 7.3
                      ColorSquare(
                        color: colorCreationState.selectedColor,
                        size: 200,
                      ),

                      const SizedBox(height: 48),

                      // HSB Sliders - Requirement 7.4
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                        child: Column(
                          children: [
                            // Hue slider
                            _buildSlider(
                              label: 'Hue',
                              value: _hue,
                              min: 0,
                              max: 360,
                              divisions: 360,
                              onChanged: (value) {
                                setState(() {
                                  _hue = value;
                                });
                                _updateColor(); // Real-time update - Requirement 7.7
                              },
                            ),

                            const SizedBox(height: 24),

                            // Saturation slider
                            _buildSlider(
                              label: 'Saturation',
                              value: _saturation,
                              min: 0,
                              max: 1,
                              divisions: 100,
                              onChanged: (value) {
                                setState(() {
                                  _saturation = value;
                                });
                                _updateColor(); // Real-time update - Requirement 7.7
                              },
                            ),

                            const SizedBox(height: 24),

                            // Brightness slider
                            _buildSlider(
                              label: 'Brightness',
                              value: _brightness,
                              min: 0,
                              max: 1,
                              divisions: 100,
                              onChanged: (value) {
                                setState(() {
                                  _brightness = value;
                                });
                                _updateColor(); // Real-time update - Requirement 7.7
                              },
                            ),

                            const SizedBox(height: 32),

                            // DONE button - Requirement 7.5
                            PrimaryButton(
                              label: 'DONE',
                              fullWidth: true,
                              onPressed: _saveAndNavigateBack, // Requirement 7.8
                            ),

                            const SizedBox(height: 16),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Home button at bottom - Requirement 7.6
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: NavigationButton(
                          type: NavigationButtonType.home,
                          onPressed: () {
                            // Navigate to InitialLogoScreen - Requirement 7.10
                            Navigator.of(context).popUntil((route) => route.isFirst);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            Text(
              label == 'Hue'
                  ? value.toStringAsFixed(0)
                  : (value * 100).toStringAsFixed(0),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF6366F1),
            inactiveTrackColor: Colors.grey[300],
            thumbColor: const Color(0xFF6366F1),
            overlayColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
