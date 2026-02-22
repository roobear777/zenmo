import 'package:flutter/material.dart';
import 'package:color_wallet/fingerprint_flow.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Zenmo — Fingerprint Intro (minimal, matches reference screenshot)
class FingerprintIntroScreen extends StatelessWidget {
  const FingerprintIntroScreen({super.key});

  Future<List<int>> _loadDraftAnswers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const <int>[];

    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('private')
              .doc('fingerprint')
              .get();

      final data = snap.data();
      final dynamic raw = data?['answers'];
      if (raw is List) {
        final out = <int>[];
        for (final v in raw) {
          if (v is int) out.add(v);
          if (v is num) out.add(v.toInt());
        }
        return out;
      }
    } catch (e) {
      debugPrint('FingerprintIntroScreen: failed to load draft answers — $e');
    }

    return const <int>[];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    TextSpan bold(String s) =>
        TextSpan(text: s, style: const TextStyle(fontWeight: FontWeight.w600));
    TextSpan italic(String s) =>
        TextSpan(text: s, style: const TextStyle(fontStyle: FontStyle.italic));

    Widget para(List<InlineSpan> spans) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.35,
            color: Colors.black87,
          ),
          children: spans,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account & Settings'),
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
                'Hello, dear Amazing Alpha Tester!',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              // "To create your very own..." paragraph
              para(const [
                TextSpan(
                  text:
                      "To begin your very own Color Fingerprint, answer four questions. You can return and add more any time.",
                ),
              ]),

              // "Take as much time..." paragraph
              para(const [
                TextSpan(
                  text:
                      'Take as much time as you want. Some folks spend 20 minutes thinking theirs through; '
                      'others finish in five or ten minutes. You can save and come back whenever you\'d like.',
                ),
              ]),

              // "When you're done..." paragraph
              para([
                const TextSpan(
                  text:
                      "When you're done, you'll have a custom 5x5 mosaic view of yourself. "
                      'We hope this reflection brings deeper understanding to your life. At the very least, it should offer you more ',
                ),
                bold('color'),
                const TextSpan(text: '.'),
              ]),

              // "Are you ready... hue you are?!" paragraph
              para([
                const TextSpan(text: 'Are you ready to find out '),
                italic('hue you are?!'),
              ]),

              const Spacer(),

              SizedBox(
                width: 140,
                child: ElevatedButton(
                  onPressed: () async {
                    final answers = await _loadDraftAnswers();
                    final startAt = answers.length;

                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (_) => FingerprintFlow(
                              initialAnswers: answers,
                              startAtIndex: startAt,
                            ),
                      ),
                    );
                    if (context.mounted) Navigator.of(context).maybePop();
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
