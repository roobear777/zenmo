// lib/models/daily_grid_tile.dart
enum DailyGridTileType { color, question, filler }

class DailyGridTile {
  final DailyGridTileType type;
  final String? id; // answerId or questionId
  final String? colorHex; // only for color tiles

  const DailyGridTile.color({required this.id, required this.colorHex})
    : type = DailyGridTileType.color;

  const DailyGridTile.question({required this.id})
    : type = DailyGridTileType.question,
      colorHex = null;

  const DailyGridTile.filler()
    : type = DailyGridTileType.filler,
      id = null,
      colorHex = null;
}
