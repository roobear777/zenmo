// lib/cart_screen.dart
import 'dart:async';
import 'dart:convert'; // for json/base64
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html; // for history.replaceState (web)
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // FirebaseFirestore, Timestamp
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http; // keep (not used for gift anymore)
import 'package:cloud_functions/cloud_functions.dart'; // NEW: applyGiftCode callable

import '../services/cart_repository.dart'
    show CartRepository, CartItem, CartMode;

import 'wallet_screen.dart';
import 'account_screen.dart';
import 'menu.dart';
import 'package:color_wallet/utils/money.dart';
import 'daily_hues/daily_hues_screen.dart';
import 'color_picker_screen.dart';

// Cloud Function URL for Stripe Checkout redirect (hosted)
const String kCheckoutRedirectUrl =
    'https://us-central1-zenmobeta.cloudfunctions.net/checkoutRedirect';

// (kept for future: read-only endpoint not used in this file anymore)
// const String kValidateGiftUrl =
//     'https://us-central1-zenmobeta.cloudfunctions.net/validateGiftCode';

// Fallback thumbnails by productId (used when item.imageUrl is null/empty)
const Map<String, String> kProductThumbs = {
  'postcard': 'assets/shop/postcard.jpg',
  'mug': 'assets/shop/zenmug.jpg',
  'paint': 'assets/shop/jar-of-paint.jpg',
  'hoodie': 'assets/shop/fingerprint_hoodie.png', // hoodie default
};

/// Client-side preview helper: same logic as server (country-only, max-rule).
/// Returns USD cents.
int computeShippingCentsForPreview(
  String? destCountry,
  List<String> productIds,
) {
  final isDomestic = (destCountry ?? '').toUpperCase() == 'US';

  int rateFor(String pid) {
    final p = pid.toLowerCase();
    if (p.startsWith('hoodie')) return isDomestic ? 1000 : 2100;
    if (p.contains('mug')) return isDomestic ? 800 : 1700;
    if (p.contains('paint')) return isDomestic ? 700 : 1500;
    return isDomestic ? 400 : 1100; // default postcard
  }

  if (productIds.isEmpty) return isDomestic ? 400 : 1100;

  var maxCents = 0;
  for (final pid in productIds) {
    final cents = rateFor(pid);
    if (cents > maxCents) maxCents = cents;
  }
  return maxCents;
}

// NEW: local status enum for banner + behavior
enum GiftCodeStatus {
  none,
  issued,
  issuedLegacyValue,
  redeemed,
  notFound,
  invalid,
  error,
}

// NEW: minimal model captured from callable
class AppliedGift {
  final String code;
  final GiftCodeStatus status;
  final String? itemType; // hoodie | mug | paint | postcard (when issued)
  final int? valueCents; // legacy amount-off
  AppliedGift({
    required this.code,
    required this.status,
    this.itemType,
    this.valueCents,
  });
}

class CartScreen extends StatefulWidget {
  final CartMode mode; // hoodieOnly / keepsakesOnly
  const CartScreen({super.key, this.mode = CartMode.keepsakesOnly});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _repo = CartRepository();
  final _giftCtrl = TextEditingController();
  final _secondHoodieEmailCtrl = TextEditingController();
  bool _applying = false;

  /// one-shot guards
  bool _checkoutDialogShown = false;

  String? _destCountryToggle;

  // NEW: gift validation UI state
  AppliedGift? _appliedGift; // null if none
  String _giftStatusText = ''; // banner text

