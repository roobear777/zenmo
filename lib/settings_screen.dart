// lib/settings_screen.dart
import 'package:color_wallet/widgets/wallet_badge_icon.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account & Settings'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(height: 1.0, color: Colors.black12),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            const Text(
              'Your user settings:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const BulletList([
              'billing info',
              'password',
              'your name',
              'default shipping address',
              'credit card',
            ]),
            const SizedBox(height: 24),
            const Text(
              'Your Color Fingerprint',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const BulletList(['create', 'view', 'redo']),
            const SizedBox(height: 24),
            Container(
              height: 150,
              color: Colors.grey[200],
              child: const Center(
                child: Icon(Icons.image_outlined, size: 50, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2, // Settings tab
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacementNamed(context, '/wallet');
          } else if (index == 1) {
            Navigator.pushReplacementNamed(context, '/create');
          } else if (index == 2) {
            // already here
          }
        },
        items: const [
          BottomNavigationBarItem(icon: WalletBadgeIcon(), label: 'Wallet'),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Send Vibes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class BulletList extends StatelessWidget {
  final List<String> items;
  const BulletList(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          items
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('\u2022 ', style: TextStyle(fontSize: 16)),
                      Expanded(
                        child: Text(item, style: const TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }
}
