import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/fingerprint_flow_screen.dart';
import 'screens/initial_logo_screen.dart';
import 'state/fingerprint_state.dart';
import 'widgets/phone_frame.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZenmoApp());
}

class ZenmoApp extends StatelessWidget {
  const ZenmoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final state = FingerprintState();
        // Load saved state asynchronously
        state.load();
        return state;
      },
      child: MaterialApp(
        title: 'Zenmo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        builder: (context, child) {
          return PhoneFrame(child: child ?? const SizedBox.shrink());
        },
        home: const InitialLogoScreen(), // Updated to use new UI redesign entry point
      ),
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
