import 'package:flutter/material.dart';

enum NavigationButtonType { back, home }

class NavigationButton extends StatelessWidget {
  final NavigationButtonType type;
  final VoidCallback onPressed;

  const NavigationButton({
    super.key,
    required this.type,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        type == NavigationButtonType.back ? Icons.chevron_left : Icons.home_outlined,
        color: const Color(0xFF6366F1),
        size: 32,
      ),
    );
  }
}
