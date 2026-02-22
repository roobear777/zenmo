// lib/loading_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'daily_hues/daily_hues_screen.dart'; // was color_picker_screen.dart
import 'force_password_screen.dart';
import 'services/user_identity_service.dart';

import 'fingerprint_intro_screen.dart';
import 'fingerprint_flow.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key, this.initialName});
  final String? initialName;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  String? _displayName;

  // Self-healing identity
  final _identity = UserIdentityService();

  // Pulse anim
  late final AnimationController _pulseCtl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _opacityAnim;

  // Fade-out before route change
  late final AnimationController _outCtl;
  late final Animation<double> _outOpacity;

  bool _navigated = false;
  bool _canSkip = false; // guard tap-to-skip until checks complete
  bool _onboardingInFlight = false;

  @override
  void initState() {
    super.initState();
    _displayName = widget.initialName;

    _pulseCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    _scaleAnim = Tween<double>(
      begin: 0.96,
      end: 1.04,
    ).animate(CurvedAnimation(parent: _pulseCtl, curve: Curves.easeInOut));
    _opacityAnim = Tween<double>(
      begin: 0.35,
      end: 0.55,
    ).animate(CurvedAnimation(parent: _pulseCtl, curve: Curves.easeInOut));

    _outCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _outOpacity = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _outCtl, curve: Curves.easeOut));

    // Heal name, then decide route.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _identity.ensureDisplayIdentity(); // no-op if already fine
        final name = await _identity.getDisplayName();
        if (mounted) setState(() => _displayName = name);
      } catch (e) {
        debugPrint('LoadingScreen: identity init failed — $e');
      }

      final diverted = await _checkPwResetAndMaybeRoute();
      if (!diverted) {
        final ok = await _checkFingerprintOnboardingAndMaybeRoute();
        if (!mounted) return;

        _canSkip = true; // allow tap to reopen onboarding
        if (ok) _startAutoAdvance();
      }
    });
  }

  static const int _kMinFingerprintAnswers = 4;

  Future<List<int>> _fetchFingerprintDraftAnswers(String uid) async {
    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('private')
              .doc('fingerprint')
              .get();

      final data = snap.data();
      final dynamic raw = data?['answers'];
      if (raw is List) {
        final out = <int>[];
        for (final v in raw) {
          if (v is int) {
            out.add(v);
          } else if (v is num) {
            out.add(v.toInt());
          }
        }
        return out;
      }
    } catch (e) {
      // Fail closed: if we can't read answers, treat as 0 and gate.
      debugPrint('fingerprint draft read failed — $e');
    }
    return const <int>[];
  }

  Future<bool> _checkFingerprintOnboardingAndMaybeRoute() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return true; // no user -> don't gate here

    final answers = await _fetchFingerprintDraftAnswers(user.uid);
    final answeredCount = answers.length;

    if (answeredCount >= _kMinFingerprintAnswers) return true;

    // Do NOT allow DailyHues, but DO allow the user to back out of the flow.
    if (_onboardingInFlight) return false;
    _onboardingInFlight = true;

    final Widget page =
        (answeredCount == 0)
            ? const FingerprintIntroScreen()
            : FingerprintFlow(
              initialAnswers: answers,
              startAtIndex: answeredCount,
            );

    try {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    } finally {
      _onboardingInFlight = false;
    }

    // After returning, we’re still gated unless they reached 4.
    final answersAfter = await _fetchFingerprintDraftAnswers(user.uid);
    return answersAfter.length >= _kMinFingerprintAnswers;
  }

  /// Returns true if we routed to ForcePasswordScreen, false if not.
  Future<bool> _checkPwResetAndMaybeRoute() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final snap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      final data = snap.data();
      final needReset =
          data?['pwResetRequired'] == true ||
          data?['mustChangePassword'] == true; // check either flag

      if (needReset && mounted) {
        _navigated = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ForcePasswordScreen()),
        );
        return true;
      }
    } catch (e) {
      // Fail open: if we can't read the flag, continue the normal flow.
      debugPrint('pwResetRequired check failed — $e');
    }
    return false;
  }

  void _startAutoAdvance() {
    // linger as you prefer; if you previously set this to 1400ms keep it
    Future.delayed(const Duration(milliseconds: 1400), _goNext);
  }

  Future<void> _goNext() async {
    if (!mounted || _navigated) return;

    // Safety: never allow fingerprint onboarding to be bypassed.
    final ok = await _checkFingerprintOnboardingAndMaybeRoute();
    if (!mounted || _navigated) return;
    if (!ok) return;

    _navigated = true;
    await _outCtl.forward();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(_fadeRoute(const DailyHuesScreen()));
  }

  @override
  void dispose() {
    _pulseCtl.dispose();
    _outCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double h = constraints.maxHeight;
        final bool isTiny = h < 560.0;

        final core = Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_canSkip) _goNext(); // guard tap-to-skip
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Hi',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder:
                          (child, anim) =>
                              FadeTransition(opacity: anim, child: child),
                      child:
                          (_displayName == null || _displayName!.isEmpty)
                              ? const SizedBox(key: ValueKey('empty'))
                              : Text(
                                '${_displayName!}!',
                                key: const ValueKey('name'),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                              ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                AnimatedBuilder(
                  animation: _pulseCtl,
                  builder: (context, _) {
                    return Opacity(
                      opacity: _opacityAnim.value,
                      child: Transform.scale(
                        scale: _scaleAnim.value,
                        child: const _RgbAdditiveTriplet(
                          radius: 32,
                          top: Offset(0, -18),
                          left: Offset(-18, 11),
                          right: Offset(18, 11),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                const Text(
                  'Send good vibes\nwith colors.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        );

        final body = FadeTransition(opacity: _outOpacity, child: core);

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child:
                isTiny
                    ? SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: h),
                        child: body,
                      ),
                    )
                    : body,
          ),
        );
      },
    );
  }
}

