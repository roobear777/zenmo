import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/swatch_repository.dart';
import '../services/cart_repository.dart'
    show CartRepository, CartPreset, CartMode;
import '../services/keep_repository.dart';
import '../services/firestore/keep_repository_firestore.dart';
import 'cart_screen.dart';

// bottom nav targets
import 'wallet_screen.dart';
import 'create_screen.dart';
import 'daily_hues/daily_scroll_screen.dart';

// Fingerprint preview widget
import 'fingerprint_grid.dart';

class KeepsakeOptionsScreen extends StatefulWidget {
  final Color selectedColor;
  final String title;
  final String? swatchId;

  // used for KEEP toggle persistence (kept for compatibility, but not required)
  final String? senderId;

  // Optional fingerprint payload (typically passed from AccountScreen)
  final List<int>? fingerprintAnswers; // partial or complete
  final int? fingerprintTotal; // e.g., 25
  final int? fingerprintShuffleSeed; // if completed/shuffled
  final bool? fingerprintCompleted; // true/false

  // override used by callers who know the user has a fingerprint
  final bool? hasFingerprint;

  const KeepsakeOptionsScreen({
    super.key,
    required this.selectedColor,
    required this.title,
    this.swatchId,
    this.senderId,
    this.fingerprintAnswers,
    this.fingerprintTotal,
    this.fingerprintShuffleSeed,
    this.fingerprintCompleted,
    this.hasFingerprint,
  });

  @override
  State<KeepsakeOptionsScreen> createState() => _KeepsakeOptionsScreenState();
}

class _KeepsakeOptionsScreenState extends State<KeepsakeOptionsScreen> {
  final _cart = CartRepository();
  final _repo = SwatchRepository();
  final KeepRepository _keepRepo = KeepRepositoryFirestore(
    firestore: FirebaseFirestore.instance,
  );

  bool? swatchKept; // KEEP toggle state

  // Keepsake quantities
  int qtyPostcard = 0;
  int qtyMug = 0;
  int qtyPaint = 0;

  // Asset thumbnails (must exist under assets/shop/ and be declared in pubspec.yaml)
  static const String _assetPostcard = 'assets/shop/postcard.jpg';
  static const String _assetMug = 'assets/shop/zenmug.jpg';
  static const String _assetPaint = 'assets/shop/jar-of-paint.jpg';

  // For scrolling to the fingerprint area from the hint
  final GlobalKey _fingerprintKey = GlobalKey();

  String get _colorHex =>
      '#${widget.selectedColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  String _fallbackSwatchId() =>
      ('${widget.title}|$_colorHex').hashCode.toRadixString(16);

  bool get _hasFingerprint {
    if (widget.hasFingerprint != null) return widget.hasFingerprint!;
    final a = widget.fingerprintAnswers;
    if (a != null && a.isNotEmpty) return true;
    return widget.fingerprintCompleted == true;
  }

  Map<String, dynamic> _buildFingerprintBlock() {
    final answers = widget.fingerprintAnswers ?? const <int>[];
    final hasAny = answers.isNotEmpty;

    final int total = widget.fingerprintTotal ?? 25;
    final int shuffleSeed = widget.fingerprintShuffleSeed ?? 0;
    final bool completed =
        widget.fingerprintCompleted ?? (hasAny && answers.length >= total);

    if (!hasAny &&
        widget.fingerprintTotal == null &&
        widget.fingerprintShuffleSeed == null &&
        widget.fingerprintCompleted == null) {
      return const {};
    }

    return {
      if (hasAny) 'answers': answers,
      'total': total,
      'shuffleSeed': shuffleSeed,
      'completed': completed,
    };
  }

  Map<String, dynamic> _swatchBase() {
    final map = <String, dynamic>{
      'id':
          (widget.swatchId == null || widget.swatchId!.isEmpty)
              ? _fallbackSwatchId()
              : widget.swatchId!,
      'title': widget.title,
      'colorHex': _colorHex,
    };
    final fp = _buildFingerprintBlock();
    if (fp.isNotEmpty) {
      map['fingerprint'] = fp;
    }
    return map;
  }

