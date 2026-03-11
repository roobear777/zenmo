import 'package:flutter/material.dart';
import '../models/color_swatch.dart' as models;

/// Manages temporary state during color creation
class ColorCreationState extends ChangeNotifier {
  Color _selectedColor;
  String _title;
  String _note;

  ColorCreationState({
    Color? selectedColor,
    String title = '',
    String note = '',
  })  : _selectedColor = selectedColor ?? Colors.blue,
        _title = title,
        _note = note;

  /// Gets the currently selected color
  Color get selectedColor => _selectedColor;

  /// Updates the selected color
  void updateColor(Color color) {
    _selectedColor = color;
    notifyListeners();
  }

  /// Updates the color from HSB values
  void updateFromHSB(double hue, double saturation, double brightness) {
    _selectedColor = HSVColor.fromAHSV(
      1.0,
      hue,
      saturation,
      brightness,
    ).toColor();
    notifyListeners();
  }

  /// Gets the title
  String get title => _title;

  /// Updates the title
  void updateTitle(String title) {
    _title = title;
    notifyListeners();
  }

  /// Gets the note
  String get note => _note;

  /// Updates the note
  void updateNote(String note) {
    _note = note;
    notifyListeners();
  }

  /// Checks if the current state is valid for saving
  bool get isValid => _title.trim().isNotEmpty;

  /// Converts the current state to a ColorSwatch
  models.ColorSwatch toColorSwatch() {
    return models.ColorSwatch(
      title: _title,
      color: _selectedColor,
      note: _note.isEmpty ? null : _note,
      createdAt: DateTime.now(),
      creator: 'User', // TODO: Get actual user identifier
    );
  }

  /// Resets the state to default values
  void reset() {
    _selectedColor = Colors.blue;
    _title = '';
    _note = '';
    notifyListeners();
  }

  /// Gets HSB values from the current color
  HSVColor get hsvColor => HSVColor.fromColor(_selectedColor);

  /// Gets the hue value (0-360)
  double get hue => hsvColor.hue;

  /// Gets the saturation value (0-1)
  double get saturation => hsvColor.saturation;

  /// Gets the brightness value (0-1)
  double get brightness => hsvColor.value;
}