PageRouteBuilder _fadeRoute(Widget page) {
  return PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder:
        (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
  );
}

/// Paints three RGB circles USING ADDITIVE BLENDING inside an offscreen layer,
/// then composites that result over whatever background (white) with normal srcOver.
/// This avoids the pastel washout while keeping your white splash.
class _RgbAdditiveTriplet extends StatelessWidget {
  final double radius;
  final Offset top;
  final Offset left;
  final Offset right;

  const _RgbAdditiveTriplet({
    required this.radius,
    required this.top,
    required this.left,
    required this.right,
  });

  @override
  Widget build(BuildContext context) {
    // Size big enough to contain all three circles
    final double size = radius * 2 + 48; // small margin
    return CustomPaint(
      size: Size.square(size),
      painter: _RgbAdditivePainter(
        radius: radius,
        top: top + Offset(size / 2, size / 2),
        left: left + Offset(size / 2, size / 2),
        right: right + Offset(size / 2, size / 2),
      ),
    );
  }
}

class _RgbAdditivePainter extends CustomPainter {
  final double radius;
  final Offset top;
  final Offset left;
  final Offset right;

  _RgbAdditivePainter({
    required this.radius,
    required this.top,
    required this.left,
    required this.right,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Offscreen layer where the circles add to EACH OTHER, not to the white bg.
    canvas.saveLayer(rect, Paint()); // transparent buffer

    final add =
        Paint()
          ..blendMode = BlendMode.plus
          ..isAntiAlias = true;

    // slightly under-opaque so overlaps can build nicely
    add.color = const Color(0xCCFF0000); // red ~80% alpha
    canvas.drawCircle(top, radius, add);

    add.color = const Color(0xCC00FF00); // green
    canvas.drawCircle(left, radius, add);

    add.color = const Color(0xCC0000FF); // blue
    canvas.drawCircle(right, radius, add);

    // Composite the offscreen buffer over the page (white bg) normally.
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RgbAdditivePainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.top != top ||
        oldDelegate.left != left ||
        oldDelegate.right != right;
  }
}
