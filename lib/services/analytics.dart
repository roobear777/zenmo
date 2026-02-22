// lib/services/analytics.dart
import 'dart:developer' as dev;

class AnalyticsService {
  static void logEvent(
    String name, {
    Map<String, Object?> parameters = const {},
  }) {
    // MVP: console log. Later swap to FirebaseAnalytics.
    dev.log(
      'analytics: $name',
      name: 'Analytics',
      error: parameters.isEmpty ? null : parameters,
    );
  }
}
