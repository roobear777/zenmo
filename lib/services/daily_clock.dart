// lib/services/daily_clock.dart
import 'dart:async';

class DailyClock {
  DailyClock({DateTime Function()? nowProvider})
    : _nowProvider = nowProvider ?? DateTime.now;

  final DateTime Function() _nowProvider;
  final _controller = StreamController<String>.broadcast();

  Stream<String> get dayStream => _controller.stream;

  /// e.g. "2025-09-26" in device local time.
  String get localDay {
    final now = _nowProvider();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Timer? _midnightTimer;

  void start() {
    // Emit immediately.
    _controller.add(localDay);

    // Schedule precise tick at next local midnight.
    _scheduleNextMidnightTick();
  }

  void _scheduleNextMidnightTick() {
    _midnightTimer?.cancel();

    final now = _nowProvider();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final duration = tomorrow.difference(now);

    _midnightTimer = Timer(duration, () {
      _controller.add(localDay);
      _scheduleNextMidnightTick(); // schedule following day
    });
  }

  void dispose() {
    _midnightTimer?.cancel();
    _controller.close();
  }
}
