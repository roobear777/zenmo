import 'package:flutter/material.dart';

class ColorSquare extends StatelessWidget {
  final Color color;
  final double size;
  final VoidCallback? onTap;
  final bool showBorder;

  const ColorSquare({
    super.key,
    required this.color,
    this.size = 60,
    this.onTap,
    this.showBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: showBorder
              ? Border.all(color: Colors.grey.shade300, width: 1)
              : null,
        ),
      ),
    );
  }
}
