// Model for a single fingerprint answer
class FingerprintAnswer {
  final String title;
  final List<int> colors; // Color values as integers
  final List<String> hexes; // Hex strings like "#FF5733"

  const FingerprintAnswer({
    required this.title,
    required this.colors,
    required this.hexes,
  });

  factory FingerprintAnswer.empty() {
    return const FingerprintAnswer(title: '', colors: [], hexes: []);
  }

  factory FingerprintAnswer.fromMap(Map<String, dynamic> map) {
    final colorsRaw = (map['colors'] is List) ? (map['colors'] as List) : [];
    final hexesRaw = (map['hexes'] is List) ? (map['hexes'] as List) : [];

    final colors = <int>[];
    for (final v in colorsRaw) {
      if (v is int) colors.add(v);
    }

    final hexes = <String>[];
    for (final v in hexesRaw) {
      if (v is String) hexes.add(v);
    }

    return FingerprintAnswer(
      title: (map['title'] ?? '').toString(),
      colors: colors,
      hexes: hexes,
    );
  }

  Map<String, dynamic> toMap() {
    return {'title': title, 'colors': colors, 'hexes': hexes};
  }

  bool get isValid => title.trim().isNotEmpty && colors.isNotEmpty;

  FingerprintAnswer copyWith({
    String? title,
    List<int>? colors,
    List<String>? hexes,
  }) {
    return FingerprintAnswer(
      title: title ?? this.title,
      colors: colors ?? this.colors,
      hexes: hexes ?? this.hexes,
    );
  }
}
