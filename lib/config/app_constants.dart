import 'package:flutter/material.dart';

/// Application-wide constants for colors, spacing, and styling
class AppConstants {
  // Theme Colors
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Colors.white;
  static const Color textPrimaryColor = Colors.black87;
  static const Color textSecondaryColor = Colors.black54;
  static const Color textTertiaryColor = Colors.black45;
  static const Color borderColor = Color(0xFFE2E8F0);
  static const Color borderColorLight = Color(0xFFF0F4F8);

  // Spacing
  static const double spacingXs = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 12.0;
  static const double spacingL = 16.0;
  static const double spacingXl = 24.0;
  static const double spacingXxl = 32.0;

  // Border Radius
  static const double borderRadiusS = 4.0;
  static const double borderRadiusM = 8.0;
  static const double borderRadiusL = 12.0;
  static const double borderRadiusXl = 16.0;

  // Font Sizes
  static const double fontSizeXs = 11.0;
  static const double fontSizeS = 12.0;
  static const double fontSizeM = 14.0;
  static const double fontSizeL = 16.0;
  static const double fontSizeXl = 18.0;
  static const double fontSizeXxl = 20.0;
  static const double fontSizeHuge = 24.0;
  static const double fontSizeGiant = 64.0;
  static const double fontSizeJumbo = 96.0;

  // Shadow
  static const List<BoxShadow> shadowSmall = [
    BoxShadow(
      color: Color.fromARGB(13, 0, 0, 0),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  // Animation Durations
  static const Duration animationDurationFast = Duration(milliseconds: 200);
  static const Duration animationDurationNormal = Duration(milliseconds: 300);
  static const Duration animationDurationSlow = Duration(milliseconds: 500);
}
