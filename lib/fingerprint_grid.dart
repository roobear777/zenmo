import 'package:flutter/material.dart';
import 'dart:math' as math;

/// FingerprintGrid: renders a square grid of answers.
/// - Empty slots show a plain alternating grey pattern.
/// - Filled slots show the chosen color.
/// - Optional [placementOrder] maps answer index -> cell index (row-major).
/// - Optional [onTileTap] lets the parent know which cell (and which answer index) was tapped.
class FingerprintGrid extends StatelessWidget {
  const FingerprintGrid({
    super.key,
    required this.answers, // ARGB ints in question order (dense prefix)
    required this.total,
    this.cornerRadius = 8,
    this.borderColor = Colors.transparent,
    this.borderWidth = 0,
    this.gap = 0,
    this.forceCols,
    this.placementOrder,
    this.onTileTap, // NEW
  });

  final List<int> answers;
  final int total;

  final double cornerRadius;
  final Color borderColor;
  final double borderWidth;
  final double gap;
  final int? forceCols;

  /// answer index -> cell index (row-major)
  final List<int>? placementOrder;

  /// callback with (cellIndex, answerIndex or null if empty)
  final void Function(int cellIndex, int? answerIndex)? onTileTap;

  @override
  Widget build(BuildContext context) {
    final cols = forceCols ?? _bestCols(total);
    const light = Color(0xFFEDEDEF);
    const dark = Color(0xFFDCDDE2);

    final double tileRadius = gap > 0 ? 6.0 : 0.0;

    // Build inverse map: cellIndex -> answerIndex
    final Map<int, int> cellToAnswerIndex = <int, int>{};
    if (placementOrder != null && placementOrder!.isNotEmpty) {
      final bound = math.min(
        answers.length,
        math.min(placementOrder!.length, total),
      );
      for (int ai = 0; ai < bound; ai++) {
        final cell = placementOrder![ai];
        if (cell >= 0 && cell < total) cellToAnswerIndex[cell] = ai;
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(cornerRadius),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: borderWidth),
          borderRadius: BorderRadius.circular(cornerRadius),
        ),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.all(gap > 0 ? gap : 0),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            childAspectRatio: 1,
          ),
          itemCount: total,
          itemBuilder: (_, i) {
            int? aIndex;
            if (cellToAnswerIndex.isNotEmpty) {
              aIndex = cellToAnswerIndex[i];
            } else {
              if (i < answers.length) aIndex = i;
            }

            final filled = aIndex != null;
            final row = i ~/ cols;
            final col = i % cols;
            final bg = ((row + col) & 1) == 0 ? light : dark;
            final color = filled ? Color(answers[aIndex]) : bg;

            final Widget tile =
                tileRadius == 0
                    ? Container(color: color)
                    : ClipRRect(
                      borderRadius: BorderRadius.circular(tileRadius),
                      child: Container(color: color),
                    );

            if (onTileTap == null) return tile;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTileTap!(i, aIndex),
              child: tile,
            );
          },
        ),
      ),
    );
  }

  int _bestCols(int n) {
    final r = math.sqrt(n).round();
    return r.clamp(2, 10);
  }
}
