// lib/services/daily_grid_composer.dart
import '../config/feature_flags.dart';
import '../models/answer.dart';
import '../models/daily_grid_tile.dart';
import '../models/question.dart';

class DailyGridComposer {
  const DailyGridComposer();

  /// Deterministic grid composition:
  /// - Place up to 5 question tiles at fixed preferred indices.
  /// - Fill the rest with answer tiles.
  /// - Pad with fillers if requested and needed.
  List<DailyGridTile> compose({
    required List<Answer> answers,
    required List<Question> questions,
    int minTilesTarget = 25, // 5x5 default target
    bool showFillers = FeatureFlags.showFillers,
  }) {
    final questionSlots = _preferredQuestionIndices;
    final selectedQuestions =
        questions.take(FeatureFlags.maxQuestionTiles).toList();

    // Start with answer tiles
    final tiles = <DailyGridTile>[];
    for (final a in answers) {
      tiles.add(DailyGridTile.color(id: a.id, colorHex: a.colorHex));
    }

    // Insert questions at preferred slots if available
    for (
      var i = 0;
      i < selectedQuestions.length && i < questionSlots.length;
      i++
    ) {
      final slot = questionSlots[i];
      final q = selectedQuestions[i];
      // Ensure list has enough length to place at slot or append as needed
      while (tiles.length <= slot) {
        tiles.addAll(
          _placeholderColors(5 - (tiles.length % 5)),
        ); // ensure growth by row
      }
      tiles.insert(slot, DailyGridTile.question(id: q.id));
    }

    // Pad to min target with fillers if needed
    if (showFillers && tiles.length < minTilesTarget) {
      final deficit = minTilesTarget - tiles.length;
      for (var i = 0; i < deficit; i++) {
        tiles.add(const DailyGridTile.filler());
      }
    }

    return tiles;
  }

  /// Preferred positions to sprinkle 5 "?" tiles in a 5-wide grid.
  List<int> get _preferredQuestionIndices => const [2, 8, 13, 19, 24];

  /// If we must grow the list to reach a slot, add some answer-like placeholders.
  /// (These are immediately overshadowed by real data once available.)
  List<DailyGridTile> _placeholderColors(int count) {
    // Neutral fillers (not interactive) until real answers exist further down.
    return List.generate(count, (_) => const DailyGridTile.filler());
  }
}
