import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// -------- Cart mode lives here so UI can import from a single place --------
enum CartMode { hoodieOnly, keepsakesOnly }

/// ---------- Models ----------
class CartItem {
  final String id;
  final String productId;
  final String productName;
  final int unitPriceCents;
  final int qty;
  final bool requiresAddress;
  final String shipTo; // empty when not set
  final bool shippingIncluded;
  final Map<String, dynamic> swatch; // {id, title, colorHex, ...}
  final String? imageUrl;

  // NEW: flattened hoodie metadata (optional; only present for hoodie items)
  final String? hoodieFit; // 'relaxed' | 'slim' (legacy 'tailored' -> 'slim')
  final String? hoodieSize; // 'xs' | 's' | 'm' | 'l' | 'xl' | '2xl'
  final String? hoodiePriceId; // Stripe price_...
  final String? hoodieLookupKey; // hoodie_xs_relaxed etc.

  CartItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unitPriceCents,
    required this.qty,
    required this.requiresAddress,
    required this.shipTo,
    required this.shippingIncluded,
    required this.swatch,
    this.imageUrl,
    this.hoodieFit,
    this.hoodieSize,
    this.hoodiePriceId,
    this.hoodieLookupKey,
  });

  int get lineTotalCents => unitPriceCents * qty;

  factory CartItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return CartItem(
      id: doc.id,
      productId: d['productId'] as String,
      productName: d['productName'] as String,
      unitPriceCents: d['unitPriceCents'] as int,
      qty: d['qty'] as int,
      requiresAddress: d['requiresAddress'] as bool,
      shipTo: (d['shipTo'] as String?) ?? '',
      shippingIncluded: (d['shippingIncluded'] as bool?) ?? false,
      swatch:
          (d['swatch'] is Map)
              ? Map<String, dynamic>.from(d['swatch'] as Map)
              : const <String, dynamic>{},
      imageUrl: d['imageUrl'] as String?,
      // NEW hoodie fields (may be null / absent for non-hoodies)
      hoodieFit: d['hoodieFit'] as String?,
      hoodieSize: d['hoodieSize'] as String?,
      hoodiePriceId: d['hoodiePriceId'] as String?,
      hoodieLookupKey: d['hoodieLookupKey'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'unitPriceCents': unitPriceCents,
    'qty': qty,
    'requiresAddress': requiresAddress,
    'shipTo': shipTo,
    'shippingIncluded': shippingIncluded,
    'swatch': swatch,
    if (imageUrl != null) 'imageUrl': imageUrl,
    // NEW: persist flattened hoodie fields when present
    if (hoodieFit != null) 'hoodieFit': hoodieFit,
    if (hoodieSize != null) 'hoodieSize': hoodieSize,
    if (hoodiePriceId != null) 'hoodiePriceId': hoodiePriceId,
    if (hoodieLookupKey != null) 'hoodieLookupKey': hoodieLookupKey,
  };

  CartItem copyWith({int? qty, String? shipTo}) => CartItem(
    id: id,
    productId: productId,
    productName: productName,
    unitPriceCents: unitPriceCents,
    qty: qty ?? this.qty,
    requiresAddress: requiresAddress,
    shipTo: shipTo ?? this.shipTo,
    shippingIncluded: shippingIncluded,
    swatch: swatch,
    imageUrl: imageUrl,
    // carry hoodie metadata through unchanged
    hoodieFit: hoodieFit,
    hoodieSize: hoodieSize,
    hoodiePriceId: hoodiePriceId,
    hoodieLookupKey: hoodieLookupKey,
  );
}

class CartTotals {
  final int subtotalCents;
  final int discountCents;
  final int taxableCents;
  final int taxCents;
  final int shippingCents;
  final int totalCents;

  const CartTotals({
    required this.subtotalCents,
    required this.discountCents,
    required this.taxableCents,
    required this.taxCents,
    required this.shippingCents,
    required this.totalCents,
  });
}

/// ---------- Presets (postcard / mug / paint) ----------
enum CartPreset { postcard, mug, paint }

class _ProductSpec {
  final String productId;
  final String productName;
  final int unitPriceCents;
  final bool requiresAddress;
  final bool shippingIncluded;
  const _ProductSpec({
    required this.productId,
    required this.productName,
    required this.unitPriceCents,
    required this.requiresAddress,
    required this.shippingIncluded,
  });
}

