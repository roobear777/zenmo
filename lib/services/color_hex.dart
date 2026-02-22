// lib/color_hex.dart
import 'package:flutter/material.dart';

/// #RRGGBB (alpha dropped) – good for print/merch
String hexRgbFromInt(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = (argb) & 0xFF;
  String two(int v) => v.toRadixString(16).padLeft(2, '0');
  return '#${two(r)}${two(g)}${two(b)}'.toUpperCase();
}

String hexRgbFromColor(Color c) => hexRgbFromInt(c.value);

List<String> hexListFromInts(List<int> ints) =>
    ints.map(hexRgbFromInt).toList(growable: false);

List<String> hexListFromColors(List<Color> colors) =>
    colors.map((c) => hexRgbFromInt(c.value)).toList(growable: false);
