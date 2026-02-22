import 'dart:math' as math;

import 'package:color_wallet/menu.dart';
import 'package:color_wallet/services/user_repository.dart';
import 'package:color_wallet/widgets/scroll_hint_overlay.dart';
import 'package:color_wallet/widgets/wallet_badge_icon.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'daily_hues/daily_hues_screen.dart';
import 'create_screen.dart';
import 'wallet_screen.dart';

const double kCenterNeutralFraction = 0.11; // inner 11% of radius = neutral hub

class ColorPickerScreen extends StatefulWidget {
  const ColorPickerScreen({
    super.key,
    this.returnPickedColor = false,
    this.onPicked,
  });

  final bool returnPickedColor;
  final ValueChanged<Color>? onPicked;

  @override
  State<ColorPickerScreen> createState() => _ColorPickerScreenState();
}

class _ColorPickerScreenState extends State<ColorPickerScreen> {
  final GlobalKey _wheelKey = GlobalKey();
  Color? selectedColor;
  int? _lastRingIndex;

  final int _selectedIndex = 1;
  bool _openingMosaic = false;
  bool _hadValidPick = false;

  // recipients
  final _userRepo = UserRepository();
  List<AppUser> _users = [];
  bool _loadingUsers = true;
  String? _selectedRecipientId;
  String? _selectedRecipientName;

  @override
  void initState() {
    super.initState();
    _loadRecipients();
  }

  Future<void> _loadRecipients() async {
    try {
      final me = FirebaseAuth.instance.currentUser;
      if (me == null) {
        setState(() {
          _users = [];
          _loadingUsers = false;
        });
        return;
      }
      final list = await _userRepo.getAllUsersExcluding(me.uid);
      if (!mounted) return;
      setState(() {
        _users = list;
        _loadingUsers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _users = [];
        _loadingUsers = false;
      });
    }
  }

  void _onNavTapped(int index) {
    if (index == _selectedIndex) return;

    if (index == 0) {
      Navigator.of(
        context,
        rootNavigator: false,
      ).push(MaterialPageRoute(builder: (_) => const WalletScreen()));
    } else if (index == 1) {
      // already on ColorPicker (Vibes) — no-op
      return;
    } else if (index == 2) {
      Navigator.of(
        context,
        rootNavigator: false,
      ).push(MaterialPageRoute(builder: (_) => const DailyHuesScreen()));
    }
  }

  /// Returns true if the tap was inside the neutral centre hub.
  bool _handleColorSelection(Offset globalPosition) {
    final RenderBox? box =
        _wheelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;

    final local = box.globalToLocal(globalPosition);
    final size = box.size;
    final center = Offset(size.width / 2, size.height / 2);
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    final maxRadius = size.width / 2;
    final double centerNeutralRadius = maxRadius * kCenterNeutralFraction;

    // Inside neutral hub: do not set selectedColor; signal centre hit.
    if (distance <= centerNeutralRadius) {
      return true;
    }

    // Inside coloured rings region: normal hue/ring selection.
    if (distance <= maxRadius) {
      final angleRadians = math.atan2(dy, dx);
      final angleDegrees = (angleRadians * 180 / math.pi + 360 + 90) % 360;
      final hue = angleDegrees;

      const int rings = 10;
      final ringWidth = maxRadius / rings;
      final ringIndex = (distance / ringWidth).floor().clamp(0, rings - 1);
      final ringValue = math.pow((ringIndex + 1) / rings, 0.1).toDouble();

      const int fadeStartRing = 5;
      final int maxFadeRings = rings - fadeStartRing;
      final double opacity =
          ringIndex < fadeStartRing
              ? 1.0
              : 1.0 -
                  ((ringIndex - fadeStartRing + 1) / maxFadeRings).clamp(
                    0.0,
                    1.0,
                  );

      final newColor =
          HSVColor.fromAHSV(opacity, hue, 1.0, ringValue).toColor();

      setState(() {
        selectedColor = newColor.withAlpha(0xFF);
        _lastRingIndex = ringIndex;
        _hadValidPick = true;
      });
    }

    return false;
  }

  Future<void> _openMosaic() async {
    if (_openingMosaic) return;
    final base = selectedColor;
    if (base == null) return;

    _openingMosaic = true;
    try {
      final hsv = HSVColor.fromColor(base);
      final ringIndex = _lastRingIndex ?? 0;

      // Re-usable picker mode: just pick a color and return it.
      if (widget.returnPickedColor) {
        final picked = await Navigator.of(
          context,
          rootNavigator: false,
        ).push<Color?>(
          MaterialPageRoute(
            builder:
                (_) => ColorMosaicScreen(
                  baseHue: hsv.hue,
                  ringIndex: ringIndex,
                  returnPickedColor: true,
                ),
          ),
        );

        if (picked != null && mounted) {
          final solid = picked.withAlpha(0xFF);
          widget.onPicked?.call(solid);
          Navigator.of(context, rootNavigator: false).pop(solid);
        }
        return;
      }

      // Normal Send-Vibes flow:
      // Wheel → Mosaic → CreateScreen
      // Back from CreateScreen returns to Mosaic (with pulsing tile).
      Navigator.of(context, rootNavigator: false).push(
        MaterialPageRoute(
          builder:
              (_) => ColorMosaicScreen(
                baseHue: hsv.hue,
                ringIndex: ringIndex,
                presetRecipientId: _selectedRecipientId,
                presetRecipientName: _selectedRecipientName,
                returnPickedColor: false,
              ),
        ),
      );
    } finally {
      _openingMosaic = false;
    }
  }

