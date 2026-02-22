// lib/welcome_screen.dart
//
// Locked-position wordmark (LobsterLocal).
// We pin the wordmark in a fixed-height box and keep an identical layout
// between loading/final states to eliminate any vertical drift.

import 'dart:async'; // for StreamSubscription

// kIsWeb
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:ui' show FontFeature;

import 'loading_screen.dart';
import 'email_auth_screen.dart';

/// Simple local model for the "front door swatch"
class _FeaturedSwatch {
  final Color background;
  final String title;
  final String creator;
  final Color zenmoColor; // parity with previous versions

  const _FeaturedSwatch({
    required this.background,
    required this.title,
    required this.creator,
    required this.zenmoColor,
  });
}

// Helper to convert "#RRGGBB" / "RRGGBB" to a Color.
Color _colorFromHex(String hex) {
  var cleaned = hex.trim();
  if (cleaned.startsWith('#')) cleaned = cleaned.substring(1);
  if (cleaned.length == 6) cleaned = 'FF$cleaned'; // add opaque alpha
  final value = int.tryParse(cleaned, radix: 16) ?? 0xFFE3DEFF;
  return Color(value);
}

/// Simple WCAG-style contrast ratio between two colours.
double _contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final bright = l1 > l2 ? l1 : l2;
  final dark = l1 > l2 ? l2 : l1;
  return (bright + 0.05) / (dark + 0.05);
}

/// Accent from complementary hue; if contrast weak, nudge L.
Color _onBackgroundColor(Color bg) {
  final hsl = HSLColor.fromColor(bg);
  final compHue = (hsl.hue + 180.0) % 360.0;

  var accent =
      HSLColor.fromAHSL(1.0, compHue, hsl.saturation, hsl.lightness).toColor();

  final cr0 = _contrastRatio(accent, bg);
  if (cr0 < 3.0) {
    final lighter =
        HSLColor.fromAHSL(1.0, compHue, hsl.saturation, 0.88).toColor();
    final darker =
        HSLColor.fromAHSL(1.0, compHue, hsl.saturation, 0.22).toColor();
    final crL = _contrastRatio(lighter, bg);
    final crD = _contrastRatio(darker, bg);
    accent = crL >= crD ? lighter : darker;
  }
  return accent;
}

// Reusable wordmark using LOCAL Lobster font.
class _WordmarkZenmo extends StatelessWidget {
  final Color color;
  const _WordmarkZenmo({required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Zenmo',
      textAlign: TextAlign.center,
      // lock line-height: no extra leading
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
      style: const TextStyle(
        fontFamily: 'OleoScriptBold',
        fontSize: 90,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.0,
        height: 1.0, // tighter, predictable metrics
        fontFeatures: [
          FontFeature('calt'),
          FontFeature('liga'),
          FontFeature('kern'),
        ],
      ).copyWith(color: color),
    );
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const double kMaxBodyWidth = 360;
  static const double kWordmarkBoxHeight = 120; // fits 90px text consistently
  static const double kButtonsBlockHeight = 160;

  User? _user;
  late final Stream<User?> _authStream;
  late final StreamSubscription<User?> _sub;

  _FeaturedSwatch? _swatch;
  bool _loadingSwatch = true;

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'europe-west2',
  );