  @override
  void initState() {
    super.initState();
    _loadKept();
  }

  /// Read kept state from the `keeps` collection for the current user and root (swatchId).
  Future<void> _loadKept() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final root = widget.swatchId; // treat swatchId as the root/answer id
    if (uid == null || root == null || root.isEmpty) {
      setState(() => swatchKept = false);
      return;
    }
    try {
      final kept = await _keepRepo.isKept(root);
      if (!mounted) return;
      setState(() => swatchKept = kept);
    } catch (_) {
      if (!mounted) return;
      setState(() => swatchKept = false);
    }
  }

  Future<void> _addSelectedKeepsakesAndGo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please sign in first')));
      return;
    }

    try {
      final baseSwatch = _swatchBase();

      if (qtyPostcard > 0) {
        await _cart.addPreset(
          preset: CartPreset.postcard,
          swatch: baseSwatch,
          qty: qtyPostcard,
          imageUrl: _assetPostcard,
        );
      }
      if (qtyMug > 0) {
        await _cart.addPreset(
          preset: CartPreset.mug,
          swatch: baseSwatch,
          qty: qtyMug,
          imageUrl: _assetMug,
        );
      }
      if (qtyPaint > 0) {
        await _cart.addPreset(
          preset: CartPreset.paint,
          swatch: baseSwatch,
          qty: qtyPaint,
          imageUrl: _assetPaint,
        );
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const CartScreen(mode: CartMode.keepsakesOnly),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cart error: $e')));
    }
  }

  /// Center-out spiral order (same as AccountScreen)
  List<int> _centerOutSpiral({required int rows, required int cols}) {
    final total = rows * cols;
    final List<int> order = [];
    int r = rows ~/ 2, c = cols ~/ 2;
    order.add(r * cols + c);
    int step = 1;
    final dirs = <List<int>>[
      [1, 0],
      [0, 1],
      [-1, 0],
      [0, -1],
    ];
    int d = 0;
    while (order.length < total) {
      for (int rep = 0; rep < 2; rep++) {
        final dx = dirs[d % 4][0];
        final dy = dirs[d % 4][1];
        for (int s = 0; s < step; s++) {
          c += dx;
          r += dy;
          if (r >= 0 && r < rows && c >= 0 && c < cols) {
            order.add(r * cols + c);
            if (order.length == total) return order;
          }
        }
        d++;
      }
      step++;
    }
    return order;
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    // Show toggle whenever we have a swatchId (allow self-keeps too so Wallet stays usable).
    final bool canToggleKeep = widget.swatchId != null;

    final answers = widget.fingerprintAnswers ?? const <int>[];
    final bool hasAnswers = answers.isNotEmpty; // for preview only

    return Scaffold(
      appBar: AppBar(
        title: const Text('Keep this color in your life.'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Divider(height: 1, thickness: 1, color: Colors.black12),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          // Fingerprint preview if answers exist, else color band
          hasAnswers
              ? Container(
                key: _fingerprintKey,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: FingerprintGrid(
                          answers: answers,
                          total: widget.fingerprintTotal ?? 25,
                          borderColor: Colors.transparent,
                          borderWidth: 0,
                          cornerRadius: 8,
                          gap: 0,
                          forceCols: 5,
                          placementOrder: _centerOutSpiral(rows: 5, cols: 5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your Color Fingerprint',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              )
              : Container(
                key: _fingerprintKey,
                height: 230,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Expanded(child: Container(color: widget.selectedColor)),
                    Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Center(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

          const SizedBox(height: 16),

          // KEEP toggle row -> backed by `keeps` collection
          if (canToggleKeep)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.bookmark_border,
                    size: 18,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Keep this Zenmo in your wallet',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.9,
                    child: CupertinoSwitch(
                      value: (swatchKept ?? false),
                      onChanged: (v) async {
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        final root = widget.swatchId; // root/answer id
                        if (uid == null || root == null || root.isEmpty) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please sign in first'),
                            ),
                          );
                          return;
                        }
                        try {
                          final kept = await _keepRepo.toggleKeep(root);
                          if (!mounted) return;
                          setState(() => swatchKept = kept);
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Keep toggle failed: $e')),
                          );
                        }
                      },
                      activeTrackColor: Colors.black87,
                      inactiveTrackColor: const Color(0xFFCED0D6),
                    ),
                  ),
                ],
              ),
            ),

          // Items with large square photos (tap image to preview)
          _itemRow(
            label: 'send a postcard (\$2)',
            featureText:
                'Postcard will feature your custom color, title, creator name, and time stamp.',
            qty: qtyPostcard,
            onDec:
                () => setState(
                  () => qtyPostcard = qtyPostcard > 0 ? qtyPostcard - 1 : 0,
                ),
            onInc: () => setState(() => qtyPostcard++),
            imageAssetPath: _assetPostcard,
            onImageTap:
                () => _showImagePreview(
                  assetPath: _assetPostcard,
                  title: 'Postcard',
                ),
          ),
          _itemRow(
            label: 'Zenmo mug (\$19)',
            featureText:
                'Mug will feature your custom color, title, creator name, and time stamp.',
            qty: qtyMug,
            onDec: () => setState(() => qtyMug = qtyMug > 0 ? qtyMug - 1 : 0),
            onInc: () => setState(() => qtyMug++),
            imageAssetPath: _assetMug,
            onImageTap:
                () =>
                    _showImagePreview(assetPath: _assetMug, title: 'Zenmo mug'),
          ),
          _itemRow(
            label: 'jar of paint (\$29)',
            featureText:
                'Jar of paint will feature your custom color, title, creator name, and time stamp.',
            qty: qtyPaint,
            onDec:
                () =>
                    setState(() => qtyPaint = qtyPaint > 0 ? qtyPaint - 1 : 0),
            onInc: () => setState(() => qtyPaint++),
            imageAssetPath: _assetPaint,
            onImageTap:
                () => _showImagePreview(
                  assetPath: _assetPaint,
                  title: 'Jar of paint',
                ),
          ),

          const SizedBox(height: 16),

          // Footer buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Continue Shopping'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _addSelectedKeepsakesAndGo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5F6572),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Go to Cart'),
                ),
              ),
            ],
          ),
        ],
      ),

      // bottom nav
      bottomNavigationBar: Container(
        height: 60,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.black12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const WalletScreen()),
                );
              },
              child: const _NavIcon(label: 'Wallet', icon: Icons.wallet),
            ),
            GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateScreen(selectedColor: Colors.white),
                  ),
                );
              },
              child: const _NavIcon(label: 'Send Vibes', icon: Icons.brush),
            ),
            GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const DailyScrollScreen()),
                );
              },
              child: const _NavIcon(
                label: 'Daily Hues',
                icon: Icons.grid_view_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Image preview modal
  Future<void> _showImagePreview({
    required String assetPath,
    required String title,
  }) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: InteractiveViewer(
                      minScale: 0.9,
                      maxScale: 4.0,
                      child: Image.asset(
                        assetPath,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image, size: 40),
                            ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Vertical product card with large square photo
  Widget _itemRow({
    required String label,
    String? featureText, // NEW: optional descriptive blurb
    required int qty,
    required VoidCallback onDec,
    required VoidCallback onInc,
    String? imageAssetPath,
    VoidCallback? onImageTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onImageTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  color: const Color(0xFFEFF1F4),
                  child:
                      (imageAssetPath != null && imageAssetPath.isNotEmpty)
                          ? Image.asset(
                            imageAssetPath,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, __, ___) => const Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.black38,
                                  ),
                                ),
                          )
                          : const Center(
                            child: Icon(Icons.image, color: Colors.black38),
                          ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (featureText != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                featureText,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  height: 1.25,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _qtyBtn(icon: Icons.remove, onTap: qty > 0 ? onDec : null),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('$qty'),
              ),
              _qtyBtn(icon: Icons.add, onTap: onInc),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn({required IconData icon, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black26),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? Colors.black26 : Colors.black87,
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final String label;
  final IconData icon;
  const _NavIcon({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 24),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