  Future<void> _openNeutralMosaic() async {
    if (_openingMosaic) return;

    _openingMosaic = true;
    try {
      if (widget.returnPickedColor) {
        final picked = await Navigator.of(
          context,
          rootNavigator: false,
        ).push<Color?>(
          MaterialPageRoute(
            builder: (_) => const NeutralMosaicScreen(returnPickedColor: true),
          ),
        );

        if (picked != null && mounted) {
          final solid = picked.withAlpha(0xFF);
          widget.onPicked?.call(solid);
          Navigator.of(context, rootNavigator: false).pop(solid);
        }
        return;
      }

      // Normal Send Vibes flow (neutral path)
      Navigator.of(context, rootNavigator: false).push(
        MaterialPageRoute(
          builder:
              (_) => NeutralMosaicScreen(
                presetRecipientId: _selectedRecipientId,
                presetRecipientName: _selectedRecipientName,
              ),
        ),
      );
    } finally {
      _openingMosaic = false;
    }
  }

  // ---------- bottom-sheet recipient picker ----------

  Future<void> _openRecipientSheet() async {
    final picked = await showModalBottomSheet<_PickedRecipient>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (_) => _RecipientPickerSheet(users: _users, loading: _loadingUsers),
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedRecipientId = picked.id;
        _selectedRecipientName = picked.name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const double kButtonFixedH = 44.0;
    const double kPreviewMin = 100.0;
    const double kPreviewMax = 160.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        toolbarHeight: 56,
        title: const Text('Color Wheel', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            // Robust back: try local pop, then root pop, else fallback to Wallet.
            final nav = Navigator.of(context, rootNavigator: false);
            if (nav.canPop()) {
              nav.pop();
              return;
            }
            final root = Navigator.of(context, rootNavigator: true);
            if (root.canPop()) {
              root.pop();
              return;
            }
            nav.pushReplacement(
              MaterialPageRoute(builder: (_) => const WalletScreen()),
            );
          },
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 4),
            child: ZenmoMenuButton(isOnColorPicker: true),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Colors.black26),
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: LayoutBuilder(
          builder: (context, cons) {
            final viewInsets = MediaQuery.of(context).viewInsets.bottom;

            final double h = cons.maxHeight;
            final double w = cons.maxWidth;
            final double shortest = math.min(w, h);
            final bool compact = shortest < 360 || h < 600;

            final bool showButton = !widget.returnPickedColor;
            final double buttonH = showButton ? kButtonFixedH : 0.0;

            final double bottomReserve =
                12 + MediaQuery.of(context).viewPadding.bottom;

            final double previewSide =
                (w * (compact ? 0.38 : 0.42))
                    .clamp(kPreviewMin, kPreviewMax)
                    .toDouble();

            // Wheel size is now driven purely by width, so it can be as
            // wide as the buttons / card on all devices.
            final double widthCap = (w * (compact ? 0.90 : 0.92));
            const double kMinWheel = 160.0;
            final double kMaxWheel = compact ? 520.0 : 680.0;
            double wheelSide = widthCap.clamp(kMinWheel, kMaxWheel);

            // Approximate height of the recipient picker row
            const double pickerApproxH = 56.0;

            // Use leftover height only to space things out;
            // overflow is handled by SingleChildScrollView.
            final double leftover = (h -
                    previewSide -
                    wheelSide -
                    pickerApproxH -
                    buttonH)
                .clamp(0.0, double.infinity);

            final double gapTop = leftover / 4.0;
            final double gapBottom = leftover - gapTop;

            Widget buildPreview(double side) => SizedBox(
              height: side,
              width: side,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selectedColor ?? Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black26),
                ),
                child:
                    selectedColor == null
                        ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: Text(
                              'Send good vibes\nby selecting one of\n16 million colors below',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, height: 1.15),
                            ),
                          ),
                        )
                        : null,
              ),
            );

            Widget buildWheelBox(double side) => SizedBox(
              width: side,
              height: side,
              child: GestureDetector(
                onPanUpdate: (d) {
                  // Pan is only for colour picking in the ring area.
                  _handleColorSelection(d.globalPosition);
                },
                onTapDown: (d) {
                  final bool isCenter = _handleColorSelection(d.globalPosition);
                  if (isCenter) {
                    _openNeutralMosaic();
                    _hadValidPick = false; // prevent colour mosaic on tapUp
                  }
                },
                onTapUp: (_) {
                  if (_hadValidPick) _openMosaic();
                  _hadValidPick = false;
                },
                child: Container(
                  key: _wheelKey,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: CustomPaint(painter: HueValueDiscPainter()),
                ),
              ),
            );

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.only(bottom: viewInsets > 0 ? viewInsets : 0),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: h),
                child: Column(
                  children: [
                    SizedBox(height: gapTop),
                    buildPreview(previewSide),
                    SizedBox(height: gapTop),
                    Center(child: buildWheelBox(wheelSide)),

                    // --- Recipient UI (still available here) ---
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child:
                          (_selectedRecipientId == null)
                              ? SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _openRecipientSheet,
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: const Text('Choose recipient'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(44),
                                    side: const BorderSide(
                                      color: Color(0xFFC9CCD3),
                                    ),
                                    foregroundColor: const Color(0xFF2D3142),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              )
                              : Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'TO: ${_selectedRecipientName ?? _selectedRecipientId!}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black87,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _openRecipientSheet,
                                    child: const Text('Change'),
                                  ),
                                ],
                              ),
                    ),

                    if (!widget.returnPickedColor) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: double.infinity,
                          height: kButtonFixedH,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4B5563),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            onPressed: () async {
                              // If no recipient yet, let them pick one first.
                              if (_selectedRecipientId == null) {
                                await _openRecipientSheet();
                                if (_selectedRecipientId == null) return;
                              }
                              final Color fallback = const Color.fromARGB(
                                255,
                                253,
                                253,
                                253,
                              );
                              Navigator.of(context, rootNavigator: false).push(
                                MaterialPageRoute(
                                  builder:
                                      (_) => CreateScreen(
                                        selectedColor:
                                            selectedColor ?? fallback,
                                        presetRecipientId:
                                            _selectedRecipientId!,
                                        presetRecipientName:
                                            _selectedRecipientName ??
                                            _selectedRecipientId!,
                                      ),
                                ),
                              );
                            },
                            child: const Text(
                              'Preview + Name Color',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(height: bottomReserve),
                    ],
                    SizedBox(height: gapBottom),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTapped,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
        items: const [
          BottomNavigationBarItem(icon: WalletBadgeIcon(), label: 'Wallet'),
          BottomNavigationBarItem(icon: Icon(Icons.brush), label: 'Send Vibes'),
          BottomNavigationBarItem(
            label: 'Daily Hues',
            icon: Icon(Icons.grid_view_rounded),
          ),
        ],
      ),
    );
  }
}

