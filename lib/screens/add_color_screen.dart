import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/color_creation_state.dart';
import '../state/fingerprint_state.dart';
import '../config/fingerprint_questions.dart';
import '../widgets/navigation_button.dart';
import '../widgets/primary_button.dart';
import '../widgets/color_picker/color_picker_widget.dart';
import '../services/firestore_fingerprint_service.dart';

class AddColorScreen extends StatefulWidget {
  final int questionIndex;
  const AddColorScreen({super.key, required this.questionIndex});

  @override
  State<AddColorScreen> createState() => _AddColorScreenState();
}

class _AddColorScreenState extends State<AddColorScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  String? _titleError;
  bool _showFineTune = false;
  bool _showNote = false;
  bool _colorPicked = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final ccs = context.read<ColorCreationState>();
    ccs.reset();
    _titleController.addListener(() {
      ccs.updateTitle(_titleController.text);
      if (_titleError != null && _titleController.text.trim().isNotEmpty) {
        setState(() => _titleError = null);
      }
    });
    _noteController.addListener(() => ccs.updateNote(_noteController.text));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _saveColor() {
    final ccs = context.read<ColorCreationState>();
    if (!ccs.isValid) { setState(() => _titleError = 'Title is required'); return; }
    context.read<FingerprintState>().addColorToQuestion(widget.questionIndex, ccs.toColorSwatch());
    ccs.reset();
    _titleController.clear();
    _noteController.clear();
    setState(() { _titleError = null; _showFineTune = false; _showNote = false; _colorPicked = false; });
  }

  Future<void> _saveAndSubmit() async {
    final ccs = context.read<ColorCreationState>();
    if (!ccs.isValid) { setState(() => _titleError = 'Title is required'); return; }
    final fs = context.read<FingerprintState>();
    fs.addColorToQuestion(widget.questionIndex, ccs.toColorSwatch());
    setState(() => _isSubmitting = true);
    try {
      await context.read<FirestoreFingerprintService>().submitFingerprint(fs);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
    if (mounted) Navigator.of(context).pop();
  }


  @override
  Widget build(BuildContext context) {
    return Consumer<ColorCreationState>(
      builder: (context, ccs, _) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      NavigationButton(
                        type: NavigationButtonType.hexagon,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      Consumer<FingerprintState>(
                        builder: (context, fs, _) {
                          final saved = fs
                              .getAnswer(widget.questionIndex)
                              .swatches
                              .map((s) => s.color)
                              .toList();
                          return _ColorPreviewRow(
                            savedColors: saved,
                            pickedColor: _colorPicked ? ccs.selectedColor : null,
                            onWheelTap: _colorPicked
                                ? () => setState(() => _colorPicked = false)
                                : null,
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Question prompt
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Consumer<FingerprintState>(
                    builder: (context, fs, _) {
                      final label = widget.questionIndex < kFingerprintQuestions.length
                          ? kFingerprintQuestions[widget.questionIndex]
                          : (fs.customPrompt ?? 'Your prompt');
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.black87)),
                      );
                    },
                  ),
                ),

                Expanded(
                  child: Column(
                    children: [
                          // Title field
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                            child: TextField(
                              controller: _titleController,
                              style: GoogleFonts.ibmPlexSans(fontSize: 16, color: Colors.black87),
                              decoration: InputDecoration(
                                hintText: 'Because this feels like…',
                                hintStyle: GoogleFonts.ibmPlexSans(fontSize: 16, color: Colors.black38),
                                errorText: _titleError,
                                errorStyle: GoogleFonts.ibmPlexSans(fontSize: 12),
                                border: InputBorder.none,
                                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.black12)),
                                focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
                              ),
                            ),
                          ),

                          // Wheel + side buttons
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Color wheel or big preview
                                Expanded(
                                  child: _colorPicked
                                      ? _BigColorPreview(
                                          color: ccs.selectedColor,
                                          onTap: () => setState(() => _colorPicked = false),
                                        )
                                      : AspectRatio(
                                          aspectRatio: 1,
                                          child: ColorPickerWidget(
                                            currentColor: ccs.selectedColor,
                                            onColorChanged: (c) {
                                              ccs.updateColor(c);
                                            },
                                            onPickComplete: () {
                                              if (!_colorPicked) setState(() => _colorPicked = true);
                                            },
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                // Side icon buttons
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _SideIconButton(
                                      icon: Icons.tune,
                                      active: _showFineTune,
                                      onTap: () => setState(() {
                                        _showFineTune = !_showFineTune;
                                        if (_showFineTune) _showNote = false;
                                      }),
                                    ),
                                    const SizedBox(height: 12),
                                    _SideIconButton(
                                      icon: Icons.chat_bubble_outline,
                                      active: _showNote,
                                      onTap: () => setState(() {
                                        _showNote = !_showNote;
                                        if (_showNote) _showFineTune = false;
                                      }),
                                    ),
                                    const SizedBox(height: 12),
                                    // Add another color — no outline, just icon
                                    GestureDetector(
                                      onTap: _saveColor,
                                      child: Container(
                                        width: 40, height: 40,
                                        alignment: Alignment.center,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Container(
                                              width: 22, height: 22,
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: SweepGradient(colors: [
                                                  Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
                                                  Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
                                                ]),
                                              ),
                                            ),
                                            const Icon(Icons.add, size: 14, color: Colors.white),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Expanded section: sliders or note
                          if (_showFineTune || _showNote)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                              child: _showFineTune
                                  ? _HsbSliders(colorCreationState: ccs)
                                  : TextField(
                                      controller: _noteController,
                                      maxLines: 3,
                                      decoration: InputDecoration(
                                        hintText: 'For your eyes only...',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      ),
                                    ),
                            ),

                          const Spacer(),

                          // Submit button at bottom
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                            child: PrimaryButton(
                              label: _isSubmitting ? '...' : '→',
                              fullWidth: true,
                              onPressed: _isSubmitting ? null : _saveAndSubmit,
                            ),
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

class _BigColorPreview extends StatelessWidget {
  const _BigColorPreview({required this.color, required this.onTap});
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
        child: const Center(
          child: Text('Tap to change', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ),
    ),
  );
}




class _ColorPreviewRow extends StatelessWidget {
  const _ColorPreviewRow({
    required this.savedColors,
    required this.pickedColor,
    required this.onWheelTap,
  });

  final List<Color> savedColors;
  final Color? pickedColor;   // non-null when user has picked but not yet saved
  final VoidCallback? onWheelTap; // non-null when showing wheel thumb

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Already-saved colors for this prompt
        ...savedColors.map((c) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.black12),
            ),
          ),
        )),
        // Current picker slot: wheel thumb if picked, empty box if not
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: onWheelTap != null
              ? GestureDetector(
                  onTap: onWheelTap,
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black12),
                      gradient: const SweepGradient(colors: [
                        Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
                        Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
                      ]),
                    ),
                  ),
                )
              : Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.black12),
                  ),
                ),
        ),
      ],
    );
  }
}


