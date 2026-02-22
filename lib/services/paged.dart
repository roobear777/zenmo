// lib/services/paged.dart
class Paged<T> {
  final List<T> items;
  final DateTime? nextCreatedAtCursor; // pass to startAfter
  final bool hasMore;

  const Paged({
    required this.items,
    required this.nextCreatedAtCursor,
    required this.hasMore,
  });
}