// ---------- bottom-sheet widgets ----------

class _PickedRecipient {
  final String id;
  final String name;
  const _PickedRecipient({required this.id, required this.name});
}

class _RecipientPickerSheet extends StatefulWidget {
  final List<AppUser> users;
  final bool loading;
  const _RecipientPickerSheet({required this.users, required this.loading});

  @override
  State<_RecipientPickerSheet> createState() => _RecipientPickerSheetState();
}

class _RecipientPickerSheetState extends State<_RecipientPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lower = _query.toLowerCase();
    final filtered =
        widget.users.where((u) {
          final name = u.displayName.toLowerCase();
          final id = (u.effectiveUid ?? u.uid).toLowerCase();
          return lower.isEmpty || name.contains(lower) || id.contains(lower);
        }).toList();

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: widget.users.isNotEmpty,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search people',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child:
                widget.loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final u = filtered[i];
                        final String fallbackId = u.effectiveUid ?? u.uid;
                        final String display =
                            (u.displayName.trim().isEmpty)
                                ? fallbackId
                                : u.displayName;

                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title: Text(
                            display,
                            style: theme.textTheme.bodyLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap:
                              () => Navigator.of(
                                context,
                                rootNavigator: false,
                              ).pop(
                                _PickedRecipient(id: fallbackId, name: display),
                              ),
                        );
                      },
                    ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------- color wheel painter ----------

class HueValueDiscPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const int numberOfRings = 10;
    const int angleStep = 12;
    final radius = size.width / 2;
    final center = Offset(radius, radius);

    final double centerNeutralRadius = radius * kCenterNeutralFraction;
    final double available = radius - centerNeutralRadius;

    for (int ring = 0; ring < numberOfRings; ring++) {
      final double innerRadius =
          centerNeutralRadius + available * ring / numberOfRings;
      final double outerRadius =
          centerNeutralRadius + available * (ring + 1) / numberOfRings;
      final double value = math.pow((ring + 1) / numberOfRings, 0.5).toDouble();

      const int fadeStartRing = 5;
      final int maxFadeRings = numberOfRings - fadeStartRing;
      final double opacity =
          ring < fadeStartRing
              ? 1.0
              : 1.0 -
                  ((ring - fadeStartRing + 1) / maxFadeRings).clamp(0.0, 1.0);

      for (int angle = 0; angle < 360; angle += angleStep) {
        final double startAngle = (angle - 90) * math.pi / 180;
        final double sweepAngle = angleStep * math.pi / 180;

        final paint =
            Paint()
              ..color =
                  HSVColor.fromAHSV(
                    opacity,
                    angle.toDouble(),
                    1.0,
                    value,
                  ).toColor()
              ..style = PaintingStyle.stroke
              ..strokeWidth = outerRadius - innerRadius;

        final double ringMidRadius = (innerRadius + outerRadius) / 2;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: ringMidRadius),
          startAngle,
          sweepAngle,
          false,
          paint,
        );
      }
    }

    // Draw neutral centre pie (black → white slices).
    const int slices = 8;
    final double sliceSweep = 2 * math.pi / slices;
    final List<Color> greySlices = [
      const Color(0xFF101010),
      const Color(0xFF2A2A2A),
      const Color(0xFF505050),
      const Color(0xFF7A7A7A),
      const Color(0xFF9D9D9D),
      const Color(0xFFC3C3C3),
      const Color(0xFFE4E4E4),
      const Color(0xFFF8F8F8),
    ];

    for (int i = 0; i < slices; i++) {
      final double start = -math.pi / 2 + i * sliceSweep;
      final paint =
          Paint()
            ..style = PaintingStyle.fill
            ..color = greySlices[i % greySlices.length];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: centerNeutralRadius),
        start,
        sliceSweep,
        true,
        paint,
      );
    }

    // Optional subtle outline around the neutral hub for crispness.
    final outlinePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.black.withOpacity(0.12);
    canvas.drawCircle(center, centerNeutralRadius, outlinePaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// ---------- mosaic screen ----------

enum MosaicMode { random, ordered }

class ColorMosaicScreen extends StatefulWidget {
  final double baseHue;
  final int ringIndex;
  final bool returnPickedColor;
  final String? presetRecipientId;
  final String? presetRecipientName;

  const ColorMosaicScreen({
    super.key,
    required this.baseHue,
    required this.ringIndex,
    this.returnPickedColor = false,
    this.presetRecipientId,
    this.presetRecipientName,
  });

  @override
  State<ColorMosaicScreen> createState() => _ColorMosaicScreenState();
}

class _ColorMosaicScreenState extends State<ColorMosaicScreen>
    with SingleTickerProviderStateMixin {
  // FIXED GRID for ORGANIZED
  static const int _cols = 6;
  static const int _tileCount = 600;

  // random-mode constants (unchanged)
  static const double _cellSide = 28;
  static const double _sMinGlobal = 0.24;
  static const double _vMinGlobal = 0.32;
  static const double _vMaxGlobal = 0.98;

  static const List<double> _vBiasByRing = <double>[
    -0.10,
    -0.08,
    -0.06,
    -0.03,
    -0.01,
    0.01,
    0.03,
    0.06,
    0.08,
    0.10,
  ];
  static const List<double> _sBiasByRing = <double>[
    0.04,
    0.03,
    0.02,
    0.01,
    0.00,
    -0.01,
    -0.02,
    -0.03,
    -0.04,
    -0.06,
  ];

  _HSV _applyRingBias(_HSV c, int ring) {
    final int r = ring.clamp(0, 9);
    final double s = math.max(
      _sMinGlobal,
      math.min(1.0, c.s + _sBiasByRing[r]),
    );
    final double v = math.max(
      _vMinGlobal,
      math.min(_vMaxGlobal, c.v + _vBiasByRing[r]),
    );
    return c.copyWith(s: s, v: v);
  }

  static const double _hueSeedStepDeg = 0.25;
  int _qHueIdx(double hueDeg) {
    final h = ((hueDeg % 360) + 360) % 360;
    return (h / _hueSeedStepDeg).round();
  }

  // random hue drift around base per ring
  static const List<double> _hueDrift = <double>[
    12,
    12,
    10,
    10,
    8,
    6,
    5,
    4,
    3,
    2,
  ];

  // clusters for randomized sampler (RANDOM MODE ONLY)
  static const _Cluster pastel = _Cluster(
    sMin: 0.28,
    sMax: 0.50,
    vMin: 0.85,
    vMax: 0.98,
  );
  static const _Cluster mid = _Cluster(
    sMin: 0.50,
    sMax: 0.75,
    vMin: 0.60,
    vMax: 0.85,
  );
  static const _Cluster vivid = _Cluster(
    sMin: 0.75,
    sMax: 0.95,
    vMin: 0.60,
    vMax: 0.90,
  );
  static const _Cluster ink = _Cluster(
    sMin: 0.75,
    sMax: 1.00,
    vMin: 0.30,
    vMax: 0.55,
  );
  static const _Cluster neon = _Cluster(
    sMin: 0.95,
    sMax: 1.00,
    vMin: 0.97,
    vMax: 1.00,
  );

  static const List<_ClusterWeights> _wByRing = <_ClusterWeights>[
    _ClusterWeights(mid: 0.20, vivid: 0.10, ink: 0.60, neon: 0.10),
    _ClusterWeights(mid: 0.35, vivid: 0.20, ink: 0.35, neon: 0.10),
    _ClusterWeights(mid: 0.40, vivid: 0.28, ink: 0.22, neon: 0.10),
    _ClusterWeights(mid: 0.45, vivid: 0.35, ink: 0.12, neon: 0.08),
    _ClusterWeights(
      vivid: 0.50,
      mid: 0.35,
      pastel: 0.07,
      ink: 0.05,
      neon: 0.03,
    ),
    _ClusterWeights(vivid: 0.55, mid: 0.30, pastel: 0.10, neon: 0.05),
    _ClusterWeights(vivid: 0.40, mid: 0.30, pastel: 0.25, neon: 0.05),
    _ClusterWeights(pastel: 0.40, mid: 0.35, vivid: 0.20, neon: 0.05),
    _ClusterWeights(pastel: 0.62, mid: 0.18, vivid: 0.08, neon: 0.12),
    _ClusterWeights(pastel: 0.68, mid: 0.16, vivid: 0.04, neon: 0.12),
  ];

  static const double _antiClumpThreshold = 0.085;

  MosaicMode _mode = MosaicMode.random;

  // ----------------- ORDERED cache -----------------
  List<Color>? _orderedColors;
  int? _ordHueKey;
  int? _ordRingKey;

  // ----------------- highlight + glow -----------------
  int? _activeTileIndex;
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _glowAnimation = CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _startGlowPulse() {
    _glowController
      ..stop()
      ..reset();
    _glowController.repeat(reverse: true);
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      _glowController.stop();
      // leave a soft "after-glow"
      _glowController.forward(from: 0.0);
    });
  }

  void _handleTileTap(int index, Color color) {
    // Picker-only mode: just return the color.
    if (widget.returnPickedColor) {
      Navigator.of(context, rootNavigator: false).pop(color);
      return;
    }

    // Normal flow: go to CreateScreen; when user backs out, pulse this tile.
    Navigator.of(context, rootNavigator: false)
        .push(
          MaterialPageRoute(
            builder:
                (_) => CreateScreen(
                  selectedColor: color,
                  presetRecipientId: widget.presetRecipientId,
                  presetRecipientName: widget.presetRecipientName,
                ),
          ),
        )
        .then((_) {
          if (!mounted) return;
          setState(() {
            _activeTileIndex = index;
          });
        });
  }

  Widget _buildTile({
    required int index,
    required Color color,
    required Widget inner,
    bool disableInkEffects = false,
  }) {
    final bool isActive = _activeTileIndex == index;

    Widget ink;
    if (disableInkEffects) {
      ink = InkWell(
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        splashColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: () => _handleTileTap(index, color),
        child: inner,
      );
    } else {
      ink = InkWell(onTap: () => _handleTileTap(index, color), child: inner);
    }

    if (!isActive) return ink;

    // Active tile: persistent outline (no pulsing / no scaling)
    final bool lightTile = color.computeLuminance() > 0.55;
    final Color strokeBase = lightTile ? Colors.black : Colors.white;

    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border.all(color: strokeBase.withOpacity(0.95), width: 3.0),
      ),
      child: ink,
    );
  }

  double _clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);
  double _wrapHue(double h) {
    final hh = h % 360.0;
    return hh < 0 ? hh + 360.0 : hh;
  }

  double _ease(double x, double g) => math.pow(x.clamp(0.0, 1.0), g).toDouble();

  // Build ordered palette once per (hue, ring). Fully deterministic.
  void _ensureOrderedCache() {
    final int hueKey = _qHueIdx(widget.baseHue);
    final int ringKey = widget.ringIndex.clamp(0, 9);
    if (_orderedColors != null &&
        _ordHueKey == hueKey &&
        _ordRingKey == ringKey) {
      return; // cache valid
    }
    // ---- parameters for ordered ramp (HSV) ----
    const int cols = _cols; // 6 columns
    final int rows = (_tileCount / cols).ceil();
    final double hue = widget.baseHue;

    // Ring interpolation factor (0 = inner, 1 = outer)
    final double ringT = ringKey / 9.0;

    // Value (brightness) ramp:
    // Inner rings: deeper/darker range
    // Outer rings: lighter/airier range (also prevents grey→black tail)
    const double vMax = 1.00;
    const double vMinInner = 0.16;
    const double vMinOuter = 0.30;

    final double vMin = vMinInner + (vMinOuter - vMinInner) * ringT;

    const double vGammaInner = 0.78;
    const double vGammaOuter = 0.62;

    final double vGamma = vGammaInner + (vGammaOuter - vGammaInner) * ringT;

    // Ring-based saturation band:
    // Inner rings: more punch + broader S range
    // Outer rings: noticeably softer + more washed-out potential
    const double strongInner = 1.00;
    const double strongOuter = 0.70;
    const double weakInner = 0.20;
    const double weakOuter = 0.05;

    final double sStrong =
        strongInner + (strongOuter - strongInner) * ringT; // col 1
    final double sWeak = weakInner + (weakOuter - weakInner) * ringT; // col 6

    const double sGamma = 1.10;

    1.10; // slow the drop so mid-columns aren’t all washed

    final List<Color> colors = List<Color>.generate(_tileCount, (i) {
      final int row = i ~/ cols;
      final int col = i % cols;

      // Vertical value ramp (top = brightest, bottom = darkest)
      final double tV = rows <= 1 ? 0.0 : row / (rows - 1);
      final double tVFlipped = 1.0 - tV;
      double v = vMin + (vMax - vMin) * _ease(tVFlipped, vGamma);

      // Horizontal saturation ramp (left = strongest colour, right = most washed-out)
      final double tS = cols <= 1 ? 0.0 : col / (cols - 1);
      final double sEdgeMax = sStrong;
      final double sEdgeMin = sWeak;
      double s = sEdgeMax + (sEdgeMin - sEdgeMax) * _ease(tS, sGamma);
      s = _clamp01(s);

      // Avoid extremely dead, muddy tiles.
      if (s * v < 0.06) {
        v = (v + 0.035).clamp(vMin, vMax);
      }

      return HSVColor.fromAHSV(1.0, hue, s, v).toColor();
    });

    _orderedColors = colors;
    _ordHueKey = hueKey;
    _ordRingKey = ringKey;
  }

  // Segmented control (Organized / Randomized)
  Widget _modeSegmentedPill() {
    final bool ordered = _mode == MosaicMode.ordered;
    final bool random = _mode == MosaicMode.random;

    Widget seg(
      String label,
      bool selected,
      VoidCallback onTap, {
      BorderRadius? radius,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: radius ?? BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFD0D4DB) : Colors.white,
            borderRadius: radius ?? BorderRadius.zero,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFC5CF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(
            'Organized',
            ordered,
            () => setState(() => _mode = MosaicMode.ordered),
            radius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              bottomLeft: Radius.circular(8),
            ),
          ),
          Container(width: 1, height: 28, color: const Color(0xFFBFC5CF)),
          seg(
            'Randomized',
            random,
            () => setState(() => _mode = MosaicMode.random),
            radius: const BorderRadius.only(
              topRight: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int seed = _qHueIdx(widget.baseHue) * 1009 + widget.ringIndex * 9176;
    final rnd = math.Random(seed);

    // Build samples
    late final List<_HSV> samples;
    if (_mode == MosaicMode.random) {
      final _ClusterWeights w = _wByRing[widget.ringIndex.clamp(0, 9)];
      samples = _generateRandomSamples(
        hue: widget.baseHue,
        hueJitter: _hueDrift[widget.ringIndex.clamp(0, 9)],
        weights: w,
        total: _tileCount,
        rnd: rnd,
        ringIndex: widget.ringIndex,
      );
    } else {
      // ordered path uses cache
      samples = const <_HSV>[];
    }

    // RANDOM vs ORDERED post-processing
    List<Color> colors;
    List<int> tileHeights;
    if (_mode == MosaicMode.random) {
      _antiClump(samples, rnd, threshold: _antiClumpThreshold);
      final List<int> heights = _assignHeights(rnd, count: samples.length);
      final Map<int, int> counts = <int, int>{};
      colors = _toUniqueColors(samples, rnd, counts, maxPerColor: 1);
      tileHeights = List<int>.from(heights);

      // sprinkle neutrals for inner rings (random only)
      if (widget.ringIndex <= 2) {
        final int L = colors.length;
        final int N = (L * 0.05).round().clamp(6, 9999).toInt();

        final Set<int> pos = <int>{};
        final int start = (L * 0.05).floor();
        while (pos.length < N) {
          final int span = (L - start) <= 1 ? 1 : (L - start);
          pos.add(start + rnd.nextInt(span));
        }
        final List<int> sortedPos = pos.toList()..sort();
        final List<Color> neutrals = _makeNeutralsUnique(
          N,
          rnd,
          counts,
          maxPerColor: 1,
        );
        for (int i = 0; i < neutrals.length - 1; i++) {
          final int j = i + rnd.nextInt(neutrals.length - i);
          final tmp = neutrals[i];
          neutrals[i] = neutrals[j];
          neutrals[j] = tmp;
        }
        for (int i = 0; i < sortedPos.length; i++) {
          final int at = sortedPos[i] + i;
          final Color c = neutrals[i];
          colors.insert(at, c);
          tileHeights.insert(at, 2);
          counts[c.value] = 1;
        }
      }
    } else {
      // ORDERED: build once and reuse (prevents scroll shuffle)
      _ensureOrderedCache();
      colors = _orderedColors!;
      tileHeights = const <int>[]; // not used in fixed grid
    }

    // Choose grid widget per mode
    final Widget orderedGrid = GridView.builder(
      key: ValueKey('orderedGrid:$_ordHueKey:$_ordRingKey'),
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: 800,
      itemCount: colors.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _cols,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
        childAspectRatio: 1.0,
      ),
      itemBuilder: (context, i) {
        final c = colors[i];
        return _buildTile(
          index: i,
          color: c,
          disableInkEffects: true,
          inner: Container(color: c),
        );
      },
    );

    final Widget randomGrid = MasonryGridView.count(
      primary: true,
      physics: const AlwaysScrollableScrollPhysics(),
      crossAxisCount: _cols,
      mainAxisSpacing: 0,
      crossAxisSpacing: 0,
      cacheExtent: 800,
      itemCount: colors.length,
      itemBuilder: (context, i) {
        final c = colors[i];
        final units = tileHeights[i];
        return _buildTile(
          index: i,
          color: c,
          inner: Container(height: _cellSide * units, color: c),
        );
      },
    );

    // Show ScrollHint overlay (pulsing black chevron) on BOTH modes
    final Widget gridWithChevron = ScrollHintOverlay(
      visual: ScrollHintVisual.nakedSingle,
      brandColor: Colors.black,
      chipSize: 88,
      initialDelay: Duration.zero,
      maxShowDuration: const Duration(days: 365),
      showBottomGradient: false,
      bottomPadding: MediaQuery.of(context).padding.bottom + 24,
      alwaysShow: true,
      child: (_mode == MosaicMode.ordered) ? orderedGrid : randomGrid,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            gridWithChevron,
            // Back button (top-left)
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: const Icon(Icons.chevron_left, size: 28),
                  color: Colors.black,
                  splashRadius: 22,
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Back',
                ),
              ),
            ),
            // Segmented control (Organized / Randomized) centered top
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(child: _modeSegmentedPill()),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- RANDOMIZED (unchanged) ----------
  List<_HSV> _generateRandomSamples({
    required double hue,
    required double hueJitter,
    required _ClusterWeights weights,
    required int total,
    required math.Random rnd,
    required int ringIndex,
  }) {
    final counts = weights.asCounts(total);
    final List<_HSV> out = [];

    void addCluster(_Cluster cluster, int n) {
      for (int i = 0; i < n; i++) {
        final double h =
            (hue - hueJitter + rnd.nextDouble() * (2 * hueJitter)) % 360;
        double s =
            cluster.sMin + rnd.nextDouble() * (cluster.sMax - cluster.sMin);
        double v =
            cluster.vMin + rnd.nextDouble() * (cluster.vMax - cluster.vMin);

        if (s < _sMinGlobal) s = _sMinGlobal;
        if (v < _vMinGlobal) v = _vMinGlobal;
        if (v > _vMaxGlobal) v = _vMaxGlobal;

        final _HSV adjusted0 = _antiBrownAdjust(_HSV(h: h, s: s, v: v));
        final _HSV adjusted = _applyRingBias(adjusted0, ringIndex);
        out.add(adjusted);
      }
    }

    addCluster(pastel, counts.pastel);
    addCluster(mid, counts.mid);
    addCluster(vivid, counts.vivid);
    addCluster(ink, counts.ink);
    addCluster(neon, counts.neon);

    out.shuffle(rnd);
    return out;
  }

  _HSV _antiBrownAdjust(_HSV c) {
    final double h = (c.h % 360);
    final bool inOrangeRed = (h >= 350 || h < 30) || (h >= 30 && h < 50);
    final bool inOliveZone = (h >= 50 && h < 95);

    if (inOrangeRed && c.v < 0.58) c = c.copyWith(v: 0.60 + c.v * 0.05);
    if (inOliveZone && c.v < 0.50) c = c.copyWith(v: 0.58 + c.v * 0.04);
    if (c.s < 0.30) c = c.copyWith(s: 0.30);
    return c;
  }

  void _antiClump(
    List<_HSV> list,
    math.Random rnd, {
    required double threshold,
  }) {
    for (int i = 1; i < list.length; i++) {
      final _HSV a = list[i - 1];
      final _HSV b = list[i];
      if (_distance(a, b) < threshold) {
        bool swapped = false;
        final int maxLook =
            ((list.length - 1) < (i + 12)) ? (list.length - 1) : (i + 12);

        for (int j = i + 1; j <= maxLook; j++) {
          if (_distance(a, list[j]) >= threshold) {
            final tmp = list[i];
            list[i] = list[j];
            list[j] = tmp;
            swapped = true;
            break;
          }
        }
        if (!swapped) {
          final int ahead = list.length - i - 1;
          if (ahead > 0) {
            final int span = math.min(8, ahead);
            final int j = i + 1 + rnd.nextInt(span);
            final tmp = list[i];
            list[i] = list[j];
            list[j] = tmp;
          }
        }
      }
    }
  }

  double _distance(_HSV a, _HSV b) {
    final double dh = (a.h - b.h).abs();
    final double hueDiff = (dh > 180 ? 360 - dh : dh) / 180.0;
    final double ds = (a.s - b.s).abs();
    final double dv = (a.v - b.v).abs();
    const double wH = 0.6, wS = 1.0, wV = 1.0;
    return math.sqrt(
      (hueDiff * wH) * (hueDiff * wH) +
          (ds * wS) * (ds * wS) +
          (dv * wV) * (dv * wV),
    );
  }

  List<int> _assignHeights(math.Random rnd, {required int count}) {
    const double heroRate = 0.04;
    const int minUnits = 1;
    const int maxUnits = 3;

    final List<int> heights = List<int>.filled(count, minUnits);
    final int heroCount = (count * heroRate).round();
    final Set<int> heroIdx = <int>{};
    while (heroIdx.length < heroCount) {
      heroIdx.add(rnd.nextInt(count));
    }
    for (int i = 0; i < count; i++) {
      if (heroIdx.contains(i)) {
        heights[i] = 4;
      } else {
        heights[i] = minUnits + rnd.nextInt(maxUnits - minUnits + 1);
      }
    }
    return heights;
  }

  List<Color> _toUniqueColors(
    List<_HSV> samples,
    math.Random rnd,
    Map<int, int> counts, {
    int maxPerColor = 1,
  }) {
    double clamp(double x, double lo, double hi) =>
        x < lo ? lo : (x > hi ? hi : x);
    double wrapHue(double h) {
      final hh = h % 360.0;
      return hh < 0 ? hh + 360.0 : hh;
    }

    final Set<int> seen = <int>{};
    final List<Color> out = [];

    for (var c in samples) {
      _HSV candidate = c;
      Color col = candidate.toColor();

      int tries = 0;
      while (seen.contains(col.value) && tries < 10) {
        final dh = (rnd.nextDouble() * 0.50) - 0.25; // ±0.25°
        final ds = (rnd.nextDouble() * 0.02) - 0.01; // ±1%
        final dv = (rnd.nextDouble() * 0.02) - 0.01; // ±1%
        candidate = _HSV(
          h: wrapHue(candidate.h + dh),
          s: clamp(candidate.s + ds, _sMinGlobal, 1.0),
          v: clamp(candidate.v + dv, _vMinGlobal, _vMaxGlobal),
        );
        col = candidate.toColor();
        tries++;
      }
      if (seen.contains(col.value)) {
        candidate = candidate.copyWith(h: wrapHue(candidate.h + 0.33));
        col = candidate.toColor();
      }

      out.add(col);
      seen.add(col.value);
      counts[col.value] = 1;
    }
    return out;
  }

  // ---------- shared helpers/types ----------
}

