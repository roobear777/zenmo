import 'package:flutter/material.dart';

/// Example palettes shown when a question has no colors yet
class ExamplePalette {
  final String title;
  final List<Color> colors;

  const ExamplePalette({
    required this.title,
    required this.colors,
  });
}

const List<ExamplePalette> kExamplePalettes = [
  ExamplePalette(
    title: 'Need more sleep',
    colors: [
      Color(0xFF2D3748),
      Color(0xFF4A5568),
      Color(0xFF718096),
    ],
  ),
  ExamplePalette(
    title: 'Passsssion',
    colors: [
      Color(0xFFE53E3E),
      Color(0xFFF56565),
      Color(0xFFFC8181),
    ],
  ),
  ExamplePalette(
    title: 'No thanks gran...',
    colors: [
      Color(0xFF38B2AC),
      Color(0xFF4FD1C5),
      Color(0xFF81E6D9),
    ],
  ),
  ExamplePalette(
    title: 'Spring Blooms A...',
    colors: [
      Color(0xFFED64A6),
      Color(0xFFF687B3),
      Color(0xFFFBB6CE),
    ],
  ),
  ExamplePalette(
    title: 'Deserunt ut ut dui',
    colors: [
      Color(0xFF9F7AEA),
      Color(0xFFB794F4),
      Color(0xFFD6BCFA),
    ],
  ),
  ExamplePalette(
    title: '[add an answer]',
    colors: [
      Color(0xFFEDF2F7),
      Color(0xFFE2E8F0),
      Color(0xFFCBD5E0),
    ],
  ),
];