class _SideIconButton extends StatelessWidget {
  const _SideIconButton({required this.icon, required this.active, required this.onTap});
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF6366F1).withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 22, color: active ? const Color(0xFF6366F1) : Colors.black45),
    ),
  );
}


class _HsbSliders extends StatelessWidget {
  const _HsbSliders({required this.colorCreationState});
  final ColorCreationState colorCreationState;

  @override
  Widget build(BuildContext context) {
    final h = colorCreationState.hue;
    final s = colorCreationState.saturation;
    final b = colorCreationState.brightness;
    return Column(children: [
      _SliderRow(label: 'H', value: h, min: 0, max: 360, color: HSVColor.fromAHSV(1, h, 1, 1).toColor(), onChanged: (v) => colorCreationState.updateFromHSB(v, s, b)),
      const SizedBox(height: 8),
      _SliderRow(label: 'S', value: s, min: 0, max: 1, color: HSVColor.fromAHSV(1, h, s, 1).toColor(), onChanged: (v) => colorCreationState.updateFromHSB(h, v, b)),
      const SizedBox(height: 8),
      _SliderRow(label: 'B', value: b, min: 0, max: 1, color: HSVColor.fromAHSV(1, h, s, b).toColor(), onChanged: (v) => colorCreationState.updateFromHSB(h, s, v)),
    ]);
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.label, required this.value, required this.min, required this.max, required this.color, required this.onChanged});
  final String label;
  final double value, min, max;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(width: 16, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54))),
    const SizedBox(width: 8),
    Expanded(
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: color, thumbColor: color,
          inactiveTrackColor: Colors.black12, trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        ),
        child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
      ),
    ),
  ]);
}
