import 'dart:async';
import 'package:flutter/material.dart';

/// Overlay that shows a subtle "scroll down" chevron at the bottom
/// until the user scrolls (or a timeout passes).
///
/// How it works:
/// - Listens to the PrimaryScrollController (so wrap a primary scrollable,
///   e.g. ListView/GridView with primary:true).
/// - Only shows if the content can scroll (maxScrollExtent > 0).
/// - Hides after user scroll delta exceeds [hideAfterScrollDelta] or [maxShowDuration].
class ScrollHintOverlay extends StatefulWidget {
  const ScrollHintOverlay({
    super.key,
    required this.child,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxShowDuration = const Duration(seconds: 5),
    this.hideAfterScrollDelta = 30.0,
    this.bottomPadding = 12.0,
  });

  final Widget child;
  final Duration initialDelay;
  final Duration maxShowDuration;
  final double hideAfterScrollDelta;
  final double bottomPadding;

  @override
  State<ScrollHintOverlay> createState() => _ScrollHintOverlayState();
}

class _ScrollHintOverlayState extends State<ScrollHintOverlay>
    with SingleTickerProviderStateMixin {
  bool _canScroll = false;
  bool _userScrolled = false;
  double _accumulatedDelta = 0.0;
  Timer? _delayTimer;
  Timer? _maxTimer;

  late final AnimationController _chevCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _delayTimer?.cancel();
    _maxTimer?.cancel();
    _chevCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scrollController = PrimaryScrollController.of(context);

    // We need to know if this scroll view can scroll (has overflow).
    // Use a NotificationListener to read metrics after layout.
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.hasPixels && n.metrics.maxScrollExtent > 0) {
          if (!_canScroll) {
            setState(() => _canScroll = true);
            _startTimers();
          }
        }
        // accumulate user scroll to hide
        if (n is UserScrollNotification || n is ScrollUpdateNotification) {
          final delta =
              (n is ScrollUpdateNotification) ? n.scrollDelta ?? 0 : 0;
          if (delta.abs() > 0) {
            _accumulatedDelta += delta.abs();
            if (_accumulatedDelta >= widget.hideAfterScrollDelta) {
              _hideNow();
            }
          }
        }
        return false; // don’t stop the notification chain
      },
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // your scrollable content
          widget.child,

          // chevron overlay
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: (_canScroll && !_userScrolled) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: Padding(
                padding: EdgeInsets.only(bottom: widget.bottomPadding),
                child: _ChevronBounce(animation: _chevCtl),
              ),
            ),
          ),
          // a soft gradient at the bottom so the chevron sits legibly
          if (_canScroll && !_userScrolled)
            IgnorePointer(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 48,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(0, 0.2),
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.white],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _startTimers() {
    _delayTimer?.cancel();
    _maxTimer?.cancel();

    // small delay before we show (prevents flashing on very short pages)
    _delayTimer = Timer(widget.initialDelay, () {
      if (mounted && _canScroll && !_userScrolled) {
        setState(() {}); // just ensure rebuild to show
      }
    });

    // auto-hide after max duration
    _maxTimer = Timer(widget.maxShowDuration, _hideNow);
  }

  void _hideNow() {
    if (!_userScrolled && mounted) {
      setState(() => _userScrolled = true);
    }
    _delayTimer?.cancel();
    _maxTimer?.cancel();
  }
}

class _ChevronBounce extends StatelessWidget {
  const _ChevronBounce({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    // Simple up-down float + fade
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: const Offset(0, 0.0),
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut));

    final fade = Tween<double>(
      begin: 0.25,
      end: 0.85,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut));

    return SlideTransition(
      position: slide,
      child: FadeTransition(
        opacity: fade,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 22,
                  color: Colors.black87,
                ),
                SizedBox(width: 2),
                Text(
                  'Scroll',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
