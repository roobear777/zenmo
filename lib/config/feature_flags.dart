// lib/config/feature_flags.dart
class FeatureFlags {
  /// Master flag for Daily Hues feature access.
  static const bool dailyHuesEnabled = true;

  /// How many "?" question tiles to sprinkle in the grid when available.
  static const int maxQuestionTiles = 5;

  /// Target grid width in columns for phones.
  static const int gridColsMobile = 5;

  /// Show gray filler tiles when content is sparse.
  static const bool showFillers = true;
}
