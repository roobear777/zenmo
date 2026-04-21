import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/fingerprint_questions.dart';
import '../state/fingerprint_state.dart';
import '../state/shared_prompts_state.dart';
import '../widgets/navigation_button.dart';
import 'add_color_screen.dart';
import 'summary_screen.dart';

class UnderstandScreen extends StatefulWidget {
  const UnderstandScreen({super.key});

  @override
  State<UnderstandScreen> createState() => _UnderstandScreenState();
}

class _UnderstandScreenState extends State<UnderstandScreen> {
  int? _selectedIndex;
  String? _selectedSharedLabel;

  void _selectHex(int index, FingerprintState fs) {
    setState(() { _selectedIndex = index; _selectedSharedLabel = null; });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _selectedIndex = null);
      fs.currentQuestionIndex = index;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AddColorScreen(questionIndex: index),
      ));
    });
  }

  void _selectSharedHex(int sharedIndex, String label, FingerprintState fs) {
    // shared prompts use indices starting at kFingerprintTotalQuestions
    final stateIndex = kFingerprintTotalQuestions + sharedIndex;
    setState(() { _selectedSharedLabel = label; _selectedIndex = null; });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _selectedSharedLabel = null);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AddColorScreen(questionIndex: stateIndex),
      ));
    });
  }

  Future<void> _showAddPromptDialog(SharedPromptsState sps) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Add a prompt', style: TextStyle(fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. First love, A dream...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isNotEmpty) await sps.addPrompt(text);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<FingerprintState, SharedPromptsState>(
      builder: (context, fs, sps, _) {
        final anyComplete = fs.anyQuestionComplete;

        // Build the full flat list of hex items
        // Each item: (label, chosenColors, isCompleted, onTap)
        final List<_HexItem> items = [
          // Fixed prompts
          ...List.generate(kFingerprintTotalQuestions, (i) => _HexItem(
            label: kFingerprintQuestions[i],
            chosenColors: fs.getAnswer(i).swatches.map((s) => s.color).toList(),
            isCompleted: fs.isQuestionComplete(i),
            onTap: () => _selectHex(i, fs),
          )),
          // Shared prompts from Firestore
          ...List.generate(sps.prompts.length, (i) {
            final stateIndex = kFingerprintTotalQuestions + i;
            return _HexItem(
              label: sps.prompts[i],
              chosenColors: fs.getAnswer(stateIndex).swatches.map((s) => s.color).toList(),
              isCompleted: fs.isQuestionComplete(stateIndex),
              onTap: () => _selectSharedHex(i, sps.prompts[i], fs),
            );
          }),
        ];

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(
                        children: [
                          NavigationButton(
                            type: NavigationButtonType.back,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),

                    // Scrollable honeycomb wall
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final availW = constraints.maxWidth - 32;
                          final r = availW / (3 * math.sqrt(3));
                          return SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            child: _HoneycombWall(
                              hexRadius: r,
                              items: items,
                              onAddTap: () => _showAddPromptDialog(sps),
                            ),
                          );
                        },
                      ),
                    ),

                    // View Answers button
                    if (anyComplete)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SummaryScreen()),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('View Answers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                  ],
                ),

                // Focus overlay
                if (_selectedIndex != null || _selectedSharedLabel != null)
                  AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      color: Colors.white,
                      child: Center(
                        child: _HexTile(
                          radius: 110,
                          chosenColors: _selectedIndex != null
                              ? fs.getAnswer(_selectedIndex!).swatches.map((s) => s.color).toList()
                              : [],
                          label: _selectedIndex != null
                              ? kFingerprintQuestions[_selectedIndex!]
                              : (_selectedSharedLabel ?? ''),
                          isCompleted: _selectedIndex != null
                              ? fs.isQuestionComplete(_selectedIndex!)
                              : false,
                        ),
                      ),
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

// ---------------------------------------------------------------------------
// Data class for a hex item
// ---------------------------------------------------------------------------

class _HexItem {
  final String label;
  final List<Color> chosenColors;
  final bool isCompleted;
  final VoidCallback onTap;
  const _HexItem({required this.label, required this.chosenColors, required this.isCompleted, required this.onTap});
}

// ---------------------------------------------------------------------------
// Scrollable honeycomb wall — rows of 3 and 2, offset alternating
// ---------------------------------------------------------------------------

