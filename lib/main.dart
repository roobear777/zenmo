import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'screens/initial_logo_screen.dart';
import 'services/auth_service.dart';
import 'services/firestore_fingerprint_service.dart';
import 'services/shared_prompts_service.dart';
import 'services/shared_prompts_service.dart';
import 'state/color_creation_state.dart';
import 'state/shared_prompts_state.dart';
import 'state/fingerprint_state.dart';
import 'widgets/phone_frame.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Firebase — swallow errors so the app always renders.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  // Sign in anonymously — swallow errors, app works without it.
  final authService = AuthService();
  await authService.ensureAnonymousSignIn();

  runApp(ZenmoApp(authService: authService));
}

class ZenmoApp extends StatelessWidget {
  const ZenmoApp({super.key, required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: authService),
        Provider<FirestoreFingerprintService>.value(
          value: FirestoreFingerprintService(),
        ),
        ChangeNotifierProvider<FingerprintState>(
          create: (_) {
            final state = FingerprintState();
            state.load();
            return state;
          },
        ),
        ChangeNotifierProvider<ColorCreationState>(
          create: (_) => ColorCreationState(),
        ),
        ChangeNotifierProvider<SharedPromptsState>(
          create: (_) => SharedPromptsState(SharedPromptsService()),
        ),
      ],
      child: MaterialApp(
        title: 'Zenmo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        builder: (context, child) {
          return PhoneFrame(child: child ?? const SizedBox.shrink());
        },
        home: const InitialLogoScreen(),
      ),
    );
  }
}
