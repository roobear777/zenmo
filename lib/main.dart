import 'package:flutter/material.dart';
import 'screens/fingerprint_flow_screen.dart';

void main() {
  runApp(const ZenmoApp());
}

class ZenmoApp extends StatelessWidget {
  const ZenmoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zenmo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zenmo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Welcome to Zenmo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FingerprintFlowScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.fingerprint),
              label: const Text('Create Fingerprint'),
            ),
          ],
        ),
      ),
    );
  }
}