const Map<CartPreset, _ProductSpec> _presets = {
  CartPreset.postcard: _ProductSpec(
    productId: 'postcard',
    productName: 'Postcard',
    unitPriceCents: 200, // $2
    requiresAddress: true,
    shippingIncluded: false, // shipping collected at Stripe
  ),
  CartPreset.mug: _ProductSpec(
    productId: 'mug',
    productName: 'Custom mug',
    unitPriceCents: 1900, // $19
    requiresAddress: true, // address required
    shippingIncluded: false, // shipping collected at Stripe
  ),
  CartPreset.paint: _ProductSpec(
    productId: 'paint',
    productName: 'jar of paint',
    unitPriceCents: 2900, // $29
    requiresAddress: true, // address required
    shippingIncluded: false,
  ),
};

/// Default product images for presets (assets must exist & be declared in pubspec)
const Map<CartPreset, String> _presetImages = {
  CartPreset.postcard: 'assets/shop/postcard.jpg',
  CartPreset.mug: 'assets/shop/zenmug.jpg',
  CartPreset.paint: 'assets/shop/jar-of-paint.jpg',
};

/// ---------- Repository ----------
class CartRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      throw StateError('No signed-in user for cart access');
    }
    return u.uid;
  }

  // Normalize legacy hoodie fit values.
  String _normalizeHoodieFit(String? v) {
    final s = (v ?? '').trim().toLowerCase();
    if (s == 'tailored') return 'slim'; // legacy -> slim
    if (s == 'slim') return 'slim';
    return 'relaxed';
  }

  // Bucketed path: /users/{uid}/cart/items/items/{itemId}
  CollectionReference<Map<String, dynamic>> _itemsCol(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('cart')
      .doc('items')
      .collection('items');

  // Meta document: /users/{uid}/cart/meta
  DocumentReference<Map<String, dynamic>> _metaDoc(String uid) =>
      _db.collection('users').doc(uid).collection('cart').doc('meta');

  /// Live list of items
  Stream<List<CartItem>> watchItems() {
    return _itemsCol(_uid)
        .orderBy('productName')
        .snapshots()
        .map((qs) => qs.docs.map((d) => CartItem.fromDoc(d)).toList());
  }

  /// Watch discount meta (giftCode + discountCents)
  Stream<Map<String, dynamic>> watchMeta() {
    return _metaDoc(_uid).snapshots().map(
      (doc) => doc.data() ?? {'giftCode': '', 'discountCents': 0},
    );
  }

  // ---------- One-shot helpers & clear ----------

  Future<List<CartItem>> getItemsOnce() async {
    final qs = await _itemsCol(_uid).orderBy('productName').get();
    return qs.docs.map((d) => CartItem.fromDoc(d)).toList();
  }

  Future<Map<String, dynamic>> getMetaOnce() async {
    final doc = await _metaDoc(_uid).get();
    return doc.data() ?? {'giftCode': '', 'discountCents': 0};
  }

  /// Remove all items from the cart (new helper exposed as `clearAll()`).
  Future<void> clearCart() async {
    final qs = await _itemsCol(_uid).get();
    final batch = _db.batch();
    for (final d in qs.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  // Public alias used by CartScreen
  Future<void> clearAll() => clearCart();

  /// Add a new item or increment qty if same product + swatch already exists.
  Future<void> addOrIncrement({
    required String productId,
    required String productName,
    required int unitPriceCents,
    required Map<String, dynamic> swatch, // {id,title,colorHex, ...}
    bool requiresAddress = false,
    bool shippingIncluded = true,
    String? imageUrl,
    int qty = 1,
  }) async {
    final col = _itemsCol(_uid);

    // merge key: productId + swatch.id (+ hoodie.lookupKey for hoodies)
    Query<Map<String, dynamic>> q = col
        .where('productId', isEqualTo: productId)
        .where('swatch.id', isEqualTo: swatch['id']);

    String? hoodieLookupKey;
    if (productId == 'hoodie') {
      final lk =
          (swatch['hoodie'] is Map)
              ? (swatch['hoodie']['lookupKey'] as String?)
              : null;
      hoodieLookupKey = lk;
      if (lk != null && lk.isNotEmpty) {
        q = q.where('swatch.hoodie.lookupKey', isEqualTo: lk);
      }
    }

    final qs = await q.limit(1).get();

    if (qs.docs.isNotEmpty) {
      final doc = qs.docs.first.reference;
      await doc.update({'qty': FieldValue.increment(qty)});
      return;
    }

    // Persist core swatch fields + optional metadata (fingerprint/hoodie)
    final Map<String, dynamic> swatchToSave = {
      'id': swatch['id'],
      'title': swatch['title'] ?? '',
      'colorHex': swatch['colorHex'] ?? '#000000',
      if (swatch['fingerprint'] != null) 'fingerprint': swatch['fingerprint'],
      if (swatch['hoodie'] != null) 'hoodie': swatch['hoodie'],
    };

    // ---- Flatten hoodie variant fields so webhook can read them in cartMeta.items ----
    String? priceId;
    String? hoodieFit;
    String? hoodieSize;
    if (productId == 'hoodie' && swatch['hoodie'] is Map) {
      final h = Map<String, dynamic>.from(swatch['hoodie'] as Map);
      final fit = (h['fit'] ?? h['hoodieFit'])?.toString();
      final size = (h['size'] ?? h['hoodieSize'])?.toString();
      final pid = h['priceId']?.toString();

      hoodieFit = _normalizeHoodieFit(fit); // legacy "tailored" -> "slim"
      hoodieSize = (size ?? '').toLowerCase(); // keep lower; UI uppercases
      priceId = pid;
    }
    // -------------------------------------------------------------------------------

    await col.add({
      'productId': productId,
      'productName': productName,
      'unitPriceCents': unitPriceCents,
      'qty': qty,
      'requiresAddress': requiresAddress,
      'shipTo': '',
      'shippingIncluded': shippingIncluded,
      'swatch':
          swatchToSave, // contains swatch.hoodie {priceId, fit, size, lookupKey}
      if (imageUrl != null) 'imageUrl': imageUrl,

      // NEW flattened hoodie fields (optional; included only for hoodies)
      if (hoodieFit != null && hoodieFit.isNotEmpty) 'hoodieFit': hoodieFit,
      if (hoodieSize != null && hoodieSize.isNotEmpty) 'hoodieSize': hoodieSize,
      if (priceId != null && priceId.isNotEmpty) 'hoodiePriceId': priceId,
      if (hoodieLookupKey != null && hoodieLookupKey.isNotEmpty)
        'hoodieLookupKey': hoodieLookupKey,
    });
  }

  /// Add by preset (postcard/mug/paint)
  Future<void> addPreset({
    required CartPreset preset,
    required Map<String, dynamic> swatch,
    int qty = 1,
    String? imageUrl,
  }) async {
    assert((swatch['id'] is String) && (swatch['id'] as String).isNotEmpty);
    final spec = _presets[preset]!;

    await addOrIncrement(
      productId: spec.productId,
      productName: spec.productName,
      unitPriceCents: spec.unitPriceCents,
      swatch: swatch,
      requiresAddress: spec.requiresAddress,
      shippingIncluded: spec.shippingIncluded,
      imageUrl: imageUrl ?? _presetImages[preset],
      qty: qty,
    );
  }

  Future<void> updateQty(String itemId, int qty) async {
    if (qty < 1) qty = 1;
    await _itemsCol(_uid).doc(itemId).update({'qty': qty});
  }

  Future<void> updateAddress(String itemId, String shipTo) async {
    await _itemsCol(_uid).doc(itemId).update({'shipTo': shipTo});
  }

  Future<void> remove(String itemId) async {
    await _itemsCol(_uid).doc(itemId).delete();
  }

  // -------- Mode enforcement helper (one-liner switch) --------
  bool isAllowedForMode(CartItem it, CartMode mode) {
    if (mode == CartMode.hoodieOnly) {
      return it.productId.trim().toLowerCase() == 'hoodie';
    } else {
      // keepsakesOnly
      final pid = it.productId.trim().toLowerCase();
      return pid == 'postcard' || pid == 'mug' || pid == 'paint';
    }
  }

  /// Gift code:
  /// Store the normalized entitlement code in cart meta.
  /// No local discount is computed here anymore (entitlement handled in backend).
  Future<int> applyGiftCode(String code) async {
    final normalized = code.trim().toUpperCase();

    await _metaDoc(_uid).set({
      'giftCode': normalized,
      // keep discountCents field but always 0 under the new entitlement system
      'discountCents': 0,
    }, SetOptions(merge: true));

    // No immediate client-side discount; backend will decide at checkout
    return 0;
  }

  CartTotals computeTotals(
    List<CartItem> items, {
    required int discountCents,
    double taxRate = 0.05,
    int shippingCents = 0,
  }) {
    final subtotal = items.fold<int>(0, (sum, it) => sum + it.lineTotalCents);
    final taxable = (subtotal - discountCents).clamp(0, 1 << 31);
    final tax = (taxable * taxRate).round();
    final total = taxable + tax + shippingCents;

    return CartTotals(
      subtotalCents: subtotal,
      discountCents: discountCents,
      taxableCents: taxable,
      taxCents: tax,
      shippingCents: shippingCents,
      totalCents: total,
    );
  }
}
