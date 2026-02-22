import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OrderItemPayload {
  final String productId;
  final String productName;
  final int unitPriceCents;
  final int qty;

  /// Must include at least one of:
  /// - 'colorHex': String "#RRGGBB"
  /// - 'paletteHex': List<String> of "#RRGGBB"
  /// - 'fingerprintHex': List<String> of 25 "#RRGGBB"
  final Map<String, dynamic> swatch; // forwarded from CartItem.swatch
  final bool requiresAddress;
  final String shipTo;
  final bool shippingIncluded;
  final String? imageUrl;

  OrderItemPayload({
    required this.productId,
    required this.productName,
    required this.unitPriceCents,
    required this.qty,
    required this.swatch,
    required this.requiresAddress,
    required this.shipTo,
    required this.shippingIncluded,
    this.imageUrl,
  });

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'unitPriceCents': unitPriceCents,
    'qty': qty,
    'swatch': swatch,
    'requiresAddress': requiresAddress,
    'shipTo': shipTo,
    'shippingIncluded': shippingIncluded,
    if (imageUrl != null) 'imageUrl': imageUrl,
  };
}

class OrderRepository {
  final _db = FirebaseFirestore.instance;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  /// Creates an order doc and returns its ID + a Venmo deep link.
  Future<({String orderId, Uri venmoApp, Uri venmoWeb})> createOrder({
    required List<OrderItemPayload> items,
    required int subtotalCents,
    required int discountCents,
    required int taxCents,
    required int shippingCents,
    required int totalCents,
    required String giftCode,
    required String venmoRecipient, // e.g. "fabralind"
  }) async {
    final ref = await _db.collection('orders').add({
      'userUid': _uid,
      'status': 'pending_payment', // manual flip to 'paid' later
      'createdAt': FieldValue.serverTimestamp(),
      'paymentMethod': 'venmo',
      'totals': {
        'subtotalCents': subtotalCents,
        'discountCents': discountCents,
        'taxCents': taxCents,
        'shippingCents': shippingCents,
        'totalCents': totalCents,
        'giftCode': giftCode,
      },
      'items': items.map((e) => e.toMap()).toList(),
    });

    final orderId = ref.id;
    final amountDollars = (totalCents / 100).toStringAsFixed(2);
    final note = Uri.encodeComponent('Zenmo Order $orderId');
    final app = Uri.parse(
      'venmo://paycharge?txn=pay&recipients=$venmoRecipient&amount=$amountDollars&note=$note',
    );
    final web = Uri.parse(
      'https://venmo.com/$venmoRecipient?txn=pay&amount=$amountDollars&note=$note',
    );

    return (orderId: orderId, venmoApp: app, venmoWeb: web);
  }
}
