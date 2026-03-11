import 'package:flutter/material.dart';
import 'color_square.dart';

/// A card widget representing a single question with expandable/collapsible states
/// Requirements: 2.3, 2.4, 2.5, 15.2
class QuestionCard extends StatelessWidget {
  final int questionIndex;
  final String questionText;
  final bool isExpanded;
  final bool isCompleted;
  final List<Color> palettePreview; // Up to 4 colors
  final VoidCallback onTap;

  const QuestionCard({
    super.key,
    required this.questionIndex,
    required this.questionText,
    required this.isExpanded,
    required this.isCompleted,
    required this.palettePreview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCompleted ? const Color(0xFF6366F1) : Colors.grey.shade300,
            width: isCompleted ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Question number badge
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isCompleted 
                        ? const Color(0xFF6366F1) 
                        : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${questionIndex + 1}',
                      style: TextStyle(
                        color: isCompleted ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // Question text
                Expanded(
                  child: Text(
                    questionText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isCompleted ? FontWeight.w600 : FontWeight.normal,
                      color: Colors.black87,
                    ),
                  ),
                ),
                
                // Completion indicator
                if (isCompleted)
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF6366F1),
                    size: 24,
                  ),
              ],
            ),
            
            // Palette preview when expanded
            if (isExpanded && palettePreview.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  for (int i = 0; i < palettePreview.length && i < 4; i++) ...[
                    ColorSquare(
                      color: palettePreview[i],
                      size: 48,
                    ),
                    if (i < palettePreview.length - 1 && i < 3)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
