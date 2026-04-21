import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../state/fingerprint_state.dart';
import '../widgets/primary_button.dart';
import 'admin/admin_login_screen.dart';
import 'understand_screen.dart';

/// Initial entry screen displaying the Zenmo logo and primary navigation
/// Requirements: 1.1, 1.2, 1.3, 12.9, 17.1, 1.4, 17.2
class InitialLogoScreen extends StatefulWidget {
  const InitialLogoScreen({super.key});

  @override
  State<InitialLogoScreen> createState() => _InitialLogoScreenState();
}

class _InitialLogoScreenState extends State<InitialLogoScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _textOpacity;
  late Animation<double> _textScale;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Text fades in and scales up
    _textOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _textScale = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Animated Zenmo text
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _textOpacity.value,
                    child: Transform.scale(
                      scale: _textScale.value,
                      child: const Text(
                        'Zenmo',
                        style: TextStyle(
                          fontFamily: 'OleoScriptBold',
                          fontSize: 96,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  );
                },
              ),

              const Spacer(flex: 2),

              // "Test Questions" button
              PrimaryButton(
                label: 'Test Questions',
                fullWidth: true,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const UnderstandScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),

              // "New User" reset button
              TextButton(
                onPressed: () {
                  context.read<FingerprintState>().resetAll();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ready for a new user'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: const Text(
                  'New User',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black38,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // "Anonymous Feedback Survey" link at bottom
              GestureDetector(
                onTap: () async {
                  final Uri url = Uri.parse(
                    'https://forms.gle/qMgBFgQZzQefgnQo9',
                  );
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text(
                  'Anonymous Feedback Survey',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF6366F1),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),

            // Discreet admin lock icon — bottom right
            Positioned(
              bottom: 16,
              right: 16,
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => const AdminLoginScreen(),
                    ),
                  );
                },
                child: const Icon(
                  Icons.lock_outline,
                  size: 22,
                  color: Color(0xFF999999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
