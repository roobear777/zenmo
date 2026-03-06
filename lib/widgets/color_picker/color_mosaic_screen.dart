import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'color_generation_utils.dart';

enum MosaicMode { organized, randomized }

/// Color mosaic screen with mode switching between organized and randomized displays
class ColorMosaicScreen extends StatefulWidget {
  final double baseHue;
  final int ringIndex;
  final ValueChanged<Color> onColorSelected;

  const ColorMosaicScreen({
    super.key,
    required this.baseHue,
    required this.ringIndex,
    required this.onColorSelected,
  });

  @override
  State<ColorMosaicScreen> createState() => _ColorMosaicScreenState();
}

class _ColorMosaicScreenState extends State<ColorMosaicScreen> {
  static const int _cols = 6;
  static const int _tileCount = 600;
  static const double _cellSide = 28;

  MosaicMode _mode = MosaicMode.randomized;

  // Organized cache
  List<Color>? _orderedColors;
  int? _ordHueKey;
  int? _ordRingKey;

  int _qHueIdx(double hueDeg) {
    final h = ((hueDeg % 360) + 360) % 360;
    return (h / 0.25).round();
  }

  void _ensureOrderedCache() {
    final int hueKey = _qHueIdx(widget.baseHue);
    final int ringKey = widget.ringIndex.clamp(0, 9);
    if (_orderedColors != null &&
        _ordHueKey == hueKey &&
        _ordRingKey == ringKey) {
      return; // cache valid
    }

    _orderedColors = generateOrganizedPalette(
      baseHue: widget.baseHue,
      ringIndex: ringKey,
      tileCount: _tileCount,
      cols: _cols,
    );
    _ordHueKey = hueKey;
    _ordRingKey = ringKey;
  }

  Widget _buildTile({
    required int index,
    required Color color,
    required Widget inner,
    bool disableInkEffects = false,
  }) {
    Widget ink;
    if (disableInkEffects) {
      ink = InkWell(
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        splashColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: () => widget.onColorSelected(color.withAlpha(0xFF)),
        child: inner,
      );
    } else {
      ink = InkWell(
        onTap: () => widget.onColorSelected(color.withAlpha(0xFF)),
        child: inner,
      );
    }

    return ink;
  }

  Widget _modeSegmentedPill() {
    final bool organized = _mode == MosaicMode.organized;
    final bool randomized = _mode == MosaicMode.randomized;

    Widget seg(
      String label,
      bool selected,
      VoidCallback onTap, {
      BorderRadius? radius,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: radius ?? BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFD0D4DB) : Colors.white,
            borderRadius: radius ?? BorderRadius.zero,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFC5CF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(
            'Organized',
            organized,
            () => setState(() => _mode = MosaicMode.organized),
            radius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              bottomLeft: Radius.circular(8),
            ),
          ),
          Container(width: 1, height: 28, color: const Color(0xFFBFC5CF)),
          seg(
            'Randomized',
            randomized,
            () => setState(() => _mode = MosaicMode.randomized),
            radius: const BorderRadius.only(
              topRight: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int seed = _qHueIdx(widget.baseHue) * 1009 + widget.ringIndex * 9176;
    final rnd = math.Random(seed);

    late final List<Color> colors;
    late final List<int> tileHeights;

    if (_mode == MosaicMode.randomized) {
      colors = generateRandomizedPalette(
        baseHue: widget.baseHue,
        ringIndex: widget.ringIndex,
        seed: seed,
        tileCount: _tileCount,
      );
      tileHeights = assignTileHeights(rnd: rnd, count: colors.length);
    } else {
      _ensureOrderedCache();
      colors = _orderedColors!;
      tileHeights = const <int>[]; // not used in fixed grid
    }

    final Widget orderedGrid = GridView.builder(
      key: ValueKey('orderedGrid:$_ordHueKey:$_ordRingKey'),
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: 800,
      itemCount: colors.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _cols,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
        childAspectRatio: 1.0,
      ),
      itemBuilder: (context, i) {
        final c = colors[i];
        return _buildTile(
          index: i,
          color: c,
          disableInkEffects: true,
          inner: Container(color: c),
        );
      },
    );

    final Widget randomGrid = MasonryGridView.count(
      primary: true,
      physics: const AlwaysScrollableScrollPhysics(),
      crossAxisCount: _cols,
      mainAxisSpacing: 0,
      crossAxisSpacing: 0,
      cacheExtent: 800,
      itemCount: colors.length,
      itemBuilder: (context, i) {
        final c = colors[i];
        final units = tileHeights[i];
        return _buildTile(
          index: i,
          color: c,
          inner: Container(height: _cellSide * units, color: c),
        );
      },
    );

    final Widget gridWithChevron = Stack(
      children: [
        (_mode == MosaicMode.organized) ? orderedGrid : randomGrid,
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
            // Back button (top-left)
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
            // Segmented control (Organized / Randomized) centered top
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(child: _modeSegmentedPill()),
            ),
          ],
        ),
      ),
    );
  }
}
