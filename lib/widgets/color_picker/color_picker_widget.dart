import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'color_generation_utils.dart';
import 'hue_value_disc_painter.dart';

const double _kWorldScale = 6.4;

// ---------------------------------------------------------------------------
// Compact widget — tap to open immersive overlay
// ---------------------------------------------------------------------------

class ColorPickerWidget extends StatefulWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback? onPickComplete;

  const ColorPickerWidget({
    super.key,
    required this.currentColor,
    required this.onColorChanged,
    this.onPickComplete,
  });

  @override
  State<ColorPickerWidget> createState() => _ColorPickerWidgetState();
}

class _ColorPickerWidgetState extends State<ColorPickerWidget> {
  OverlayEntry? _entry;
  final GlobalKey _wheelKey = GlobalKey();

  void _startImmersive(Offset globalTap) {
    if (_entry != null) return;

    Offset tapFraction = const Offset(0.5, 0.5);
    final box = _wheelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      final local = box.globalToLocal(globalTap);
      final size = box.size;
      tapFraction = Offset(local.dx / size.width, local.dy / size.height);
    }

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _entry = OverlayEntry(
      builder: (_) => _ImmersiveWheel(
        initialColor: widget.currentColor,
        onColorChanged: widget.onColorChanged,
        onDone: _stopImmersive,
        tapFraction: tapFraction,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  void _stopImmersive() {
    _entry?.remove();
    _entry = null;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    widget.onPickComplete?.call();
  }

  @override
  void dispose() {
    _stopImmersive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _startImmersive(e.position),
      child: LayoutBuilder(builder: (context, constraints) {
        final double size = math.min(constraints.maxWidth, 260.0);
        return Center(
          child: SizedBox(
            key: _wheelKey,
            width: size,
            height: size,
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: CustomPaint(painter: HueValueDiscPainter()),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Immutable state for the immersive wheel
// ---------------------------------------------------------------------------

class _WheelState {
  final Offset pan;
  final double zoom;

  const _WheelState({required this.pan, this.zoom = 1.0});

  static const initial = _WheelState(pan: Offset.zero, zoom: 1.0);

  _WheelState copyWith({Offset? pan, double? zoom}) =>
      _WheelState(pan: pan ?? this.pan, zoom: zoom ?? this.zoom);
}

// ---------------------------------------------------------------------------
// Immersive full-screen wheel
// ---------------------------------------------------------------------------

class _ImmersiveWheel extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback onDone;
  final Offset tapFraction;

  const _ImmersiveWheel({
    required this.initialColor,
    required this.onColorChanged,
    required this.onDone,
    required this.tapFraction,
  });

  @override
  State<_ImmersiveWheel> createState() => _ImmersiveWheelState();
}

class _ImmersiveWheelState extends State<_ImmersiveWheel> {
  final _notifier = ValueNotifier(_WheelState.initial);
  Size _screen = Size.zero;
  bool _opened = false;
  double _scaleStart = 1.0; // zoom at the start of a pinch gesture

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    _notifier.dispose();
    super.dispose();
  }

  void _initPanFromTap() {
    if (_screen == Size.zero) return;
    final double zoom = _notifier.value.zoom;
    final double ws = _screen.shortestSide * _kWorldScale * zoom;
    final double tapWorldX = widget.tapFraction.dx * ws;
    final double tapWorldY = widget.tapFraction.dy * ws;
    final double noPanWorldLeft = (_screen.width - ws) / 2;
    final double noPanWorldTop = (_screen.height - ws) / 2;
    final double rawPanX = (_screen.width / 2 - tapWorldX) - noPanWorldLeft;
    final double rawPanY = (_screen.height / 2 - tapWorldY) - noPanWorldTop;
    final double maxX = math.max(0, (ws - _screen.width) / 2);
    final double maxY = math.max(0, (ws - _screen.height) / 2);
    _notifier.value = _notifier.value.copyWith(
      pan: Offset(rawPanX.clamp(-maxX, maxX), rawPanY.clamp(-maxY, maxY)),
    );
  }

  void _onGlobalPointer(PointerEvent e) {
    if (_screen == Size.zero) return;
    if (!_opened) {
      if (e is PointerUpEvent || e is PointerCancelEvent) _opened = true;
      return;
    }
    if (e is PointerMoveEvent) {
      final newPan = _clampPan(_notifier.value.pan + e.delta, _notifier.value.zoom);
      _notifier.value = _notifier.value.copyWith(pan: newPan);
      _sampleCenter(newPan, _notifier.value.zoom);
    }
  }

  double _worldLeft(Offset pan, double zoom) => (_screen.width - _screen.shortestSide * _kWorldScale * zoom) / 2 + pan.dx;
  double _worldTop(Offset pan, double zoom) => (_screen.height - _screen.shortestSide * _kWorldScale * zoom) / 2 + pan.dy;

  Offset _clampPan(Offset pan, double zoom) {
    final double ws = _screen.shortestSide * _kWorldScale * zoom;
    final double maxX = math.max(0, (ws - _screen.width) / 2);
    final double maxY = math.max(0, (ws - _screen.height) / 2);
    return Offset(pan.dx.clamp(-maxX, maxX), pan.dy.clamp(-maxY, maxY));
  }

  // Sample the color at screen center (the "selected" color as you pan)
  void _sampleCenter(Offset pan, double zoom) {
    final Offset center = Offset(_screen.width / 2, _screen.height / 2);
    final double ws = _screen.shortestSide * _kWorldScale * zoom;
    final double wl = _worldLeft(pan, zoom);
    final double wt = _worldTop(pan, zoom);
    final double wx = center.dx - wl;
    final double wy = center.dy - wt;
    final double radius = ws / 2;
    final double dx = wx - radius;
    final double dy = wy - radius;
    final double dist = math.sqrt(dx * dx + dy * dy);
    if (dist > radius) return;

    final double hubR = radius * kCenterNeutralFraction;
    Color c;
    if (dist <= hubR) {
      final int grey = ((dist / hubR) * 200 + 55).round().clamp(0, 255);
      c = Color.fromARGB(255, grey, grey, grey);
    } else {
      final double hue = calculateHueFromAngle(math.atan2(dy, dx));
      final double ringW = (radius - hubR) / kRings;
      final int ring = ((dist - hubR) / ringW).floor().clamp(0, kRings - 1);
      c = HSVColor.fromAHSV(1.0, hue, 1.0, calculateRingValueForMosaic(ring))
          .toColor();
    }
    widget.onColorChanged(c);
  }

  @override
  Widget build(BuildContext context) {
    final Size newScreen = MediaQuery.of(context).size;
    final bool firstBuild = _screen == Size.zero;
    _screen = newScreen;
    if (firstBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initPanFromTap());
    }

    return Material(
      color: Colors.white,
      child: Listener(
        // Mouse scroll wheel zoom for web desktop
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            final double delta = e.scrollDelta.dy.clamp(-50.0, 50.0);
            final double oldZoom = _notifier.value.zoom;
            final double newZoom = (oldZoom * (1 - delta / 300)).clamp(1.0, 8.0);
            // Zoom toward mouse cursor position
            final Offset focal = e.position;
            final double oldWs = _screen.shortestSide * _kWorldScale * oldZoom;
            final double oldWl = (_screen.width - oldWs) / 2 + _notifier.value.pan.dx;
            final double oldWt = (_screen.height - oldWs) / 2 + _notifier.value.pan.dy;
            final double fwx = focal.dx - oldWl;
            final double fwy = focal.dy - oldWt;
            final double newWs = _screen.shortestSide * _kWorldScale * newZoom;
            final double scale = newWs / oldWs;
            final double newWl = focal.dx - fwx * scale;
            final double newWt = focal.dy - fwy * scale;
            final double newPanX = newWl - (_screen.width - newWs) / 2;
            final double newPanY = newWt - (_screen.height - newWs) / 2;
            final newPan = _clampPan(Offset(newPanX, newPanY), newZoom);
            _notifier.value = _notifier.value.copyWith(pan: newPan, zoom: newZoom);
            _sampleCenter(newPan, newZoom);
          }
        },
        child: GestureDetector(
        // Pinch to zoom — works on mobile; scroll wheel on web desktop
        onScaleStart: (d) => _scaleStart = _notifier.value.zoom,
        onScaleUpdate: (d) {
          if (d.pointerCount < 2) return;
          final double newZoom = (_scaleStart * d.scale).clamp(1.0, 8.0);
          // Zoom toward the focal point (midpoint between fingers)
          // Keep the world point under the focal point fixed on screen.
          final Offset focal = d.focalPoint;
          final Offset oldPan = _notifier.value.pan;
          final double oldZoom = _notifier.value.zoom;
          // World point under focal before zoom
          final double oldWs = _screen.shortestSide * _kWorldScale * oldZoom;
          final double oldWl = (_screen.width - oldWs) / 2 + oldPan.dx;
          final double oldWt = (_screen.height - oldWs) / 2 + oldPan.dy;
          final double focalWorldX = focal.dx - oldWl;
          final double focalWorldY = focal.dy - oldWt;
          // After zoom, we want focal to still be at the same screen position
          final double newWs = _screen.shortestSide * _kWorldScale * newZoom;
          final double scale = newWs / oldWs;
          final double newWl = focal.dx - focalWorldX * scale;
          final double newWt = focal.dy - focalWorldY * scale;
          final double newPanX = newWl - (_screen.width - newWs) / 2;
          final double newPanY = newWt - (_screen.height - newWs) / 2;
          final newPan = _clampPan(Offset(newPanX, newPanY), newZoom);
          _notifier.value = _notifier.value.copyWith(pan: newPan, zoom: newZoom);
          _sampleCenter(newPan, newZoom);
        },
        child: ValueListenableBuilder<_WheelState>(
          valueListenable: _notifier,
          builder: (context, state, _) {
            final double ws = _screen.shortestSide * _kWorldScale * state.zoom;
            return Stack(
              children: [
                Positioned(
                  left: _worldLeft(state.pan, state.zoom),
                  top: _worldTop(state.pan, state.zoom),
                  child: SizedBox(
                    width: ws,
                    height: ws,
                    child: RepaintBoundary(
                      key: ValueKey('wheel_${state.zoom.toStringAsFixed(2)}'),
                      child: CustomPaint(
                        painter: HueValueDiscPainter(zoom: state.zoom),
                        isComplex: true,
                        willChange: true,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
    );
  }
}
