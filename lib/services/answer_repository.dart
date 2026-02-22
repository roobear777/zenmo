import '../models/answer.dart';
import 'paged.dart';

/// Repository for reading answers used by Daily Scroll / Daily Answers.
///
/// Day key convention:
/// - Canonical: pass the *UTC day* string "YYYY-MM-DD" (midnight UTC).
/// - Back-compat: implementations may also accept a legacy local-day key and
///   internally fall back, but new callers should always pass UTC-day.
///
/// Sorting & cursors:
/// - Results are ordered by `createdAt` DESC (newest first).
/// - Pagination uses a `DateTime` cursor taken from the last item's `createdAt`.
/// - Display layers should render times with `.toLocal()`.
abstract class AnswerRepository {
  /// Returns up to ~120 answers for the given day (UTC-day preferred).
  Future<List<Answer>> getAnswersForDay(String localDay);

  /// Paginated answers for the given day (UTC-day preferred), ordered by
  /// `createdAt` DESC. Use the `startAfterCreatedAt` returned on the previous
  /// page as the cursor (the exact `createdAt` of the last item you received).
  Future<Paged<Answer>> getAnswersForDayPage(
    String localDay, {
    int limit = 50,
    DateTime? startAfterCreatedAt,
  });

  /// Fetch a single answer by id, or null if it does not exist.
  Future<Answer?> getAnswerById(String id);
}
