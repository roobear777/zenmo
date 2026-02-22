// lib/services/keep_repository.dart
import '../models/keep.dart';
import 'paged.dart';

abstract class KeepRepository {
  /// True if the current user has kept this answer.
  Future<bool> isKept(String answerId);

  /// Toggle keep for the current user; returns the new kept state.
  Future<bool> toggleKeep(String answerId);

  /// Paged list of the current user's keeps ordered by createdAt DESC.
  Future<Paged<Keep>> getKeepsForCurrentUser({
    int limit = 20,
    DateTime? startAfterCreatedAt,
  });
}