class _Bucket {
  final double lo, hi, w;
  const _Bucket(this.lo, this.hi, this.w);
}

class _Cluster {
  final double sMin, sMax, vMin, vMax;
  const _Cluster({
    required this.sMin,
    required this.sMax,
    required this.vMin,
    required this.vMax,
  });
}

class _ClusterWeights {
  final double neutral;
  final double pastel;
  final double mid;
  final double vivid;
  final double ink;
  final double neon;

  const _ClusterWeights({
    this.neutral = 0.0,
    this.pastel = 0.0,
    this.mid = 0.0,
    this.vivid = 0.0,
    this.ink = 0.0,
    this.neon = 0.0,
  });

  _Counts asCounts(int total) {
    final List<double> ws = [neutral, pastel, mid, vivid, ink, neon];
    final double sum = ws.fold(0.0, (a, b) => a + b);
    final List<int> raw =
        ws.map((w) => (w / (sum == 0 ? 1 : sum) * total).floor()).toList();
    int used = raw.fold(0, (a, b) => a + b);
    int idx = 0;
    while (used < total) {
      raw[idx % raw.length] += 1;
      used++;
      idx++;
    }
    return _Counts(
      neutral: raw[0],
      pastel: raw[1],
      mid: raw[2],
      vivid: raw[3],
      ink: raw[4],
      neon: raw[5],
    );
  }
}

