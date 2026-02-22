// lib/menu.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'welcome_screen.dart';
import 'wallet_screen.dart'; // Wallet screen (tabs available internally)
import 'color_picker_screen.dart';
import 'account_screen.dart';
import 'app_info_screen.dart';
import 'cart_screen.dart';

// Feature flag + route for Daily Hues
import 'config/feature_flags.dart';
import 'daily_hues/daily_hues_screen.dart';

// NEW: Gift flows (screens live directly under lib/)
import 'package:color_wallet/gift_hub_screen.dart';
import 'my_rewards_screen.dart'; // NEW

class ZenmoMenuPanel extends StatefulWidget {
  final bool isOnWallet;
  final bool isOnColorPicker;
  final Color? selectedColor;

  const ZenmoMenuPanel({
    super.key,
    this.isOnWallet = false,
    this.isOnColorPicker = false,
    this.selectedColor,
  });

  @override
  State<ZenmoMenuPanel> createState() => _ZenmoMenuPanelState();
}

class _ZenmoMenuPanelState extends State<ZenmoMenuPanel> {
  Future<void> _performLogout() async {
    Navigator.of(context).pop();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('zenmo_display_name');

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 6, 8, 12),
              child: Text(
                'Zenmo',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFF7B61FF)),
            const SizedBox(height: 10),

            // Cart
            _menuItem(
              icon: Icons.shopping_cart_outlined,
              label: 'Cart',
              trailingChevron: true,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                );
              },
            ),

            // Create Swatch
            _menuItem(
              icon: Icons.brush_outlined,
              label: 'Send Vibes',
              trailingChevron: true,
              onTap: () {
                Navigator.pop(context);
                if (!widget.isOnColorPicker) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ColorPickerScreen(),
                    ),
                  );
                }
              },
            ),

            // Daily Hues
            if (FeatureFlags.dailyHuesEnabled)
              _menuItem(
                icon: Icons.grid_view_rounded,
                label: 'Daily Hues',
                trailingChevron: true,
                onTap: () {
                  Navigator.pop(context); // Close the menu
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const DailyHuesScreen()),
                  );
                },
              ),

            // Gift an Item
            _menuItem(
              icon: Icons.card_giftcard,
              label: 'Gift an Item',
              trailingChevron: true,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GiftHubScreen()),
                );
              },
            ),

            // Rewards
            _menuItem(
              icon: Icons.emoji_events_outlined,
              label: 'Rewards',
              trailingChevron: true,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyRewardsScreen()),
                );
              },
            ),

            // (Removed) Redeem a Gift Code — users will redeem at checkout.

            // Wallet (compact single item)
            _menuItem(
              icon: Icons.wallet,
              label: 'Wallet',
              trailingChevron: true,
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const WalletScreen()),
                );
              },
            ),

            // Account
            _menuItem(
              icon: Icons.account_circle_outlined,
              label: 'Fingerprint & Account',
              trailingChevron: true,
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                );
              },
            ),

            // App Info
            _menuItem(
              icon: Icons.info_outline,
              label: 'APP INFO',
              trailingChevron: true,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AppInfoScreen()),
                );
              },
            ),

            // Settings
            _menuItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              trailingChevron: true,
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings is coming soon.')),
                );
              },
            ),

            const Divider(height: 20),

            // Log out
            _menuItem(
              icon: Icons.logout,
              label: 'Log out',
              onTap: _performLogout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
    bool trailingChevron = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black87),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
            if (trailing != null) trailing,
            if (trailingChevron) const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

class ZenmoMenuButton extends StatelessWidget {
  final bool isOnWallet;
  final bool isOnColorPicker;
  final Color? selectedColor;

  const ZenmoMenuButton({
    super.key,
    this.isOnWallet = false,
    this.isOnColorPicker = false,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu, color: Colors.black),
      onPressed: () {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) {
            return Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, left: 8),
                child: Material(
                  elevation: 12,
                  borderRadius: BorderRadius.circular(8),
                  child: ZenmoMenuPanel(
                    isOnWallet: isOnWallet,
                    isOnColorPicker: isOnColorPicker,
                    selectedColor: selectedColor,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
