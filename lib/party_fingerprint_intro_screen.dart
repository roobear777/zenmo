// lib/party_fingerprint_intro_screen.dart
import 'package:flutter/material.dart';

import 'package:color_wallet/party_fingerprint_flow.dart';
import 'package:color_wallet/party_fingerprint_repo.dart';

class PartyFingerprintIntroScreen extends StatelessWidget {
  const PartyFingerprintIntroScreen({super.key, this.startFresh = false});

  final bool startFresh;

  static const int _totalPrompts = 5;

  static bool _hasAtLeastOneColor(Map<String, dynamic>? answer) {
    if (answer == null) return false;
    final colors = answer['colors'];
    return colors is List && colors.isNotEmpty;
  }

  /// Resume at the first incomplete prompt (0-based), based on colors present.
  /// If all 5 are complete, returns 5.
  static int _resumeIndexFromDraft(List<Map<String, dynamic>> draft) {
    for (int i = 0; i < _totalPrompts; i++) {
      final Map<String, dynamic>? answer = i < draft.length ? draft[i] : null;
      if (!_hasAtLeastOneColor(answer)) {
        return i;
      }
    }
    return _totalPrompts;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget para(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          height: 1.35,
          color: Colors.black87,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Party Fingerprint'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Colors.grey),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Party Fingerprint',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              para('Answer five quick prompts with a color and a short label.'),
              para('You can save and come back later.'),
              const Spacer(),
              SizedBox(
                width: 180,
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      if (startFresh) {
                        // Reset draft so "Redo" starts clean.
                        await PartyFingerprintRepo.saveDraft(
                          answers: const <Map<String, dynamic>>[],
                          total: _totalPrompts,
                        );
                      }
                    } catch (_) {
                      // If reset fails, still allow user to proceed (they can overwrite).
                    }

                    final draft =
                        startFresh
                            ? const <Map<String, dynamic>>[]
                            : await PartyFingerprintRepo.getDraftOnce();

                    final startAt =
                        startFresh
                            ? 0
                            : _resumeIndexFromDraft(
                              draft,
                            ).clamp(0, _totalPrompts);

                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (_) => PartyFingerprintFlow(
                              initialAnswers: draft,
                              startAtIndex: startAt,
                            ),
                      ),
                    );

                    if (context.mounted) {
                      Navigator.of(context).maybePop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5F6572),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      letterSpacing: 0.5,
                    ),
                  ),
                  child: const Text("LET'S GO!"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