class _Counts {
  final int neutral, pastel, mid, vivid, ink, neon;
  const _Counts({
    required this.neutral,
    required this.pastel,
    required this.mid,
    required this.vivid,
    required this.ink,
    required this.neon,
  });
}

class _HSV {
  final double h;
  final double s;
  final double v;
  const _HSV({required this.h, required this.s, required this.v});
  _HSV copyWith({double? h, double? s, double? v}) =>
      _HSV(h: h ?? this.h, s: s ?? this.s, v: v ?? this.v);
  Color toColor() => HSVColor.fromAHSV(1.0, h, s, v).toColor();
}

// ---------- neutrals helper (added) ----------
List<Color> _makeNeutralsUnique(
  int n,
  math.Random rnd,
  Map<int, int> counts, {
  int maxPerColor = 1,
}) {
  final buckets = <_Bucket>[
    _Bucket(0.00, 0.06, 0.15),
    _Bucket(0.06, 0.25, 0.25),
    _Bucket(0.25, 0.55, 0.25),
    _Bucket(0.55, 0.85, 0.20),
    _Bucket(0.85, 1.00, 0.15),
  ];
  final double totalW = buckets.fold(0.0, (a, b) => a + b.w);

  double pickV() {
    double pick = rnd.nextDouble() * totalW;
    _Bucket chosen = buckets.first;
    for (final b in buckets) {
      if (pick <= b.w) {
        chosen = b;
        break;
      }
      pick -= b.w;
    }
    return chosen.lo + rnd.nextDouble() * (chosen.hi - chosen.lo);
  }

  final Set<int> seen = counts.keys.toSet();
  final List<Color> out = [];
  for (int i = 0; i < n; i++) {
    double v = pickV();
    Color c = HSVColor.fromAHSV(1.0, 0.0, 0.0, v).toColor();

    int tries = 0;
    while (seen.contains(c.value) && tries < 10) {
      v = (v + (rnd.nextDouble() * 0.015) - 0.0075).clamp(0.0, 1.0).toDouble();
      c = HSVColor.fromAHSV(1.0, 0.0, 0.0, v).toColor();
      tries++;
    }
    if (seen.contains(c.value)) {
      v = (v + 0.004).clamp(0.0, 1.0).toDouble();
      c = HSVColor.fromAHSV(1.0, 0.0, 0.0, v).toColor();
    }

    out.add(c);
    seen.add(c.value);
    counts[c.value] = 1;
  }
  return out;
}

