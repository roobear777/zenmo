import 'package:flutter/material.dart';
import '../widgets/primary_button.dart';
import 'understand_screen.dart';

/// Initial entry screen displaying the Zenmo logo and primary navigation
/// Requirements: 1.1, 1.2, 1.3, 12.9, 17.1, 1.4, 17.2
class InitialLogoScreen extends StatelessWidget {
  const InitialLogoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              
              // Centered "zenmo" text logo
              const Text(
                'zenmo',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              
              const Spacer(flex: 2),
              
              // "Test Questions" button
              PrimaryButton(
                label: 'Test Questions',
                fullWidth: true,
                onPressed: () {
                  // Navigate to UnderstandScreen - Requirement 1.4
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const UnderstandScreen(),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 32),
              
              // "Anonymous Feedback Survey" link at bottom
              GestureDetector(
                onTap: () {
                  // Placeholder - no action per requirement 17.2
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
      ),
    );
  }
}
