import 'package:flutter/material.dart';

import 'gift_purchase_screen.dart'; // GiftPurchaseScreen
import 'models/gift_item_type.dart'; // GiftItemType enum

class GiftHubScreen extends StatelessWidget {
  const GiftHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gift an Item')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          const Text(
            'Pick what you want to gift',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            "We’ll generate a one-time gift code. The recipient chooses size/style when claiming it. "
            "They’ll open Zenmo and enter the code in Cart → Gift Card Code. Shipping is paid at checkout.",
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),

          _GiftTile(
            title: 'Hoodie',
            imageAsset: 'assets/shop/fingerprint_hoodie.png',
            onTap: (ctx) => _open(ctx, GiftItemType.hoodie),
          ),
          _GiftTile(
            title: 'Mug',
            imageAsset: 'assets/shop/zenmug.jpg',
            onTap: (ctx) => _open(ctx, GiftItemType.mug),
          ),
          _GiftTile(
            title: 'Paint',
            imageAsset: 'assets/shop/jar-of-paint.jpg',
            onTap: (ctx) => _open(ctx, GiftItemType.paint),
          ),
          _GiftTile(
            title: 'Postcard',
            imageAsset: 'assets/shop/postcard.jpg',
            onTap: (ctx) => _open(ctx, GiftItemType.postcard),
          ),
        ],
      ),
    );
  }

  static void _open(BuildContext context, GiftItemType type) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GiftPurchaseScreen(itemType: type)),
    );
  }
}

class _GiftTile extends StatelessWidget {
  final String title;
  final String imageAsset;
  final void Function(BuildContext) onTap;

  const _GiftTile({
    required this.title,
    required this.imageAsset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F3FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: ListTile(
        onTap: () => onTap(context),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              width: 64,
              height: 64,
              color: const Color(0xFFEFF1F4),
              child: Image.asset(
                imageAsset,
                fit: BoxFit.cover,
                errorBuilder:
                    (_, __, ___) => const Icon(
                      Icons.broken_image,
                      size: 28,
                      color: Colors.black38,
                    ),
              ),
            ),
          ),
        ),
        title: Text(title, style: const TextStyle(fontSize: 18)),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
