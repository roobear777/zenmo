import 'package:flutter/material.dart';

/// Neutral mosaic screen displaying 240 grey tiles
class NeutralMosaicScreen extends StatefulWidget {
  final ValueChanged<Color> onColorSelected;

  const NeutralMosaicScreen({super.key, required this.onColorSelected});

  @override
  State<NeutralMosaicScreen> createState() => _NeutralMosaicScreenState();
}

class _NeutralMosaicScreenState extends State<NeutralMosaicScreen> {
  static const int _cols = 6;
  static const int _tileCount = 240;

  late final List<Color> _colors;

  @override
  void initState() {
    super.initState();
    _colors = _buildGreys();
  }

  List<Color> _buildGreys() {
    const double vMin = 0.05;
    const double vMax = 0.98;
    final int rows = (_tileCount / _cols).ceil();
    final List<Color> out = [];

    for (int i = 0; i < _tileCount; i++) {
      final int row = i ~/ _cols;
      final double t = rows <= 1 ? 0.0 : row / (rows - 1);
      // top lighter, bottom darker
      final double v = vMax - (vMax - vMin) * t;
      out.add(HSVColor.fromAHSV(1.0, 0.0, 0.0, v).toColor());
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    final Widget grid = GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: 800,
      itemCount: _colors.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _cols,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
        childAspectRatio: 1.0,
      ),
      itemBuilder: (context, i) {
        final c = _colors[i];
        return InkWell(
          onTap: () => widget.onColorSelected(c.withAlpha(0xFF)),
          child: Container(color: c),
        );
      },
    );

    final Widget gridWithChevron = Stack(
      children: [
        grid,
        // Scroll hint chevron at bottom
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 24,
          left: 0,
          right: 0,
          child: Center(
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 88,
              color: Colors.black.withValues(alpha: 0.3),
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            gridWithChevron,
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: const Icon(Icons.chevron_left, size: 28),
                  color: Colors.black,
                  splashRadius: 22,
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Back',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
