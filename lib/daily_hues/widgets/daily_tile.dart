// lib/daily_hues/widgets/daily_tile.dart
import 'package:flutter/material.dart';
import '../../models/daily_grid_tile.dart';

class DailyTile extends StatelessWidget {
  final DailyGridTile tile;
  final VoidCallback? onTap;

  const DailyTile({super.key, required this.tile, this.onTap});

  @override
  Widget build(BuildContext context) {
    switch (tile.type) {
      case DailyGridTileType.color:
        return _ColorTile(hex: tile.colorHex!, onTap: onTap);
      case DailyGridTileType.question:
        return _QuestionTile(onTap: onTap);
      case DailyGridTileType.filler:
        return _FillerTile();
    }
  }
}

class _ColorTile extends StatelessWidget {
  final String hex;
  final VoidCallback? onTap;
  const _ColorTile({required this.hex, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _parseHex(hex);
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Color _parseHex(String hex) {
    final cleaned = hex.replaceAll('#', '');
    final value = int.parse('FF$cleaned', radix: 16);
    return Color(value);
  }
}

class _QuestionTile extends StatelessWidget {
  final VoidCallback? onTap;
  const _QuestionTile({this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black87, width: 2),
        ),
        child: const Center(
          child: Text(
            '?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class _FillerTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFEF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD6D6D6)),
      ),
    );
  }
}