class _HoneycombWall extends StatelessWidget {
  const _HoneycombWall({
    required this.hexRadius,
    required this.items,
    required this.onAddTap,
  });

  final double hexRadius;
  final List<_HexItem> items;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context) {
    final r = hexRadius;
    final hexW = math.sqrt(3) * r;
    final hexH = 2 * r;
    final rowStep = 1.5 * r;
    final totalW = 3 * hexW;

    // All items + the "+" add hex at the end
    final allItems = [...items, null]; // null = add button
    final int total = allItems.length;

    // Layout: row 0 = 3 wide (no offset), row 1 = 2 wide (offset hexW/2), repeating
    // We pack items left-to-right into this pattern
    final List<Widget> positioned = [];
    int idx = 0;
    int row = 0;
    double maxY = 0;

    while (idx < total) {
      final bool isWideRow = row % 2 == 0;
      final int count = isWideRow ? 3 : 2;
      final double xOffset = isWideRow ? 0 : hexW / 2;
      final double y = row * rowStep;

      for (int col = 0; col < count && idx < total; col++, idx++) {
        final double x = xOffset + col * hexW;
        final double cy = y + hexH / 2;
        final item = allItems[idx];

        final Widget tile = item == null
            ? GestureDetector(
                onTap: onAddTap,
                child: _CustomHexTile(radius: r, label: null),
              )
            : GestureDetector(
                onTap: item.onTap,
                child: _HexTile(
                  radius: r,
                  chosenColors: item.chosenColors,
                  label: item.label,
                  isCompleted: item.isCompleted,
                ),
              );

        positioned.add(Positioned(
          left: x,
          top: cy - hexH / 2,
          child: tile,
        ));

        final bottom = cy + hexH / 2;
        if (bottom > maxY) maxY = bottom;
      }
      row++;
    }

    return SizedBox(
      width: totalW,
      height: maxY,
      child: Stack(children: positioned),
    );
  }
}

// ---------------------------------------------------------------------------
// Hex tiles & painter (unchanged)
// ---------------------------------------------------------------------------

class _HexTile extends StatelessWidget {
  const _HexTile({
    required this.radius,
    required this.chosenColors,
    required this.label,
    required this.isCompleted,
  });

  final double radius;
  final List<Color> chosenColors;
  final String label;
  final bool isCompleted;

  @override
  Widget build(BuildContext context) {
    final w = math.sqrt(3) * radius;
    final h = 2 * radius;
    return SizedBox(
      width: w,
      height: h,
      child: CustomPaint(
        painter: _HexPainter(chosenColors: chosenColors),
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: radius * 0.2),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black87,
                fontSize: radius * 0.24,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
                height: 1.25,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomHexTile extends StatelessWidget {
  const _CustomHexTile({required this.radius, required this.label});
  final double radius;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final w = math.sqrt(3) * radius;
    final h = 2 * radius;
    return SizedBox(
      width: w,
      height: h,
      child: CustomPaint(
        painter: _HexPainter(chosenColors: const [], outlined: true),
        child: Center(
          child: label != null
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: radius * 0.2),
                  child: Text(label!, textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: radius * 0.22, fontWeight: FontWeight.w500, height: 1.25)),
                )
              : Icon(Icons.add, color: Colors.black38, size: radius * 0.5),
        ),
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  const _HexPainter({required this.chosenColors, this.outlined = false});
  final List<Color> chosenColors;
  final bool outlined;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _hexPath(size);
    if (chosenColors.isEmpty) {
      canvas.drawPath(path, Paint()..color = Colors.white);
    } else if (chosenColors.length == 1) {
      canvas.drawPath(path, Paint()..color = chosenColors.first);
    } else {
      final n = chosenColors.length;
      final sliceW = size.width / n;
      for (int i = 0; i < n; i++) {
        canvas.save();
        canvas.clipPath(path);
        canvas.drawRect(Rect.fromLTWH(i * sliceW, 0, sliceW, size.height), Paint()..color = chosenColors[i]);
        canvas.restore();
      }
    }
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF555555)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  Path _hexPath(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.height / 2;
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = math.pi / 6 + math.pi / 3 * i;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_HexPainter old) =>
      old.chosenColors != chosenColors || old.outlined != outlined;
}
