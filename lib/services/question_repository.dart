// lib/services/question_repository.dart
import '../models/question.dart';
import 'paged.dart';

abstract class QuestionRepository {
  Future<List<Question>> getQuestionsForDay(String localDay);
  Future<Question?> getQuestionById(String id);

  Future<String> createQuestion({
    required String text,
    required String localDay,
  });

  /// Paginated questions by createdAt DESC. Use `cursor` from previous page.
  Future<Paged<Question>> getQuestionsForDayPage(
    String localDay, {
    int limit = 50,
    DateTime? startAfterCreatedAt,
  });
}
