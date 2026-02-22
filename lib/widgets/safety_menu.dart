import 'package:flutter/material.dart';

Future<void> showZenmoSafetyMenu(
  BuildContext context, {
  required String initialLetter,
  required VoidCallback onReport,
  required VoidCallback onBlock,
  required VoidCallback onReportBlockDelete,
}) {
  return showGeneralDialog(
    context: context,
    barrierLabel: 'Safety menu',
    barrierDismissible: true,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, __) {
      final cardColor = const Color(0xFFB9BCC1); // soft grey like your mock
      final btnColor = const Color(0xFF5F6572); // slate buttons
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              // The card
              Container(
                width: 300,
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 12,
                      offset: Offset(0, 6),
                      color: Color(0x33000000),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    const Text(
                      'Something off-color\nabout this Zenmo?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Row of two small buttons
                    Row(
                      children: [
                        Expanded(
                          child: _SlateButton(
                            label: 'Report message',
                            color: btnColor,
                            onTap: () {
                              Navigator.pop(ctx);
                              onReport();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SlateButton(
                            label: 'Block sender',
                            color: btnColor,
                            onTap: () {
                              Navigator.pop(ctx);
                              onBlock();
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Wide bottom button
                    _SlateButton(
                      label: 'Report, Block, & Delete.',
                      color: btnColor,
                      onTap: () {
                        Navigator.pop(ctx);
                        onReportBlockDelete();
                      },
                      wide: true,
                    ),
                  ],
                ),
              ),

              // The top circular badge (overlapping the card border)
              Positioned(
                top: -18,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(color: Color(0x22000000), blurRadius: 6),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF5F6572), // grey/slate tone
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
    transitionBuilder: (_, animation, __, child) {
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

class _SlateButton extends StatelessWidget {
  const _SlateButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.wide = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final child = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        width: wide ? double.infinity : null,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              blurRadius: 1,
              offset: Offset(0, 1),
              color: Color(0x22000000),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );

    return Material(color: Colors.transparent, child: child);
  }
}
