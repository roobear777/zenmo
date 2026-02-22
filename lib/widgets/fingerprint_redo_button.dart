// lib/widgets/fingerprint_redo_button.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../fingerprint_repo.dart';
import '../fingerprint_flow.dart'; // navigates into the 25-question flow

/// Button that:
///  • Checks monthly eligibility via the repo
///  • ALSO disables if a draft exists with ≥1 answer (redo already in progress)
///  • Navigates into the 25-question flow (no writes here)
class FingerprintRedoButton extends StatefulWidget {
  const FingerprintRedoButton({
    super.key,
    required this.answersProvider, // kept for API compatibility (unused)
    this.onDone,
    this.label = 'Redo fingerprint',
    this.disabledLabel,
    this.disabledHint = 'Next available next month',
    this.showDisabledHint = false,
  });

  /// Must return {'answers': List<int>, 'total': int}
  /// (Kept for API compatibility; not used by this button anymore.)
  final Future<Map<String, dynamic>> Function()? answersProvider;

  /// Called after the flow returns (if you want to refresh parent UI).
  final VoidCallback? onDone;

  /// Enabled label text.
  final String label;

  /// Disabled label text (defaults to [label] when null).
  final String? disabledLabel;

  /// Optional hint shown under a disabled button.
  final String disabledHint;

  /// Whether to show the disabled hint text.
  final bool showDisabledHint;

  @override
  State<FingerprintRedoButton> createState() => _FingerprintRedoButtonState();
}

class _FingerprintRedoButtonState extends State<FingerprintRedoButton> {
  bool _loading = true;
  bool _canRedo = false;

  @override
  void initState() {
    super.initState();
    _refreshEligibility();
  }

  Future<void> _refreshEligibility() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
          _canRedo = false; // not signed in → disabled
        });
        return;
      }

      // 1) Canonical monthly rule (fail-open lives in the repo)
      bool ok = await FingerprintRepo.canRedoThisMonth(
        db: FirebaseFirestore.instance,
        uid: user.uid,
      );

      // 2) UI lock: if a draft exists with >=1 answer and not completed,
      //    then a redo is already in progress → disable redo button.
      if (ok) {
        try {
          final draftSnap =
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('private')
                  .doc('fingerprint')
                  .get();

          final data = draftSnap.data();
          if (data != null) {
            final completed = data['completed'] == true;
            final answers =
                (data['answers'] is List)
                    ? (data['answers'] as List).whereType<int>().toList()
                    : const <int>[];
            if (!completed && answers.isNotEmpty) {
              ok = false;
            }
          }
        } catch (_) {
          // Ignore transient read issues; keep current 'ok'
        }
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _canRedo = ok;
      });
    } catch (_) {
      if (!mounted) return;
      // Fail-open on the canonical check keeps historical behavior
      setState(() {
        _loading = false;
        _canRedo = true;
      });
    }
  }

  Future<void> _startFlow() async {
    if (!_canRedo) return;
    await Navigator.of(context).push<List<int>?>(
      MaterialPageRoute(
        builder: (_) => const FingerprintFlow(redoCurrentMonth: true),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;
    widget.onDone?.call();
    await _refreshEligibility();
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = !_loading && _canRedo;

    final baseButton = ElevatedButton(
      onPressed: enabled ? _startFlow : null,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        backgroundColor:
            enabled ? const Color(0xFF2E004B) : null, // deep purple
        foregroundColor: enabled ? Colors.white : null,
        elevation: enabled ? 2 : 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        minimumSize: const Size(0, 36),
      ),
      child:
          _loading
              ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : Text(
                enabled ? widget.label : (widget.disabledLabel ?? widget.label),
              ),
    );

    if (!widget.showDisabledHint) return baseButton;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        baseButton,
        const SizedBox(height: 6),
        if (!_loading && !_canRedo)
          Text(
            widget.disabledHint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
      ],
    );
  }
}