  @override
  void initState() {
    super.initState();
    _destCountryToggle = 'US';
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowCheckoutResultFromUrl(),
    );
  }

  // --- BOGO ($69 hoodies => $34.50 off per pair) preview helpers ---
  int _hoodieQtyInCart(Iterable<CartItem> items) {
    int q = 0;
    for (final it in items) {
      final pid = it.productId.toLowerCase();
      if (pid == 'hoodie' || pid.startsWith('hoodie')) {
        q += it.qty;
      }
    }
    return q;
  }

  int _countByType(Iterable<CartItem> items, String itemType) {
    final t = itemType.toLowerCase();
    int q = 0;
    for (final it in items) {
      final pid = it.productId.trim().toLowerCase();
      if (t == 'hoodie' && pid == 'hoodie') q += it.qty;
      if (t == 'mug' && pid == 'mug') q += it.qty;
      if (t == 'paint' && pid == 'paint') q += it.qty;
      if (t == 'postcard' && pid == 'postcard') q += it.qty;
    }
    return q;
  }

  int _bogoDiscountCents(Iterable<CartItem> items) {
    final pairs = _hoodieQtyInCart(items) ~/ 2;
    return pairs * 3450; // $34.50 per pair (unit price = $69)
  }

  @override
  void dispose() {
    _giftCtrl.dispose();
    _secondHoodieEmailCtrl.dispose();
    super.dispose();
  }

  // ===== helpers for hoodie fit normalization =====
  String _normalizeHoodieFit(String? v) {
    final s = (v ?? '').trim().toLowerCase();
    if (s == 'tailored') return 'slim'; // legacy -> slim
    if (s == 'slim') return 'slim';
    return 'relaxed';
  }

  String? _cap(String? s) =>
      (s == null || s.isEmpty)
          ? null
          : '${s[0].toUpperCase()}${s.substring(1)}';

  // ===== determine if an order is paid/complete =====
  bool _orderIsPaid(Map<String, dynamic> order) {
    final ps = (order['payment_status'] as String? ?? '').toLowerCase();
    final st = (order['status'] as String? ?? '').toLowerCase();
    final paidFlag = order['paid'] == true;
    return paidFlag || ps == 'paid' || st == 'complete' || st == 'succeeded';
  }

  // ===== clear cart via repository + localStorage safety net =====
  Future<void> _clearCartEverywhere() async {
    try {
      final items = await _repo.getItemsOnce();
      for (final it in items) {
        await _repo.remove(it.id);
      }
    } catch (_) {
      // ignore repo errors and still try local storage
    }

    if (kIsWeb) {
      try {
        final ls = html.window.localStorage;
        ls.remove('cart');
        ls.remove('cart_items');
        ls.remove('zenmo_cart');
        ls['cart_lastCleared'] = DateTime.now().toIso8601String();
        html.window.dispatchEvent(html.CustomEvent('zenmo:cartCleared'));
      } catch (_) {
        // ignore
      }
    }
  }

  // ===== URL parsing/helpers (hash-based router) =====
  Map<String, String> _queryParamsFromHash() {
    // For URLs like https://.../#/cart?status=success&session_id=xxx
    final frag = Uri.base.fragment; // "/cart?status=success&session_id=..."
    final idx = frag.indexOf('?');
    if (idx == -1) return const {};
    final q = frag.substring(idx + 1);
    return Uri.splitQueryString(q);
  }

  void _stripHashQueryKeepingRoute() {
    if (!kIsWeb) return;
    final frag = Uri.base.fragment;
    final idx = frag.indexOf('?');
    final cleanFrag = idx == -1 ? frag : frag.substring(0, idx);
    final newUrl = '#$cleanFrag';
    html.window.history.replaceState(null, '', newUrl);
  }

  Future<void> _maybeShowCheckoutResultFromUrl() async {
    if (_checkoutDialogShown) return;
    final qp = _queryParamsFromHash();
    final status = qp['status'];
    if (status != 'success' && status != 'cancel') {
      return;
    }
    _checkoutDialogShown = true; // guard immediately
    _stripHashQueryKeepingRoute(); // don’t re-trigger on refresh

    if (!mounted) return;

    if (status == 'cancel') {
      await _showCancelDialog();
      return;
    }

    // success — try to fetch order summary if we have session_id
    final sessionId = qp['session_id'];
    Map<String, dynamic>? orderDoc;
    if (sessionId != null && sessionId.isNotEmpty) {
      try {
        final snap =
            await FirebaseFirestore.instance
                .collection('orders')
                .doc(sessionId)
                .get();
        if (snap.exists) {
          orderDoc = snap.data();
        }
      } catch (_) {
        // ignore; we'll still show a basic success dialog
      }
    }

    // If paid/complete, clear the cart before showing the dialog
    if (orderDoc != null && _orderIsPaid(orderDoc)) {
      await _clearCartEverywhere();
    }

    await _showSuccessDialog(orderDoc: orderDoc);
  }

  // ===== Success / Cancel dialogs =====
  Future<void> _showCancelDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Purchase canceled'),
          content: const Text(
            'No charge was made. You can try checkout again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _labeledRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 14),
          children: [
            const TextSpan(text: ''),
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  // Build “email-like” content card for dialog
  Widget _successDialogBody({
    required String title,
    String? fromName,
    String? hex,
    String? zenmoedAt,
    String? itemLine,
    String? amount,
    String? sessionId,
    Map<String, dynamic>? shipping,
  }) {
    final swatchColor = _parseHexColor(hex);
    final ship = shipping?['address'] as Map<String, dynamic>?;
    final shipName = (shipping?['name'] ?? '') as String;

    String shipBlock = '';
    if (ship != null) {
      final line1 = (ship['line1'] ?? '') as String;
      final line2 = (ship['line2'] ?? '') as String;
      final city = (ship['city'] ?? '') as String;
      final postal = (ship['postal_code'] ?? '') as String;
      final state = (ship['state'] ?? '') as String;
      final country = (ship['country'] ?? '') as String;
      final parts =
          <String>[
            if (shipName.isNotEmpty) shipName,
            if (line1.isNotEmpty) line1,
            if (line2.isNotEmpty) line2,
            [city, postal].where((s) => s.isNotEmpty).join(' ').trim(),
            [state, country].where((s) => s.isNotEmpty).join(', '),
          ].where((s) => s.isNotEmpty).toList();
      shipBlock = parts.join('\n');
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with big swatch and right column
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 144,
                height: 144,
                decoration: BoxDecoration(
                  color: swatchColor ?? Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (fromName != null && fromName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _labeledRow('From', fromName),
                        ),
                      if (zenmoedAt != null && zenmoedAt.isNotEmpty)
                        _labeledRow('Zenmoed at', zenmoedAt),
                      if (hex != null && hex.isNotEmpty)
                        _labeledRow('Hex', hex.toUpperCase()),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Items:', style: TextStyle(fontWeight: FontWeight.w700)),
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 6, bottom: 10),
            child: Text(itemLine ?? '—', style: const TextStyle(fontSize: 14)),
          ),
          const Text('Ship To:', style: TextStyle(fontWeight: FontWeight.w700)),
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 6, bottom: 10),
            child: Text(shipBlock.isEmpty ? '(no address)' : shipBlock),
          ),
          if (amount != null)
            RichText(
              text: const TextSpan(
                style: TextStyle(color: Colors.black87, fontSize: 14),
                children: [
                  TextSpan(
                    text: 'Amount: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          if (amount != null) const SizedBox(height: 2),
          if (amount != null)
            Text(
              amount,
              style: const TextStyle(color: Colors.black87, fontSize: 14),
            ),
          if (sessionId != null) ...[
            const SizedBox(height: 6),
            Text(
              'Session: $sessionId',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.black87,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showSuccessDialog({Map<String, dynamic>? orderDoc}) async {
    if (!mounted) return;

    final cartMeta =
        (orderDoc?['cartMeta'] ?? const {}) as Map<String, dynamic>;
    final items =
        (cartMeta['items'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final first = items.isNotEmpty ? items.first : const <String, dynamic>{};

    final title = (first['title'] ?? first['productId'] ?? 'Zenmo').toString();
    final hex = (first['hex'] ?? '').toString();
    final fromName =
        (cartMeta['fromName'] ??
                first['fromName'] ??
                cartMeta['creatorName'] ??
                cartMeta['senderName'] ??
                cartMeta['createdBy'])
            ?.toString();
    String? zenmoedAt = (first['displayedAt'] as String?);
    zenmoedAt ??= _formatZenmoedForDisplay(first);

    String? amount;
    if (orderDoc != null) {
      final cents = (orderDoc['amount_total'] ?? 0) as int;
      final cur = ((orderDoc['currency'] ?? 'usd') as String).toUpperCase();
      amount = '${(cents / 100).toStringAsFixed(2)} $cur';
    }

    String? itemLine;
    try {
      final qty = (first['qty'] ?? 1).toString();
      final product = (first['productId'] ?? 'item').toString();

      final fitRaw = ((first['hoodieFit'] ?? first['fit']) ?? '').toString();
      final sizeRaw = ((first['hoodieSize'] ?? first['size']) ?? '').toString();
      final fitNorm = _normalizeHoodieFit(fitRaw);

      final variant = [
        _cap(fitNorm),
        if (sizeRaw.isNotEmpty) sizeRaw.toUpperCase(),
      ].where((e) => e != null && (e).isNotEmpty).join(', ');

      final prodWithVariant =
          (product.toLowerCase() == 'hoodie' && variant.isNotEmpty)
              ? 'hoodie ($variant)'
              : product;

      itemLine = '$prodWithVariant x$qty';

      if (product.toLowerCase() == 'hoodie') {
        final qn = int.tryParse(qty) ?? 0;
        if (qn >= 2) {
          itemLine = '$itemLine\nSecond hoodie half price';
        }
      }
    } catch (_) {}

    Map<String, dynamic>? shipping =
        orderDoc?['shipping'] as Map<String, dynamic>? ??
        orderDoc?['shipping_details'] as Map<String, dynamic>? ??
        orderDoc?['customer_details'] as Map<String, dynamic>?;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Purchase successful!'),
          content: _successDialogBody(
            title: title,
            fromName: fromName,
            hex: hex,
            zenmoedAt: zenmoedAt,
            itemLine: itemLine,
            amount: amount,
            sessionId: orderDoc?['id'] as String?,
            shipping: shipping,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context, rootNavigator: false).pushReplacement(
                  MaterialPageRoute(builder: (_) => const DailyHuesScreen()),
                );
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // ===== Existing helpers =====
  String? _isoFrom(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is Timestamp) return v.toDate().toUtc().toIso8601String();
    return null;
  }

  String? _pickZenmoedIso(Map<String, dynamic> sw) {
    return _isoFrom(sw['zenmoedAt'] ?? sw['sentAt'] ?? sw['createdAt']);
  }

  String _formatZenmoedForDisplay(Map<String, dynamic> sw) {
    DateTime? dt;
    final raw = sw['zenmoedAt'] ?? sw['sentAt'] ?? sw['createdAt'];
    if (raw is DateTime) {
      dt = raw;
    } else if (raw is Timestamp) {
      dt = raw.toDate();
    } else if (raw is String) {
      try {
        dt = DateTime.parse(raw);
      } catch (_) {}
    }
    dt ??= DateTime.now().toUtc();
    return '${DateFormat('MMMM d, y').format(dt)} ${DateFormat.Hms().format(dt)}';
  }

  Map<String, dynamic> _toSwatchMap(Object? v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val));
    }
    return const <String, dynamic>{};
  }

  Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 3) {
      h = h.split('').map((c) => '$c$c').join();
    }
    if (h.length != 6) return null;
    final n = int.tryParse(h, radix: 16);
    if (n == null) return null;
    return Color(0xFF000000 | n);
  }

  bool _hasHoodieVariant(List<CartItem> items) {
    for (final it in items) {
      if (it.productId.trim().toLowerCase() == 'hoodie' && it.qty > 0) {
        final sw = _toSwatchMap(it.swatch);
        final hoodie =
            (sw['hoodie'] is Map)
                ? Map<String, dynamic>.from(sw['hoodie'])
                : null;
        final priceId = hoodie != null ? (hoodie['priceId'] as String?) : null;
        if (priceId != null && priceId.isNotEmpty) return true;
      }
    }
    return false;
  }

  String? _formatHoodieVariant(Map<String, dynamic>? hoodie) {
    if (hoodie == null) return null;
    final rawFit = (hoodie['fit'] as String?)?.trim();
    final rawSize = (hoodie['size'] as String?)?.trim();
    if ((rawFit == null || rawFit.isEmpty) &&
        (rawSize == null || rawSize.isEmpty)) {
      return null;
    }
    final size = (rawSize ?? '').toUpperCase();
    final fitNorm = _normalizeHoodieFit(rawFit);
    final fit =
        fitNorm.isEmpty
            ? ''
            : '${fitNorm[0].toUpperCase()}${fitNorm.substring(1)}';
    final parts = <String>[if (size.isNotEmpty) size, if (fit.isNotEmpty) fit];
    return parts.join(' · ');
  }

  // Stripe Checkout redirect (hosted) + cartMeta
  Future<void> _startCheckout() async {
    try {
      final items = await _repo.getItemsOnce();
      if (items.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Your cart is empty')));
        return;
      }

      // === Entitlement guard: exactly 1 of entitled item in cart ===
      bool entitlementOk = true;
      if (_appliedGift != null &&
          _appliedGift!.status == GiftCodeStatus.issued) {
        final t = (_appliedGift!.itemType ?? '').toLowerCase();
        if (t.isNotEmpty) {
          final count = _countByType(items, t);
          entitlementOk = (count == 1);
        }
      }
      if (!entitlementOk) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Adjust your cart to match the gift: exactly one entitled item.',
            ),
          ),
        );
        return;
      }

      final parts = <String>[];
      for (final it in items) {
        final pid = it.productId.trim().toLowerCase();
        if (it.qty > 0 &&
            (pid == 'mug' || pid == 'postcard' || pid == 'paint')) {
          parts.add('$pid:${it.qty}');
        }
      }

      final hasHoodie = _hasHoodieVariant(items);
      if (parts.isEmpty && !hasHoodie) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid items to purchase')),
        );
        return;
      }

      // ---- Destination handling (toggle REQUIRED; no dialog) ----
      if (_destCountryToggle == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select US or Worldwide to continue')),
          );
        }
        return;
      }
      final String destCountry = _destCountryToggle == 'US' ? 'US' : 'GB';
      final String destPostal = '';

      // --- Read gift code from cart/meta (Firestore) ---
      final metaSnap = await _repo.getMetaOnce();
      final giftCode =
          ((metaSnap['giftCode'] as String?) ?? '').trim().toUpperCase();

      // --- Build cartMeta payload ---
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';
      final fromName =
          (user?.displayName != null && user!.displayName!.trim().isNotEmpty)
              ? user.displayName!.trim()
              : (user?.email != null ? user!.email!.split('@').first : '');

      // NEW: second-hoodie recipient email (for BOGO gifting)
      final int hoodiePairs = _hoodieQtyInCart(items) ~/ 2;
      final String secondHoodieEmail = _secondHoodieEmailCtrl.text.trim();

      final metaObj = {
        'userUid': uid,
        'fromName': fromName,
        if (giftCode.isNotEmpty) 'giftCode': giftCode,
        if (hoodiePairs > 0 && secondHoodieEmail.isNotEmpty)
          'secondHoodieGoesTo': secondHoodieEmail,
        'items':
            items.map((it) {
              final sw = _toSwatchMap(it.swatch);
              final hoodie =
                  (sw['hoodie'] is Map)
                      ? Map<String, dynamic>.from(sw['hoodie'])
                      : null;

              final String? priceId =
                  (hoodie != null &&
                          hoodie['priceId'] is String &&
                          (hoodie['priceId'] as String).isNotEmpty)
                      ? (hoodie['priceId'] as String)
                      : null;

              final String fitRaw =
                  ((hoodie?['hoodieFit'] ?? hoodie?['fit']) ?? '').toString();
              final String sizeRaw =
                  ((hoodie?['hoodieSize'] ?? hoodie?['size']) ?? '').toString();
              final String fitNorm = _normalizeHoodieFit(fitRaw);

              return {
                'productId': it.productId,
                'qty': it.qty,
                'title': (sw['title'] as String?) ?? '',
                'hex': (sw['colorHex'] as String?) ?? '',
                'createdAt':
                    _pickZenmoedIso(sw) ??
                    DateTime.now().toUtc().toIso8601String(),
                'displayedAt': _formatZenmoedForDisplay(sw),
                'fromName': fromName,
                if (priceId != null) 'priceId': priceId,
                if (fitNorm.isNotEmpty) 'hoodieFit': fitNorm,
                if (sizeRaw.isNotEmpty) 'hoodieSize': sizeRaw.toLowerCase(),
                if (sw['fingerprint'] != null)
                  'fingerprintSummary': {
                    'answersCount':
                        ((sw['fingerprint']['answers'] ?? []) as List).length,
                    'total': sw['fingerprint']['total'] ?? 0,
                    'shuffleSeed': sw['fingerprint']['shuffleSeed'] ?? 0,
                  },
              };
            }).toList(),
      };

      // === Trim heavy keys before encoding (kept as your working logic) ===
      for (final _itm in (metaObj['items'] as List)) {
        final m = (_itm as Map);
        m.remove('createdAt'); // keep displayedAt only
      }

      String encodeMeta(Map<String, dynamic> obj) =>
          base64Encode(utf8.encode(jsonEncode(obj)));
      String cartMetaB64 = encodeMeta(metaObj);

      if (cartMetaB64.length > 480) {
        final tiny = {
          'userUid': uid,
          'fromName': metaObj['fromName'] ?? '',
          if (giftCode.isNotEmpty) 'giftCode': giftCode,
          if (hoodiePairs > 0 && secondHoodieEmail.isNotEmpty)
            'secondHoodieGoesTo': secondHoodieEmail,
          'items':
              (metaObj['items'] as List).map((raw) {
                final m = Map<String, dynamic>.from(raw as Map);
                final productId = (m['productId'] ?? '').toString();
                final qty = m['qty'] ?? 0;
                final title = (m['title'] ?? '').toString();
                final hex = (m['hex'] ?? '').toString();
                final displayedAt = (m['displayedAt'] ?? '').toString();
                final priceId = (m['priceId'] ?? '').toString();
                final hoodieFit = (m['hoodieFit'] ?? '').toString();
                final hoodieSize = (m['hoodieSize'] ?? '').toString();
                final fingerprintSummary = m['fingerprintSummary'];

                final out = <String, dynamic>{
                  'productId': productId,
                  'qty': qty,
                  'title': title,
                  'hex': hex,
                  'displayedAt': displayedAt,
                };
                if (priceId.isNotEmpty) out['priceId'] = priceId;
                if (hoodieFit.isNotEmpty) out['hoodieFit'] = hoodieFit;
                if (hoodieSize.isNotEmpty) out['hoodieSize'] = hoodieSize;
                if (fingerprintSummary != null) {
                  out['fingerprintSummary'] = fingerprintSummary;
                }
                return out;
              }).toList(),
        };

        cartMetaB64 = encodeMeta(tiny);
        if (cartMetaB64.length > 480) {
          final compact = {
            'userUid': uid,
            'fromName': metaObj['fromName'] ?? '',
            if (giftCode.isNotEmpty) 'giftCode': giftCode,
            if (hoodiePairs > 0 && secondHoodieEmail.isNotEmpty)
              'secondHoodieGoesTo': secondHoodieEmail,
            'items':
                (tiny['items'] as List).map((raw) {
                  final m = Map<String, dynamic>.from(raw as Map);
                  return <String, dynamic>{
                    'productId': (m['productId'] ?? '').toString(),
                    'qty': m['qty'] ?? 0,
                    'hex': (m['hex'] ?? '').toString(),
                    if ((m['priceId'] ?? '').toString().isNotEmpty)
                      'priceId': (m['priceId'] ?? '').toString(),
                    if ((m['hoodieFit'] ?? '').toString().isNotEmpty)
                      'hoodieFit': (m['hoodieFit'] ?? '').toString(),
                    if ((m['hoodieSize'] ?? '').toString().isNotEmpty)
                      'hoodieSize': (m['hoodieSize'] ?? '').toString(),
                  };
                }).toList(),
          };
          cartMetaB64 = encodeMeta(compact);
        }
      }
      // === END trim

      final email = FirebaseAuth.instance.currentUser?.email ?? '';

      final qp = <String, String>{
        if (parts.isNotEmpty) 'items': parts.join(','),
        if (email.isNotEmpty) 'email': email,
        'cartMeta': cartMetaB64,
        'destCountry': destCountry,
        if (destPostal.isNotEmpty) 'destPostal': destPostal,
        if (giftCode.isNotEmpty) 'giftCode': giftCode,
      };
      final uri = Uri.parse(kCheckoutRedirectUrl).replace(queryParameters: qp);

      final ok = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );

      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open checkout')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Checkout error: $e')));
    }
  }

  // ===== Gift code handler (callable) =====
  Future<void> _applyGift() async {
    final raw = _giftCtrl.text.trim();
    if (raw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a gift code first')));
      return;
    }
    final code = raw.toUpperCase();

    setState(() {
      _applying = true;
      _appliedGift = null;
      _giftStatusText = '';
    });

    try {
      // Validate/apply via callable for structured status
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('applyGiftCode');
      final resp = await callable.call<Map<String, dynamic>>({'code': code});
      final data = resp.data;

      GiftCodeStatus status;
      String? itemType;
      int? valueCents;

      final st = (data['status'] ?? '').toString();
      switch (st) {
        case 'issued':
          status = GiftCodeStatus.issued;
          itemType = (data['itemType'] ?? '').toString();
          break;
        case 'issued_legacy_value':
          status = GiftCodeStatus.issuedLegacyValue;
          valueCents =
              (data['valueCents'] is num)
                  ? (data['valueCents'] as num).toInt()
                  : null;
          break;
        case 'redeemed':
          status = GiftCodeStatus.redeemed;
          break;
        case 'not_found':
          status = GiftCodeStatus.notFound;
          break;
        default:
          status = GiftCodeStatus.invalid;
      }

      // Persist to cart meta *only* when usable; clear otherwise
      if (status == GiftCodeStatus.issued ||
          status == GiftCodeStatus.issuedLegacyValue) {
        await _repo.applyGiftCode(code);
      } else {
        await _repo.applyGiftCode('');
      }

      String message;
      if (status == GiftCodeStatus.issued && (itemType ?? '').isNotEmpty) {
        message =
            'Gift code applied — covers 1 ${itemType!.toLowerCase()} (shipping not included).';
      } else if (status == GiftCodeStatus.issuedLegacyValue) {
        final dollarsOff =
            valueCents != null
                ? '\$${(valueCents / 100).toStringAsFixed(2)}'
                : 'credit';
        message = 'Gift code applied — $dollarsOff off your order.';
      } else if (status == GiftCodeStatus.redeemed) {
        message = 'This code has already been used.';
      } else if (status == GiftCodeStatus.notFound) {
        message = 'Gift code not found.';
      } else {
        message = 'Invalid gift code.';
      }

      if (!mounted) return;
      setState(() {
        _appliedGift = AppliedGift(
          code: code,
          status: status,
          itemType: itemType,
          valueCents: valueCents,
        );
        _giftStatusText = message;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _appliedGift = AppliedGift(code: code, status: GiftCodeStatus.error);
        _giftStatusText = 'Could not validate code';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not apply code: $e')));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _removeGift() async {
    // Clear both repo meta and local state (minimal dependency: reuse apply with empty)
    await _repo.applyGiftCode('');
    if (!mounted) return;
    setState(() {
      _appliedGift = null;
      _giftCtrl.clear();
      _giftStatusText = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Cart'),
        actions: const [
          ZenmoMenuButton(isOnWallet: false, isOnColorPicker: false),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Divider(height: 1.0, thickness: 1.0, color: Colors.black12),
        ),
      ),
      body: StreamBuilder<List<CartItem>>(
        stream: _repo.watchItems(),
        builder: (context, itemsSnap) {
          final items = itemsSnap.data ?? const <CartItem>[];

          return StreamBuilder<Map<String, dynamic>>(
            stream: _repo.watchMeta(),
            builder: (context, metaSnap) {
              final meta =
                  metaSnap.data ?? const {'giftCode': '', 'discountCents': 0};
              final totals = _repo.computeTotals(
                items,
                discountCents: (meta['discountCents'] as int?) ?? 0,
                taxRate: 0.0,
                shippingCents: 0,
              );

              final productIds =
                  items.map((it) => it.productId.toString()).toList();
              final destCountryCode =
                  _destCountryToggle == 'US'
                      ? 'US'
                      : _destCountryToggle == 'WW'
                      ? 'GB'
                      : null;
              final int? shipCentsPreview =
                  destCountryCode == null
                      ? null
                      : computeShippingCentsForPreview(
                        destCountryCode,
                        productIds,
                      );

              final int bogoDiscountCents = _bogoDiscountCents(items);
              final int hoodieQty = _hoodieQtyInCart(items);
              final bool hasBogo = bogoDiscountCents > 0;

              // === Entitlement gating & preview flags ===
              final bool isEntitlement =
                  _appliedGift?.status == GiftCodeStatus.issued &&
                  (_appliedGift?.itemType ?? '').isNotEmpty;
              final String entitledType =
                  (_appliedGift?.itemType ?? '').toLowerCase();

              int entitledCount = 0;
              if (isEntitlement) {
                entitledCount = _countByType(items, entitledType);
              }
              final bool entitlementSatisfied =
                  isEntitlement ? (entitledCount == 1) : false;

              // ====== A) PREVIEW ORDER TOTAL & LABEL ======
              int orderTotalPreviewCents;
              String orderTotalLabel;
              if (shipCentsPreview == null) {
                // no destination yet → show items subtotal (minus BOGO if any and no entitlement)
                orderTotalPreviewCents =
                    totals.taxableCents -
                    (!isEntitlement && hasBogo ? bogoDiscountCents : 0);
                orderTotalLabel = 'Order Total';
              } else if (isEntitlement && entitlementSatisfied) {
                // valid entitlement AND exactly one entitled item → shipping-only preview
                orderTotalPreviewCents = shipCentsPreview;
                orderTotalLabel = 'Approx. total (shipping only, before tax)';
              } else {
                // general case (no entitlement or not satisfied yet)
                orderTotalPreviewCents =
                    (totals.taxableCents -
                        (!isEntitlement && hasBogo ? bogoDiscountCents : 0)) +
                    shipCentsPreview;
                orderTotalLabel = 'Order Total (before tax)';
              }

              // REQUIRE a destination choice before checkout
              bool canCheckout = items.isNotEmpty && _destCountryToggle != null;
              // Block checkout when entitlement present and not satisfied
              if (isEntitlement && !entitlementSatisfied) {
                canCheckout = false;
              }

              return CustomScrollView(
                slivers: [
                  // --- Item list ---
                  SliverPadding(
                    padding: const EdgeInsets.all(10),
                    sliver: SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final it = items[idx];

                        final String? thumbUrl =
                            (it.imageUrl != null && it.imageUrl!.isNotEmpty)
                                ? it.imageUrl
                                : kProductThumbs[it.productId];

                        final sw = _toSwatchMap(it.swatch);
                        final hoodieMap =
                            (sw['hoodie'] is Map)
                                ? Map<String, dynamic>.from(sw['hoodie'])
                                : null;
                        final bool isHoodie =
                            it.productId.trim().toLowerCase() == 'hoodie';
                        final String? variantLabel =
                            isHoodie ? _formatHoodieVariant(hoodieMap) : null;

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.black12),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Thumbnail
                                  Container(
                                    width: 70,
                                    height: 70,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF1F4),
                                      border: Border.all(
                                        color:
                                            idx == 2
                                                ? const Color(0xFFB7B9FF)
                                                : Colors.black12,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      child:
                                          (thumbUrl != null &&
                                                  thumbUrl.isNotEmpty)
                                              ? (thumbUrl.startsWith('http')
                                                  ? Image.network(
                                                    thumbUrl,
                                                    fit: BoxFit.cover,
                                                  )
                                                  : Image.asset(
                                                    thumbUrl,
                                                    fit: BoxFit.cover,
                                                  ))
                                              : const Icon(
                                                Icons.image,
                                                color: Colors.black38,
                                              ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Title + subtitle
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    it.productName,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    (_toSwatchMap(
                                                              it.swatch,
                                                            )['title']
                                                            as String?) ??
                                                        '',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                  if (variantLabel != null &&
                                                      variantLabel.isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 2,
                                                          ),
                                                      child: Text(
                                                        variantLabel,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.black54,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            // Delete
                                            IconButton(
                                              tooltip: 'Remove',
                                              icon: const Icon(
                                                Icons.delete_outline,
                                              ),
                                              onPressed:
                                                  () => _repo.remove(it.id),
                                            ),
                                          ],
                                        ),

                                        if (it.requiresAddress) ...[
                                          const SizedBox(height: 8),
                                          const Text(
                                            "We’ll collect the delivery address at checkout.",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],

                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            _QtyButton(
                                              icon: Icons.remove,
                                              onTap:
                                                  it.qty > 1
                                                      ? () => _repo.updateQty(
                                                        it.id,
                                                        it.qty - 1,
                                                      )
                                                      : null,
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                  ),
                                              child: Text('${it.qty}'),
                                            ),
                                            _QtyButton(
                                              icon: Icons.add,
                                              onTap:
                                                  () => _repo.updateQty(
                                                    it.id,
                                                    it.qty + 1,
                                                  ),
                                            ),
                                            const SizedBox(width: 12),

                                            Expanded(
                                              child:
                                                  it.shippingIncluded
                                                      ? const Text(
                                                        'Incl. shipping.',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.black54,
                                                        ),
                                                      )
                                                      : const SizedBox.shrink(),
                                            ),

                                            Text(
                                              dollars(it.lineTotalCents),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  if (items.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'Your cart is empty',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    ),

                  // --- BOGO (second hoodie 50% off) ---
                  // Placed directly under the hoodie quantity controls section.
                  if (!isEntitlement && hoodieQty > 0)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F9FF),
                            border: Border.all(color: Color(0xFFDCE5FF)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'BOGO: Gift a hoodie (50% off)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                hoodieQty >= 2
                                    ? 'Gift it: We send an email with instructions on how to redeem (friend just pays shipping)'
                                    : 'Gift a hoodie to a friend and recieve 50% off the second hoodie.',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                              if (hoodieQty >= 2) ...[
                                const SizedBox(height: 10),
                                const Text(
                                  'Gift recipient email',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _secondHoodieEmailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(
                                    hintText: 'Email address',
                                    helperText:
                                        'We’ll email the gift code after checkout.',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                  // --- Gift code / Redeem code ---
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black12),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Gift code / Redeem code',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _giftCtrl,
                                    decoration: const InputDecoration(
                                      hintText: 'Enter code',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (_appliedGift == null ||
                                    _appliedGift!.status ==
                                        GiftCodeStatus.invalid ||
                                    _appliedGift!.status ==
                                        GiftCodeStatus.notFound ||
                                    _appliedGift!.status ==
                                        GiftCodeStatus.redeemed ||
                                    _appliedGift!.status ==
                                        GiftCodeStatus.error)
                                  ElevatedButton(
                                    onPressed:
                                        _applying
                                            ? null
                                            : () => unawaited(_applyGift()),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black87,
                                      foregroundColor: Colors.white,
                                    ),
                                    child:
                                        _applying
                                            ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                            : const Text('Apply'),
                                  )
                                else
                                  OutlinedButton(
                                    onPressed: _removeGift,
                                    child: const Text('Remove'),
                                  ),
                              ],
                            ),

                            // inline validation / guidance
                            if (_appliedGift != null &&
                                _giftStatusText.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (_appliedGift!.status ==
                                                  GiftCodeStatus.issued ||
                                              _appliedGift!.status ==
                                                  GiftCodeStatus
                                                      .issuedLegacyValue)
                                          ? const Color(0xFFE9F7EF) // greenish
                                          : const Color(0xFFFDEDEC), // reddish
                                  border: Border.all(
                                    color:
                                        (_appliedGift!.status ==
                                                    GiftCodeStatus.issued ||
                                                _appliedGift!.status ==
                                                    GiftCodeStatus
                                                        .issuedLegacyValue)
                                            ? const Color(0xFF27AE60)
                                            : const Color(0xFFC0392B),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      (_appliedGift!.status ==
                                                  GiftCodeStatus.issued ||
                                              _appliedGift!.status ==
                                                  GiftCodeStatus
                                                      .issuedLegacyValue)
                                          ? Icons.check_circle
                                          : Icons.error_outline,
                                      size: 18,
                                      color:
                                          (_appliedGift!.status ==
                                                      GiftCodeStatus.issued ||
                                                  _appliedGift!.status ==
                                                      GiftCodeStatus
                                                          .issuedLegacyValue)
                                              ? const Color(0xFF27AE60)
                                              : const Color(0xFFC0392B),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _giftStatusText,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            if (isEntitlement && !entitlementSatisfied) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFDEDEC),
                                  border: Border.all(color: Color(0xFFC0392B)),
                                ),
                                child: Text(
                                  entitledCount == 0
                                      ? 'Add one $entitledType to use this gift.'
                                      : 'This gift covers exactly one $entitledType. Please reduce the quantity to one.',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // --- Summary box + shipping destination toggle + preview ---
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black12),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Summary',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),

                            _line('Subtotal', dollars(totals.subtotalCents)),

                            if (totals.discountCents > 0)
                              _line(
                                'Discount',
                                '-${dollars(totals.discountCents)}',
                              ),

                            // Only show numeric BOGO line when we actually have 2+ hoodies AND no entitlement
                            if (!isEntitlement && hasBogo)
                              _line(
                                'Second hoodie half price',
                                '-${dollars(bogoDiscountCents)}',
                              ),

                            const SizedBox(height: 10),
                            const Text(
                              'Shipping destination',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                ChoiceChip(
                                  label: const Text('US'),
                                  selected: _destCountryToggle == 'US',
                                  onSelected:
                                      (_) => setState(
                                        () => _destCountryToggle = 'US',
                                      ),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('International'),
                                  selected: _destCountryToggle == 'WW',
                                  onSelected:
                                      (_) => setState(
                                        () => _destCountryToggle = 'WW',
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            _line(
                              'Shipping',
                              shipCentsPreview == null
                                  ? 'Select a destination'
                                  : dollars(shipCentsPreview),
                            ),

                            // (removed) tax line while tax is disabled
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),

                            _line(
                              orderTotalLabel,
                              dollars(orderTotalPreviewCents),
                              isBold: true,
                            ),

                            const SizedBox(height: 6),
                            if (hoodieQty >= 2 && !isEntitlement)
                              const Text(
                                'Second hoodie half price — applied at checkout.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),

                            if (isEntitlement && entitlementSatisfied)
                              const Text(
                                'Gift code applied — item price will be covered at checkout. '
                                'You’ll pay shipping (and tax if applicable).',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // --- Checkout CTA ---
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ElevatedButton.icon(
                        onPressed: canCheckout ? _startCheckout : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('Check out and pay'),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              );
            },
          );
        },
      ),

      // Bottom "nav"
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
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wallet, size: 24),
                  Text('Wallet', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ColorPickerScreen()),
                );
              },
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.brush, size: 24),
                  Text('Send Vibes', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                );
              },
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_circle, size: 24),
                  Text('Account', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value, {bool isBold = false}) {
    final style = TextStyle(
      fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _QtyButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? Colors.black26 : Colors.black87,
        ),
      ),
    );
  }
}
