// lib/services/moderation_service.dart
class ModerationService {
  // Tiny, local wordlist. Expand later or move server-side.
  static const _blocked = <String>{
    'kill',
    'suicide',
    'hate',
    'slur1',
    'slur2',
    'nsfwword', // example placeholders
  };

  /// Returns null if OK, else a short error message.
  static String? validatePrompt(String text) {
    final t = text.toLowerCase();
    for (final w in _blocked) {
      if (w.isNotEmpty && t.contains(w)) {
        return 'Please rephrase your question.';
      }
    }
    return null;
  }

  static String? validateTitle(String title) {
    final t = title.toLowerCase();
    for (final w in _blocked) {
      if (w.isNotEmpty && t.contains(w)) {
        return 'Please rename this color.';
      }
    }
    return null;
  }
}
