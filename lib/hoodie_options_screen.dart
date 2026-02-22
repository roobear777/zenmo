import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/cart_repository.dart' show CartRepository, CartMode;
import 'cart_screen.dart';
import 'fingerprint_grid.dart';
import 'pricing/hoodie_prices.dart'; // HoodieFit/HoodieSize helpers

class HoodieOptionsScreen extends StatefulWidget {
  final Color selectedColor;
  final String title;

  // Optional fingerprint payload (from AccountScreen)
  final List<int>? fingerprintAnswers;
  final int? fingerprintTotal;
  final int? fingerprintShuffleSeed;
  final bool? fingerprintCompleted;

  const HoodieOptionsScreen({
    super.key,
    required this.selectedColor,
    required this.title,
    this.fingerprintAnswers,
    this.fingerprintTotal,
    this.fingerprintShuffleSeed,
    this.fingerprintCompleted,
  });

  @override
  State<HoodieOptionsScreen> createState() => _HoodieOptionsScreenState();
}

class _HoodieOptionsScreenState extends State<HoodieOptionsScreen> {
  final _cart = CartRepository();

  HoodieFit _fit = HoodieFit.relaxed;
  HoodieSize _size = HoodieSize.m;

  static const String _assetHoodie = 'assets/shop/fingerprint_hoodie.png';

  String get _colorHex =>
      '#${widget.selectedColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  Map<String, dynamic> _buildFingerprintBlock() {
    final answers = widget.fingerprintAnswers ?? const <int>[];
    final hasAny = answers.isNotEmpty;
    final total = widget.fingerprintTotal ?? 25;
    final shuffleSeed = widget.fingerprintShuffleSeed ?? 0;
    final completed =
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
      'id': ('${widget.title}|$_colorHex').hashCode.toRadixString(16),
      'title': widget.title,
      'colorHex': _colorHex,
    };
    final fp = _buildFingerprintBlock();
    if (fp.isNotEmpty) map['fingerprint'] = fp;
    return map;
  }

  Future<void> _addHoodieAndGo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please sign in first')));
      return;
    }

    try {
      final sw = _swatchBase();
      final lookup = hoodieLookupKey(_fit, _size);
      final priceId = getHoodiePriceId(fit: _fit, size: _size);

      sw['hoodie'] = {
        'lookupKey': lookup,
        'priceId': priceId,
        'amountCents': 6900,
        'currency': 'usd',
        'fit': _fit.key,
        'size': _size.key,
      };

      await _cart.addOrIncrement(
        productId: 'hoodie',
        productName: 'Fingerprint hoodie',
        unitPriceCents: 6900,
        swatch: sw,
        requiresAddress: true,
        shippingIncluded: false,
        imageUrl: _assetHoodie,
        qty: 1,
      );

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const CartScreen(mode: CartMode.hoodieOnly),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cart error: $e')));
    }
  }

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
    final answers = widget.fingerprintAnswers ?? const <int>[];
    final hasAnswers = answers.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fingerprint hoodie'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Divider(height: 1, thickness: 1, color: Colors.black12),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          hasAnswers
              ? Container(
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
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      color: const Color(0xFFEFF1F4),
                      child: Image.asset(
                        _assetHoodie,
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
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Fingerprint hoodie',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _Dropdown<HoodieFit>(
                        label: 'Fit',
                        value: _fit,
                        items: HoodieFit.values,
                        toText: (f) => f.label,
                        onChanged: (v) => setState(() => _fit = v ?? _fit),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Dropdown<HoodieSize>(
                        label: 'Size',
                        value: _size,
                        items: HoodieSize.values,
                        toText: (s) => s.label,
                        onChanged: (v) => setState(() => _size = v ?? _size),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _addHoodieAndGo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3A006A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Buy hoodie'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) toText;
  final ValueChanged<T?> onChanged;

  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.toText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: '',
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isDense: true,
          value: value,
          onChanged: onChanged,
          items:
              items
                  .map(
                    (e) =>
                        DropdownMenuItem<T>(value: e, child: Text(toText(e))),
                  )
                  .toList(),
        ),
      ),
    );
  }
}
