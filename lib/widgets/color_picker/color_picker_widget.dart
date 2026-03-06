import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'color_generation_utils.dart';
import 'hue_value_disc_painter.dart';
import 'color_mosaic_screen.dart';
import 'neutral_mosaic_screen.dart';

/// Main color picker widget that displays the hue/value disc wheel
class ColorPickerWidget extends StatefulWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;

  const ColorPickerWidget({
    super.key,
    required this.currentColor,
    required this.onColorChanged,
  });

  @override
  State<ColorPickerWidget> createState() => _ColorPickerWidgetState();
}

class _ColorPickerWidgetState extends State<ColorPickerWidget> {
  final GlobalKey _wheelKey = GlobalKey();
  Color? selectedColor;
  int? _lastRingIndex;
  bool _openingMosaic = false;
  bool _hadValidPick = false;

  /// Returns true if the tap was inside the neutral centre hub
  bool _handleColorSelection(Offset globalPosition) {
    final RenderBox? box =
        _wheelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;

    final local = box.globalToLocal(globalPosition);
    final size = box.size;
    final center = Offset(size.width / 2, size.height / 2);
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    final maxRadius = size.width / 2;
    final double centerNeutralRadius = maxRadius * kCenterNeutralFraction;

    // Inside neutral hub: do not set selectedColor; signal centre hit
    if (distance <= centerNeutralRadius) {
      return true;
    }

    // Inside coloured rings region: normal hue/ring selection
    if (distance <= maxRadius) {
      final angleRadians = math.atan2(dy, dx);
      final hue = calculateHueFromAngle(angleRadians);

      final ringWidth = maxRadius / kRings;
      final ringIndex = (distance / ringWidth).floor().clamp(0, kRings - 1);
      final ringValue = calculateRingValueForMosaic(ringIndex);

      final opacity = calculateOpacity(ringIndex);

      final newColor = HSVColor.fromAHSV(
        opacity,
        hue,
        1.0,
        ringValue,
      ).toColor();

      setState(() {
        selectedColor = newColor.withAlpha(0xFF);
        _lastRingIndex = ringIndex;
        _hadValidPick = true;
      });
    }

    return false;
  }

  Future<void> _openMosaic() async {
    if (_openingMosaic) return;
    final base = selectedColor;
    if (base == null) return;

    _openingMosaic = true;
    try {
      final hsv = HSVColor.fromColor(base);
      final ringIndex = _lastRingIndex ?? 0;

      final picked = await Navigator.of(context, rootNavigator: false)
          .push<Color?>(
            MaterialPageRoute(
              builder: (_) => ColorMosaicScreen(
                baseHue: hsv.hue,
                ringIndex: ringIndex,
                onColorSelected: (color) {
                  widget.onColorChanged(color);
                  Navigator.of(context, rootNavigator: false).pop(color);
                },
              ),
            ),
          );

      if (picked != null && mounted) {
        // Color already handled by callback
      }
    } finally {
      _openingMosaic = false;
    }
  }

  Future<void> _openNeutralMosaic() async {
    if (_openingMosaic) return;

    _openingMosaic = true;
    try {
      final picked = await Navigator.of(context, rootNavigator: false)
          .push<Color?>(
            MaterialPageRoute(
              builder: (_) => NeutralMosaicScreen(
                onColorSelected: (color) {
                  widget.onColorChanged(color);
                  Navigator.of(context, rootNavigator: false).pop(color);
                },
              ),
            ),
          );

      if (picked != null && mounted) {
        // Color already handled by callback
      }
    } finally {
      _openingMosaic = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double size = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );

        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: GestureDetector(
              onPanUpdate: (d) {
                // Pan is only for colour picking in the ring area
                _handleColorSelection(d.globalPosition);
              },
              onTapDown: (d) {
                final bool isCenter = _handleColorSelection(d.globalPosition);
                if (isCenter) {
                  _openNeutralMosaic();
                  _hadValidPick = false; // prevent colour mosaic on tapUp
                }
              },
              onTapUp: (_) {
                if (_hadValidPick) _openMosaic();
                _hadValidPick = false;
              },
              child: Container(
                key: _wheelKey,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: CustomPaint(painter: HueValueDiscPainter()),
              ),
            ),
          ),
        );
      },
    );
  }
}