// ---------- neutral mosaic screen ----------

class NeutralMosaicScreen extends StatefulWidget {
  final bool returnPickedColor;
  final String? presetRecipientId;
  final String? presetRecipientName;

  const NeutralMosaicScreen({
    super.key,
    this.returnPickedColor = false,
    this.presetRecipientId,
    this.presetRecipientName,
  });

  @override
  State<NeutralMosaicScreen> createState() => _NeutralMosaicScreenState();
}

class _NeutralMosaicScreenState extends State<NeutralMosaicScreen> {
  static const int _cols = 6;
  static const int _tileCount = 240;

  late final List<Color> _colors;

  @override
  void initState() {
    super.initState();
    _colors = _buildGreys();
  }

  List<Color> _buildGreys() {
    const double vMin = 0.05;
    const double vMax = 0.98;
    final int rows = (_tileCount / _cols).ceil();
    final List<Color> out = [];

    for (int i = 0; i < _tileCount; i++) {
      final int row = i ~/ _cols;
      final double t = rows <= 1 ? 0.0 : row / (rows - 1);
      // top lighter, bottom darker
      final double v = vMax - (vMax - vMin) * t;
      out.add(HSVColor.fromAHSV(1.0, 0.0, 0.0, v).toColor());
    }

    return out;
  }

