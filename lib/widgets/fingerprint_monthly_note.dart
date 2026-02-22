import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../fingerprint_repo.dart';

class FingerprintMonthlyNote extends StatefulWidget {
  const FingerprintMonthlyNote({super.key});

  @override
  State<FingerprintMonthlyNote> createState() => _FingerprintMonthlyNoteState();
}

class _FingerprintMonthlyNoteState extends State<FingerprintMonthlyNote> {
  bool _loading = true;
  bool _canRedo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Sole source of truth: repo decides eligibility (wrapper safe for widgets).
      final ok = await FingerprintRepo.canRedoThisMonthUnsafe();
      if (mounted) setState(() => _canRedo = ok);
    } catch (_) {
      // Fail-OPEN: transient errors must not block redo.
      if (mounted) {
        setState(() {
          _error = null;
          _canRedo = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 20,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // Never render a red error message here.
    if (_error != null) return const SizedBox.shrink();

    final text = _canRedo ? 'Available now' : _nextAvailableText();
    return Text(
      'Limit: once per calendar month • $text',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  /// e.g., "Next available 1 December, 2025"
  String _nextAvailableText([DateTime? now]) {
    final d = (now ?? DateTime.now()).toLocal();
    final firstNext =
        (d.month == 12)
            ? DateTime(d.year + 1, 1, 1)
            : DateTime(d.year, d.month + 1, 1);
    final date = DateFormat('d MMMM, y').format(firstNext);
    return 'Next available $date';
  }
}
