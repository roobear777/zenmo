import 'package:color_wallet/widgets/wallet_badge_icon.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'menu.dart';
import 'wallet_screen.dart';
import 'color_picker_screen.dart';
import 'feedback_screen.dart'; // NEW
import 'daily_hues/daily_scroll_screen.dart'; // NEW: Daily Hues

class AppInfoScreen extends StatefulWidget {
  const AppInfoScreen({super.key});

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  int _selectedIndex = 2; // Daily Hues tab

  // --- Apps Script webhook (used by "Yay!" ping only) -----------------------
  static const String _MAIL_ENDPOINT =
      'https://script.google.com/macros/s/AKfycbyKzhzn5v4gfqyY8Ix_o_G6z7VpRS5xg2Bi4vY_b9cGo92BeFGDX-xqzAR9DJYVMXo6/exec';
  static const String _MAIL_TOKEN =
      'a3f7c1b9e0d4420dbf0d0c7e4c9f2f8a6d11b5e3f87e0b12c4d5a6b7c8d9e0f1';

  String get _userDisplayName {
    final u = FirebaseAuth.instance.currentUser;
    return (u?.displayName?.trim().isNotEmpty == true)
        ? u!.displayName!.trim()
        : (u?.email ?? 'anonymous');
  }

  // --- Nav ------------------------------------------------------
  void _onNavTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WalletScreen()),
      );
    } else if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ColorPickerScreen()),
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DailyScrollScreen()),
      );
    }
  }

  // --- Simple ping to team (used by "Yay!") ---------------------------------
  Future<void> _sendToTeam({
    required String subject,
    required String body,
  }) async {
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? '';

    final form = {
      'token': _MAIL_TOKEN,
      'subject': subject,
      'body': body,
      if (userEmail.isNotEmpty) 'replyTo': userEmail,
    };

    final res = await http.post(
      Uri.parse(_MAIL_ENDPOINT),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: form.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&'),
    );

    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    try {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['ok'] != true) {
        throw Exception('Script error: ${json['error'] ?? 'unknown'}');
      }
    } catch (_) {}
  }

  // --- Dialog for "Yay!" ----------------------------------------------------
  Future<void> _showYayDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            backgroundColor: Colors.transparent,
            child: _PanelBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Thank you for your appreciation. :)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Come back here on March 21st for a special invitation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.4),
                  ),
                  SizedBox(height: 14),
                  SizedBox.shrink(),
                ],
              ),
            ),
          ),
    );

    // Fire-and-forget "Yay!" ping
    _sendToTeam(
      subject: 'Yay from $_userDisplayName',
      body:
          '$_userDisplayName tapped "Yay!" in App Info.\nDevice time: ${DateTime.now()}',
    ).catchError((_) {});
  }

  // --- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('App Info'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: const [
          ZenmoMenuButton(isOnWallet: false, isOnColorPicker: false),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Colors.black12),
        ),
      ),
      body: Column(
        children: [
          // Scrollable intro copy
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  height: 1.5,
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _P(
                      children: [
                        TextSpan(
                          text: 'Zenmo',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text:
                              ' was created by Frankie Abralind and Roo Rowley, who met at KiwiBurn in 2024, to allow people to send good vibes instead of money.',
                        ),
                      ],
                    ),
                    _Gap(),
                    _P(
                      children: [
                        TextSpan(
                          text:
                              'A portion of our profits goes to protecting ocean habitat for octopuses, which communicate using color.',
                        ),
                      ],
                    ),
                    _Gap(),
                    _P(
                      children: [
                        TextSpan(
                          text:
                              'Please let us know what you think using the buttons below. The one on the left just sends us a friendly little heart; the other one opens a short feedback form. :)',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Buttons row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: _LightButton(
                    onPressed: _showYayDialog,
                    icon: Icons.favorite_border,
                    label: 'Yay!',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LightButton(
                    // Replaced old dialog with navigation to the new screen
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FeedbackScreen(),
                        ),
                      );
                    },
                    icon: Icons.chat_bubble_outline,
                    label: 'Feedback',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // Bottom nav
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTapped,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
        items: const [
          BottomNavigationBarItem(icon: WalletBadgeIcon(), label: 'Wallet'),
          BottomNavigationBarItem(icon: Icon(Icons.brush), label: 'Send Vibes'),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded), // Daily Hues icon
            label: 'Daily Hues',
          ),
        ],
      ),
    );
  }
}

// --- Small helpers -----------------------------------------------------------

class _P extends StatelessWidget {
  final List<InlineSpan> children;
  const _P({required this.children});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: children,
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap();
  @override
  Widget build(BuildContext context) => const SizedBox(height: 18);
}

class _LightButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  const _LightButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.grey[800]),
      label: Text(label, style: TextStyle(color: Colors.grey[800])),
      style: TextButton.styleFrom(
        backgroundColor: const Color(0xFFF1F2F4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}

/// Gray panel with white inset border (used in the Yay! dialog)
class _PanelBox extends StatelessWidget {
  final Widget child;
  const _PanelBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF9EA2A8),
          borderRadius: BorderRadius.circular(6),
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: child,
        ),
      ),
    );
  }
}