  @override
  void initState() {
    super.initState();

    _user = FirebaseAuth.instance.currentUser;
    _authStream = FirebaseAuth.instance.authStateChanges();
    _sub = _authStream.listen((u) {
      if (mounted) setState(() => _user = u);
    });

    _unifiedInitialSwatchLoad();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  /// Fetch a featured swatch from the cloud, but do NOT touch widget state.
  Future<_FeaturedSwatch?> _fetchFeaturedSwatchFromCloud() async {
    try {
      final callable = _functions.httpsCallable('getRandomFeaturedSwatch');
      final result = await callable.call();

      debugPrint('getRandomFeaturedSwatch result.data = ${result.data}');

      final data = Map<String, dynamic>.from(result.data as Map);

      final baseColorHex = (data['baseColorHex'] as String?)?.trim();
      final title = (data['title'] as String?)?.trim();
      final creatorDisplay = (data['creatorDisplay'] as String?)?.trim();

      if (baseColorHex == null || baseColorHex.isEmpty) {
        debugPrint(
          'getRandomFeaturedSwatch: missing/empty baseColorHex, falling back.',
        );
        return null;
      }

      final bg = _colorFromHex(baseColorHex);
      return _FeaturedSwatch(
        background: bg,
        title: (title == null || title.isEmpty) ? ' ' : title,
        creator:
            (creatorDisplay == null || creatorDisplay.isEmpty)
                ? ' '
                : creatorDisplay,
        zenmoColor: const Color(0xFF2449FF),
      );
    } on FirebaseFunctionsException catch (e, st) {
      debugPrint(
        'FirebaseFunctionsException in getRandomFeaturedSwatch: '
        'code=${e.code}, message=${e.message}, details=${e.details}',
      );
      debugPrint('Stack: $st');
      return null;
    } catch (e, st) {
      debugPrint('Failed to fetch featured swatch (other error): $e');
      debugPrint('Stack: $st');
      return null;
    }
  }

  /// Choose the initial swatch once: try cloud, otherwise fall back to a
  /// neutral brand swatch (no Roo/Big James/Roo etc.).
  Future<void> _unifiedInitialSwatchLoad() async {
    _FeaturedSwatch? fromCloud;

    try {
      fromCloud = await _fetchFeaturedSwatchFromCloud();
    } catch (_) {
      // ignore, we'll fallback below
    }

    if (!mounted) return;

    if (fromCloud != null) {
      _swatch = fromCloud;
    } else {
      // Simple neutral fallback, with no credit text.
      _swatch = const _FeaturedSwatch(
        background: Color(0xFFE3DEFF),
        title: '',
        creator: '',
        zenmoColor: Color(0xFF2449FF),
      );
    }

    setState(() => _loadingSwatch = false);
  }

  void _continue() {
    final name = _user?.displayName;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LoadingScreen(initialName: name)),
    );
  }

  void _openEmailLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const EmailAuthScreen(mode: EmailAuthMode.signIn),
      ),
    );
  }

  void _openEmailSignup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const EmailAuthScreen(mode: EmailAuthMode.signUp),
      ),
    );
  }

  Future<void> _switchAccount() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    _openEmailLogin();
  }

  Future<void> _forgotPassword() async {
    final TextEditingController emailCtrl = TextEditingController();
    final email = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Reset password'),
          content: TextField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email address',
              hintText: 'you@example.com',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, emailCtrl.text.trim()),
              child: const Text('Send reset'),
            ),
          ],
        );
      },
    );

    final e = (email ?? '').trim();
    if (e.isEmpty) return;

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to $e')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send reset: $err')));
    }
  }

  // ----- Shared body used by both states: exact same structure -----
  Widget _buildBody({
    Key? pageKey, // <— allow AnimatedSwitcher to key the whole page
    required Color background,
    required Color wordmarkColor,
    required Widget buttonsBlock, // fixed-height child (kButtonsBlockHeight)
  }) {
    return Scaffold(
      key: pageKey, // <— apply here
      backgroundColor: background,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kMaxBodyWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Fixed-height wordmark box to lock position
                      SizedBox(
                        height: kWordmarkBoxHeight,
                        width: double.infinity,
                        child: Align(
                          alignment: Alignment.center,
                          child: _WordmarkZenmo(color: wordmarkColor),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Fixed-height buttons area
                      SizedBox(
                        width: double.infinity,
                        height: kButtonsBlockHeight,
                        child: buttonsBlock,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom-right credit (shown only when we have a swatch title)
            if (_swatch != null &&
                _swatch!.title.trim().isNotEmpty &&
                _swatch!.creator.trim().isNotEmpty)
              Positioned(
                right: 24,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _swatch!.title,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: wordmarkColor.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _swatch!.creator,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        color: wordmarkColor.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _user != null;
    final who =
        (_user?.displayName?.trim().isNotEmpty ?? false)
            ? _user!.displayName!.trim()
            : (_user?.email ?? 'your account');

    // LOADING: identical shell, white bg, neutral wordmark, empty buttons placeholder
    if (_loadingSwatch || _swatch == null) {
      return _buildBody(
        background: Colors.white,
        wordmarkColor: const Color(0xFF5F6572),
        buttonsBlock: const SizedBox.shrink(), // reserved height
      );
    }

    // FINAL: identical shell, swatch bg, accent wordmark, real buttons
    final accent = _onBackgroundColor(_swatch!.background);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      child: _buildBody(
        pageKey: ValueKey<Color>(_swatch!.background),
        background: _swatch!.background,
        wordmarkColor: accent,
        buttonsBlock: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.center,
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          child:
              signedIn
                  ? _SignedInButtons(
                    key: const ValueKey('signedIn'),
                    onContinue: _continue,
                    onSwitch: _switchAccount,
                    who: who,
                    linkColor: accent,
                  )
                  : _LoggedOutButtons(
                    key: const ValueKey('loggedOut'),
                    onLogin: _openEmailLogin,
                    onSignup: _openEmailSignup,
                    onForgot: _forgotPassword,
                  ),
        ),
      ),
    );
  }
}

// ---------------------- Buttons sub-widgets (fixed metrics) -------------------

class _SignedInButtons extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback onSwitch;
  final String who;
  final Color linkColor;
  const _SignedInButtons({
    super.key,
    required this.onContinue,
    required this.onSwitch,
    required this.who,
    required this.linkColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5F6572),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              elevation: 0,
            ),
            onPressed: onContinue,
            child: Text(
              'Continue as $who',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onSwitch,
          style: TextButton.styleFrom(foregroundColor: linkColor),
          child: const Text(
            'Not you? Switch account',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _LoggedOutButtons extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onSignup;
  final VoidCallback onForgot;
  const _LoggedOutButtons({
    super.key,
    required this.onLogin,
    required this.onSignup,
    required this.onForgot,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5F6572),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              elevation: 0,
            ),
            onPressed: onLogin,
            child: const Text(
              'Log in with email',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF5F6572),
              side: const BorderSide(color: Color(0xFF5F6572), width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: onSignup,
            child: const Text(
              'Create an account',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onForgot,
          child: const Text(
            'Forgot password?',
            style: TextStyle(fontSize: 13, color: Color(0xFF5F6572)),
          ),
        ),
      ],
    );
  }
}
