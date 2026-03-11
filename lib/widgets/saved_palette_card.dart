import 'package:flutter/material.dart';

class SavedPaletteCard extends StatelessWidget {
  final String title;
  final List<Color> colors;
  final bool isPlaceholder;
  final VoidCallback? onTap;

  const SavedPaletteCard({
    super.key,
    required this.title,
    required this.colors,
    this.isPlaceholder = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: isPlaceholder
              ? Border.all(color: Colors.grey.shade300, width: 2)
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                if (isPlaceholder)
                  Center(
                    child: Icon(
                      Icons.add,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                  )
                else
                  _buildColorGrid(),
                if (!isPlaceholder)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorGrid() {
    if (colors.isEmpty) {
      return Container(color: Colors.grey.shade200);
    }

    // Display colors in a grid pattern
    return LayoutBuilder(
      builder: (context, constraints) {
        final colorCount = colors.length;
        
        if (colorCount == 1) {
          return Container(color: colors[0]);
        } else if (colorCount == 2) {
          return Row(
            children: colors.map((color) => Expanded(child: Container(color: color))).toList(),
          );
        } else if (colorCount == 3) {
          return Row(
            children: [
              Expanded(child: Container(color: colors[0])),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: Container(color: colors[1])),
                    Expanded(child: Container(color: colors[2])),
                  ],
                ),
              ),
            ],
          );
        } else if (colorCount == 4) {
          return Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: Container(color: colors[0])),
                    Expanded(child: Container(color: colors[1])),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: Container(color: colors[2])),
                    Expanded(child: Container(color: colors[3])),
                  ],
                ),
              ),
            ],
          );
        } else {
          // 5 or more colors
          return Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: Container(color: colors[0])),
                    Expanded(child: Container(color: colors[1])),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: Container(color: colors[2])),
                    Expanded(child: Container(color: colors[3])),
                    Expanded(child: Container(color: colors.length > 4 ? colors[4] : colors[3])),
                  ],
                ),
              ),
            ],
          );
        }
      },
    );
  }
}