  void _handleTileTap(int index, Color color) {
    if (widget.returnPickedColor) {
      Navigator.of(context, rootNavigator: false).pop(color);
      return;
    }

    Navigator.of(context, rootNavigator: false).push(
      MaterialPageRoute(
        builder:
            (_) => CreateScreen(
              selectedColor: color,
              presetRecipientId: widget.presetRecipientId,
              presetRecipientName: widget.presetRecipientName,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget grid = GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: 800,
      itemCount: _colors.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _cols,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
        childAspectRatio: 1.0,
      ),
      itemBuilder: (context, i) {
        final c = _colors[i];
        return InkWell(
          onTap: () => _handleTileTap(i, c),
          child: Container(color: c),
        );
      },
    );

    final Widget gridWithChevron = ScrollHintOverlay(
      visual: ScrollHintVisual.nakedSingle,
      brandColor: Colors.black,
      chipSize: 88,
      initialDelay: Duration.zero,
      maxShowDuration: const Duration(days: 365),
      showBottomGradient: false,
      bottomPadding: MediaQuery.of(context).padding.bottom + 24,
      alwaysShow: true,
      child: grid,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            gridWithChevron,
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: const Icon(Icons.chevron_left, size: 28),
                  color: Colors.black,
                  splashRadius: 22,
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Back',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
