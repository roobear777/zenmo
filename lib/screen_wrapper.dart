// lib/screen_wrapper.dart
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'dart:math' as math;

/// ScreenWrapper
///
/// Normal: returns [child].
/// Desktop web (non-admin): centers a tight 414×896 “phone” surface with
/// rounded corners and a visible shadow. Keeps a stable scroll view to avoid
/// Navigator reparenting asserts when resizing DevTools/emulation.
///
/// NEW: `desktopScale` lets you render the framed phone smaller (e.g. 0.75)
/// on desktop web, matching DevTools' visual scale while keeping a 414×896
/// logical canvas inside the frame.
class ScreenWrapper extends StatelessWidget {
  final Widget child;
  final bool forceFrameOnWideWeb;
  final Size maxFrameSize;
  final VoidCallback? onDebugTick; // debug hook
  final double desktopScale; // visual scale for desktop web XR

  const ScreenWrapper({
    super.key,
    required this.child,
    this.forceFrameOnWideWeb = false,
    this.maxFrameSize = const Size(430, 900),
    this.onDebugTick,
    this.desktopScale = 1.0, // default 1.0 = unchanged
  });

  static bool _shouldFrame(BuildContext context, bool force) {
    if (!kIsWeb || !force) return false;
    // Frame on all web widths; admin route bypasses via caller.
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final shouldFrame = _shouldFrame(context, forceFrameOnWideWeb);
    if (!shouldFrame) return child;

    return LayoutBuilder(
      builder: (context, cons) {
        // Start from target (e.g., 414×896), allow down-clamp if viewport is tiny.
        const double minW = 320.0;
        const double minH = 560.0;

        double frameW = maxFrameSize.width;
        double frameH = maxFrameSize.height;

        if (cons.maxWidth.isFinite) {
          frameW =
              (cons.maxWidth < minW)
                  ? cons.maxWidth
                  : frameW.clamp(minW, cons.maxWidth);
        } else {
          frameW = math.max(minW, frameW);
        }

        if (cons.maxHeight.isFinite) {
          frameH =
              (cons.maxHeight < minH)
                  ? cons.maxHeight
                  : frameH.clamp(minH, cons.maxHeight);
        } else {
          frameH = math.max(minH, frameH);
        }

        // Unscaled fit check (legacy behavior)
        final bool canFitVertically =
            !cons.maxHeight.isFinite || cons.maxHeight >= frameH;

        // Shadow MUST be outside clip.
        final Widget framedSurface = Container(
          decoration: const BoxDecoration(
            boxShadow: [
              BoxShadow(
                blurRadius: 22,
                color: Colors.black12,
                spreadRadius: 6,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: ConstrainedBox(
                constraints: BoxConstraints.tight(Size(frameW, frameH)),
                child: _FramedHost(child: child),
              ),
            ),
          ),
        );

        // ---- Desktop scale application -------------------------------------
        // Apply scaling only on desktop web framing. Clamp for safety.
        final double s = desktopScale.clamp(0.5, 1.0);
        final double displayW = frameW * s;
        final double displayH = frameH * s;

        // Build a scaled version of the framed surface.
        final Widget scaledSurface = SizedBox(
          width: displayW,
          height: displayH,
          child: Transform.scale(
            scale: s,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: frameW,
              height: frameH,
              child: framedSurface,
            ),
          ),
        );

        // Stable container: either place scaled surface without scroll
        // (when it fits after scaling) or fall back to the stable scroll view.
        return ColoredBox(
          color: const Color(0xFFF4F5F7),
          child: LayoutBuilder(
            builder: (context, pageCons) {
              if (kDebugMode) onDebugTick?.call();

              final bool canFitVerticallyScaled =
                  !pageCons.maxHeight.isFinite ||
                  pageCons.maxHeight >= displayH;

              if (canFitVerticallyScaled) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: scaledSurface,
                  ),
                );
              }

              // Otherwise keep the stable scroll (prevents Navigator reparent asserts).
              return SingleChildScrollView(
                physics:
                    canFitVertically
                        ? const NeverScrollableScrollPhysics()
                        : const ClampingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  vertical: canFitVertically ? 0 : 16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        pageCons.maxHeight.isFinite ? pageCons.maxHeight : 0,
                  ),
                  child: Align(
                    alignment:
                        canFitVertically
                            ? Alignment.center
                            : Alignment.topCenter,
                    child: scaledSurface,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _FramedHost extends StatefulWidget {
  final Widget child;
  const _FramedHost({required this.child});

  @override
  State<_FramedHost> createState() => _FramedHostState();
}

class _FramedHostState extends State<_FramedHost> {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute(
      settings: settings,
      builder: (context) {
        // Keep theme consistent with outer tree.
        return Theme(data: Theme.of(context), child: widget.child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Navigator(onGenerateRoute: _onGenerateRoute),
    );
  }
}
