// lib/gift_purchase_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart'; // NEW: open Stripe Checkout
import 'models/gift_item_type.dart';

/// Re-uses the same images you already show on Keepsakes/Hoodie.
const _assetPostcard = 'assets/shop/postcard.jpg';
const _assetMug = 'assets/shop/zenmug.jpg';
const _assetPaint = 'assets/shop/jar-of-paint.jpg';
const _assetHoodie = 'assets/shop/fingerprint_hoodie.png';

String _titleFor(GiftItemType t) {
  switch (t) {
    case GiftItemType.hoodie:
      return 'Gift a Hoodie';
    case GiftItemType.mug:
      return 'Gift a Mug';
    case GiftItemType.paint:
      return 'Gift a Jar of Paint';
    case GiftItemType.postcard:
      return 'Gift a Postcard';
  }
}

String _kindFor(GiftItemType t) {
  switch (t) {
    case GiftItemType.hoodie:
      return 'hoodie';
    case GiftItemType.mug:
      return 'mug';
    case GiftItemType.paint:
      return 'paint';
    case GiftItemType.postcard:
      return 'postcard';
  }
}

String _assetFor(GiftItemType t) {
  switch (t) {
    case GiftItemType.hoodie:
      return _assetHoodie;
    case GiftItemType.mug:
      return _assetMug;
    case GiftItemType.paint:
      return _assetPaint;
    case GiftItemType.postcard:
      return _assetPostcard;
  }
}

class GiftPurchaseScreen extends StatefulWidget {
  final GiftItemType itemType;
  const GiftPurchaseScreen({super.key, required this.itemType});

  @override
  State<GiftPurchaseScreen> createState() => _GiftPurchaseScreenState();
}

class _GiftPurchaseScreenState extends State<GiftPurchaseScreen> {
  final _emailCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Rebuild when the email changes so the button enable/disable state updates.
    _emailCtrl.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String v) {
    final s = v.trim();
    if (s.isEmpty) return false;
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(s);
  }

  Future<void> _buy() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'createGiftEntitlementCheckout',
      );
      final resp = await callable.call(<String, dynamic>{
        'itemType': _kindFor(widget.itemType),
        'recipientEmail': _emailCtrl.text.trim(),
        'message': _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
      });
      final url = (resp.data as Map)['checkoutUrl'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception('Missing checkoutUrl');
      }

      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw Exception('Could not open checkout');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = _assetFor(widget.itemType);
    final title = _titleFor(widget.itemType);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Hero image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.asset(
                asset,
                fit: BoxFit.cover,
                errorBuilder:
                    (_, __, ___) => Container(
                      color: const Color(0xFFEFF1F4),
                      child: const Center(
                        child: Icon(Icons.broken_image, size: 40),
                      ),
                    ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Explanation (concise)
          Text(
            widget.itemType == GiftItemType.hoodie
                ? 'We’ll generate a one-time gift code that covers the hoodie. '
                    'Your recipient signs up to Zenmo, picks their size/style and fingerprint, '
                    'enters the code at checkout, and pays shipping/tax.'
                : 'We’ll generate a one-time gift code that covers this item. '
                    'Your recipient signs up to Zenmo, chooses their Zenmo color or fingerprint, '
                    'enters the code at checkout, and pays shipping/tax.',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),

          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Recipient email',
                    hintText: 'friend@example.com',
                    border: OutlineInputBorder(),
                  ),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator:
                      (v) =>
                          _validEmail(v ?? '')
                              ? null
                              : 'Enter a valid email (required)',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _msgCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Personal message (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_busy || !_validEmail(_emailCtrl.text)) ? null : _buy,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5A4A84),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child:
                  _busy
                      ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('Buy Gift Code'),
            ),
          ),
        ],
      ),
    );
  }
}
