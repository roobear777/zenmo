// lib/daily_hues/swatch_quick_view.dart
import 'package:flutter/material.dart';

import '../models/answer.dart';
import '../services/keep_repository.dart';

class SwatchQuickView extends StatefulWidget {
  final Answer answer;
  final KeepRepository keepRepo;
  final VoidCallback onOpenDetails;

  /// Optional: runs once after the bottom sheet is shown.
  /// Use it to mark-read when QuickView is opened (e.g., for Inbox or Kept).
  final Future<void> Function()? onShown; // NEW (optional)

  const SwatchQuickView({
    super.key,
    required this.answer,
    required this.keepRepo,
    required this.onOpenDetails,
    this.onShown, // NEW
  });

  @override
  State<SwatchQuickView> createState() => _SwatchQuickViewState();
}

class _SwatchQuickViewState extends State<SwatchQuickView> {
  bool? _kept;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadKept();

    // Fire optional hook after the sheet has been presented.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await widget.onShown?.call();
      } catch (_) {
        // swallow — marking read is best-effort
      }
    });
  }

  Future<void> _loadKept() async {
    try {
      final k = await widget.keepRepo.isKept(widget.answer.id);
      if (!mounted) return;
      setState(() {
        _kept = k;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _kept = false;
        _loading = false;
      });
    }
  }

  Future<void> _toggleKeep() async {
    final newState = await widget.keepRepo.toggleKeep(widget.answer.id);
    if (!mounted) return;
    setState(() => _kept = newState);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newState ? 'Kept to Wallet' : 'Removed from Wallet'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseHex(widget.answer.colorHex);
    final title =
        widget.answer.title.isEmpty
            ? widget.answer.colorHex
            : widget.answer.title;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E2E2)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip:
                        (_kept ?? false)
                            ? 'Remove from Wallet'
                            : 'Keep to Wallet',
                    onPressed: _toggleKeep,
                    icon: Icon(
                      (_kept ?? false) ? Icons.bookmark : Icons.bookmark_border,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onOpenDetails,
                    child: const Text('Open details'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ],
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
