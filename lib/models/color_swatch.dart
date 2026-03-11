import 'package:flutter/material.dart';

/// Represents an individual color with metadata
class ColorSwatch {
  final String title;
  final Color color;
  final String? note;
  final DateTime createdAt;
  final String creator;

  const ColorSwatch({
    required this.title,
    required this.color,
    this.note,
    required this.createdAt,
    required this.creator,
  });

  /// Returns the hex value of the color (e.g., "#FF5733")
  String get hexValue {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// Converts the ColorSwatch to a Map for persistence
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'color': color.toARGB32(),
      'note': note,
      'createdAt': createdAt.toIso8601String(),
      'creator': creator,
    };
  }

  /// Creates a ColorSwatch from a Map
  factory ColorSwatch.fromMap(Map<String, dynamic> map) {
    return ColorSwatch(
      title: (map['title'] ?? '').toString(),
      color: Color(map['color'] as int? ?? 0xFF000000),
      note: map['note'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      creator: (map['creator'] ?? 'Anonymous').toString(),
    );
  }

  ColorSwatch copyWith({
    String? title,
    Color? color,
    String? note,
    DateTime? createdAt,
    String? creator,
  }) {
    return ColorSwatch(
      title: title ?? this.title,
      color: color ?? this.color,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      creator: creator ?? this.creator,
    );
  }
}
