// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kDebugMode, kIsWeb
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async'; // unawaited, futures

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html; // web-only: for service worker retire

import 'firebase_options.dart';
import 'welcome_screen.dart';
import 'wallet_screen.dart';

// Daily Hues routes
import 'daily_hues/daily_hues_screen.dart';
import 'daily_hues/answer_question_screen.dart';
import 'daily_hues/answer_details_screen.dart';

// Models & repos for deep link resolver
import 'models/answer.dart';
import 'services/firestore/answer_repository_firestore.dart';

// Swatch repo (for seeding)
import 'services/swatch_repository.dart';

// Same day source as grid
import 'services/daily_clock.dart';

// Admin dashboard
import 'package:color_wallet/admin/admin_dashboard.dart';
// Wide-mode flag now lives in admin_components.dart
import 'package:color_wallet/admin/admin_components.dart';

// XR frame wrapper
import 'screen_wrapper.dart';

// Under construction screen
import 'under_construction_screen.dart';

// NEW: Cart route target
import 'cart_screen.dart';

////////////////////////////////////////////////////////////////////////////////
// DEV CONFIG (gated by Firestore emulator)
////////////////////////////////////////////////////////////////////////////////

// Maintenance screen toggle (set via --dart-define=MAINTENANCE=true)
const bool maintenanceMode = bool.fromEnvironment(
  'MAINTENANCE',
  defaultValue: false,
);

/// Firestore emulator switch.
const bool kUseFirestoreEmu = bool.fromEnvironment(
  'USE_FIRESTORE_EMU',
  defaultValue: false,
);

/// Verbose Firebase app line (projectId/apiKey/appId).
/// Default: off in release, on in debug. Always on when emulator is used.
const bool kVerboseFirebaseLogs = bool.fromEnvironment(
  'VERBOSE_FB_LOGS',
  defaultValue: kDebugMode,
);

/// Silence the known noisy DevTools Null-send message.
const bool kSilenceNoisyDevtoolLine = bool.fromEnvironment(
  'SILENCE_NOISY_DEVTOOLS',
  defaultValue: true,
);

/// Toggle if you ever want to hide the Admin FAB without code changes.
const bool kShowAdminFab = bool.fromEnvironment(
  'SHOW_ADMIN_BUTTON',
  defaultValue: true,
);

////////////////////////////////////////////////////////////////////////////////
// GLOBALS: Navigator key + log filtering
////////////////////////////////////////////////////////////////////////////////

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

bool _isNoisyDevtoolMsg(String s) {
  if (!kSilenceNoisyDevtoolLine) return false;
  return s.startsWith(
        'DebugService: Error serving requestsError: Unsupported operation: Cannot send Null',
      ) ||
      s.contains('Unsupported operation: Cannot send Null');
}

// Whitelist helper for Admin gating
bool isWhitelistedUid(String? uid) =>
    uid == "OpWxbjKjOuYSLopBew8uHQlMY1F2" ||
    uid == "qjvsPsCL9uZS6ba3x4cqJPWXaSb2";

////////////////////////////////////////////////////////////////////////////////
// WEB-ONLY: Retire any active Service Worker once (non-blocking), then reload.
////////////////////////////////////////////////////////////////////////////////

Future<void> retireServiceWorkerOnce() async {
  if (!kIsWeb) return;
  try {
    final storage = html.window.localStorage;
    if (storage['swRetired'] == '1') return;

    final sw = html.window.navigator.serviceWorker;
    final regs =
        await (sw?.getRegistrations() ??
            Future.value(<html.ServiceWorkerRegistration>[]));
    if (regs.isEmpty) return;

    for (final r in regs) {
      try {
        await r.unregister();
      } catch (_) {}
    }
    storage['swRetired'] = '1';
    html.window.location.reload();
  } catch (_) {
    // swallow; app still runs
  }
}

////////////////////////////////////////////////////////////////////////////////
// FAST START: runApp immediately, initialize Firebase in background
////////////////////////////////////////////////////////////////////////////////

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Filter a specific noisy DevTools line (guarded by switch).
  final origDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    final msg = message ?? '';
    if (_isNoisyDevtoolMsg(msg)) return;
    origDebugPrint(message, wrapWidth: wrapWidth);
  };

  FlutterError.onError = (details) {
    if (_isNoisyDevtoolMsg(details.exceptionAsString())) return;
    FlutterError.presentError(details);
  };

  // Show an immediate boot frame; do NOT block on async init.
  runApp(const _BootApp());

  // Start init in background (don’t await).
  // When done, swap to the real app with another runApp.
  unawaited(_initFirebaseAndServicesThenLaunch());
}

Future<void> _initFirebaseAndServicesThenLaunch() async {
  // Firebase core (required before any FirebaseX.instance use)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Non-blocking retire of service worker: start it but don’t wait here.
  unawaited(retireServiceWorkerOnce());

  // Firestore settings
  await _configureFirestore();

  if (kUseFirestoreEmu || kVerboseFirebaseLogs) {
    final o = Firebase.app().options;
    debugPrint(
      '[FB] projectId=${o.projectId} apiKey=${o.apiKey} appId=${o.appId} useEmu=$kUseFirestoreEmu',
    );
  }

  // Profile upsert: only via listener; don’t block startup.
  FirebaseAuth.instance.authStateChanges().listen((u) {
    if (u != null) {
      unawaited(_upsertUserProfile(u));
    }
  });

  // Switch to the real app (now that Firebase is ready).
  // Safe to call runApp again.
  runApp(const ZenmoApp());
}

/// Routes Firestore to emulator when kUseFirestoreEmu is true.
Future<void> _configureFirestore() async {
  if (kUseFirestoreEmu) {
    // Firestore -> local emulator
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    // NOTE: Auth remains on PROD to let you sign in with real users.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
    debugPrint(
      '[EMU] Firestore -> 127.0.0.1:8080 (persistence OFF) | Auth -> PROD',
    );
  } else {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
    debugPrint('[EMU] Firestore -> PROD (persistence ON)');
  }
}

/// Minimal profile upsert to guarantee /users docs exist for Admin – Users.
/// Write-once semantics for `createdAt`: set on create, never on update.
Future<void> _upsertUserProfile(User u) async {
  final db = FirebaseFirestore.instance;
  final ref = db.collection('users').doc(u.uid);
  final now = FieldValue.serverTimestamp();

  await db.runTransaction((tx) async {
    final snap = await tx.get(ref);

    if (!snap.exists) {
      // First-time create: include createdAt once.
      tx.set(ref, {
        'uid': u.uid,
        'email': u.email ?? '',
        'displayName':
            (u.displayName?.trim().isNotEmpty == true)
                ? u.displayName!.trim()
                : 'anonymous',
        'photoURL': u.photoURL,
        'status': 'active',
        'createdAt': now, // write-once on create
        'updatedAt': now,
        'lastActive': now,
      });
    } else {
      // Existing user: never touch createdAt.
      tx.update(ref, {
        'email': u.email ?? '',
        'displayName':
            (u.displayName?.trim().isNotEmpty == true)
                ? u.displayName!.trim()
                : 'anonymous',
        'photoURL': u.photoURL,
        'status': 'active',
        'updatedAt': now,
        'lastActive': now,
      });
    }
  });
}

////////////////////////////////////////////////////////////////////////////////
// BOOT APP: ultra-light first paint while Firebase initializes
////////////////////////////////////////////////////////////////////////////////

class _BootApp extends StatelessWidget {
  const _BootApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zenmo',
      debugShowCheckedModeBanner: false,
      home: const _BootScreen(),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: Color(0xFF5F6572),
          unselectedItemColor: Color(0xFF5F6572),
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.w500),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          // Keep boot frame, but don't render any wordmark to avoid a 3rd “Zenmo”.
          child: SizedBox.shrink(),
        ),
      ),
    );
  }
}

////////////////////////////////////////////////////////////////////////////////
// APP WIDGET: routes, deep links, narrow layout wrapper, dev/admin overlays
////////////////////////////////////////////////////////////////////////////////

class ZenmoApp extends StatelessWidget {
  const ZenmoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      showSemanticsDebugger: false,
      title: 'Zenmo',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: Color(0xFF5F6572),
          unselectedItemColor: Color(0xFF5F6572),
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.w500),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500),
        ),
      ),

      // ---- Named routes ------------------------------------------------------
      routes: <String, WidgetBuilder>{
        WalletScreen.routeName: (_) => const WalletScreen(),
        DailyHuesScreen.routeName: (_) => const DailyHuesScreen(),
        AdminDashboardScreen.routeName:
            (context) => const AdminDashboardScreen(),
        '/answerQuestion': (ctx) {
          final args =
              ModalRoute.of(ctx)!.settings.arguments as Map<String, dynamic>;
          return AnswerQuestionScreen(questionId: args['questionId'] as String);
        },
      },

      // ---- Honor initial URL on first load (Flutter Web & mobile deep links) -
      onGenerateInitialRoutes: (String initialRoute) {
        // Global maintenance gate for initial route resolution
        if (maintenanceMode) {
          return <Route<dynamic>>[
            MaterialPageRoute(
              settings: const RouteSettings(name: '/maintenance'),
              builder: (_) => const UnderConstructionScreen(),
            ),
          ];
        }

        // Support both path-based (/admin) and hash-based (#/admin) URLs.
        final Uri base = Uri.base;
        final String path = base.path; // "/admin" or "/"
        final String frag = base.fragment; // "admin" or "answer/ID" when hash
        final List<String> fragSegs =
            frag.startsWith('/')
                ? Uri.parse(frag).pathSegments
                : frag.isEmpty
                ? const []
                : Uri.parse('/$frag').pathSegments;

        // Case 1: Admin via path or hash. Gate by whitelist.
        final bool isAdminPath = path == AdminDashboardScreen.routeName;
        final bool isAdminHash =
            fragSegs.isNotEmpty &&
            '/${fragSegs.first}' == AdminDashboardScreen.routeName;

        if (isAdminPath || isAdminHash) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (isWhitelistedUid(uid)) {
            // Wide flag: lives in admin_components.dart
            adminIsWide.value = true;
            return <Route<dynamic>>[
              MaterialPageRoute(
                settings: const RouteSettings(
                  name: AdminDashboardScreen.routeName,
                ),
                builder: (_) => const AdminDashboardScreen(),
              ),
            ];
          }
          // Not whitelisted – fall back to public landing.
          return <Route<dynamic>>[
            MaterialPageRoute(
              settings: const RouteSettings(name: '/'),
              builder: (_) => const WelcomeScreen(),
            ),
          ];
        }

        // Case 2: Deep link to /answer/<id> via path or hash.
        final List<String> pathSegs = base.pathSegments;
        final bool isAnswerPath =
            pathSegs.length == 2 && pathSegs.first == 'answer';
        final bool isAnswerHash =
            fragSegs.length == 2 && fragSegs.first == 'answer';

        if (isAnswerPath || isAnswerHash) {
          final String answerId = isAnswerPath ? pathSegs[1] : fragSegs[1];
          return <Route<dynamic>>[
            MaterialPageRoute(
              settings: RouteSettings(name: '/answer/$answerId'),
              builder: (_) => _AnswerLinkGate(answerId: answerId),
            ),
          ];
        }

        // Case 3: Cart via path or hash (handles #/cart?status=success|cancel)
        final bool isCartPath =
            (pathSegs.length == 1 && pathSegs.first == 'cart') ||
            path == '/cart';
        final bool isCartHash = fragSegs.isNotEmpty && fragSegs.first == 'cart';

        if (isCartPath || isCartHash) {
          return <Route<dynamic>>[
            MaterialPageRoute(
              settings: const RouteSettings(name: '/cart'),
              builder: (_) => const CartScreen(),
            ),
          ];
        }

        // Default to Welcome.
        return <Route<dynamic>>[
          MaterialPageRoute(
            settings: const RouteSettings(name: '/'),
            builder: (_) => const WelcomeScreen(),
          ),
        ];
      },

      // ---- Deep link: /answer/<id> fetch and forward -------------------------
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        Uri uri;
        try {
          uri = Uri.parse(name);
        } catch (_) {
          return null;
        }
        final segs = uri.pathSegments;
        if (segs.length == 2 && segs.first == 'answer') {
          final answerId = segs[1];
          return MaterialPageRoute(
            builder: (_) => _AnswerLinkGate(answerId: answerId),
          );
        }
        return null;
      },

      // ---- Layout wrapper + DEV/ADMIN overlays ------------------------------
      builder: (context, child) {
        // Global maintenance gate in builder (covers all navigations)
        if (maintenanceMode) return const UnderConstructionScreen();

        final Widget content = child ?? const SizedBox.shrink();

        // Force wide shell from URL only if whitelisted.
        bool forceWideFromUrl = false;
        if (kIsWeb) {
          final Uri base = Uri.base;
          final String path = base.path;
          final String frag = base.fragment;
          final String fragPath =
              frag.isEmpty ? '' : (frag.startsWith('/') ? frag : '/$frag');
          final bool urlIsAdmin =
              (path == AdminDashboardScreen.routeName) ||
              (fragPath == AdminDashboardScreen.routeName);
          if (urlIsAdmin &&
              isWhitelistedUid(FirebaseAuth.instance.currentUser?.uid)) {
            forceWideFromUrl = true;
          }
        }

        // If forced wide from URL, render wide with overlays.
        if (forceWideFromUrl) {
          adminIsWide.value = true;
          final List<Widget> overlays = [];
          if (kShowAdminFab &&
              isWhitelistedUid(FirebaseAuth.instance.currentUser?.uid)) {
            overlays.add(
              Positioned(
                right: 16,
                bottom: 16 + MediaQuery.of(context).viewPadding.bottom,
                child: FloatingActionButton.small(
                  heroTag: 'adminFab',
                  onPressed: () async {
                    if (kIsWeb) {
                      final bool usesHash =
                          Uri.base.fragment.isNotEmpty ||
                          Uri.base.toString().contains('#/');
                      final String url =
                          usesHash
                              ? '${Uri.base.origin}${Uri.base.path}#${AdminDashboardScreen.routeName}'
                              : Uri(
                                scheme: Uri.base.scheme,
                                host: Uri.base.host,
                                port: Uri.base.hasPort ? Uri.base.port : null,
                                path: AdminDashboardScreen.routeName,
                              ).toString();
                      await launchUrl(
                        Uri.parse(url),
                        webOnlyWindowName: '_blank',
                      );
                      return;
                    }
                    adminIsWide.value = true;
                    appNavigatorKey.currentState?.pushNamed(
                      AdminDashboardScreen.routeName,
                    );
                  },
                  child: const Icon(Icons.admin_panel_settings),
                ),
              ),
            );
          }

          if (kUseFirestoreEmu) {
            overlays.add(
              Positioned(
                right: 12,
                bottom: 12 + MediaQuery.of(context).viewPadding.bottom + 56,
                child: const _DevSeedButtons(),
              ),
            );
          }

          return overlays.isEmpty
              ? content
              : Stack(children: [content, ...overlays]);
        }

        return ValueListenableBuilder<bool>(
          valueListenable: adminIsWide,
          builder: (context, wide, _) {
            // Admin wide mode = true – skip phone frame.
            // Otherwise, force iPhone-XR frame on ALL web routes.
            final bool useXRFrame = kIsWeb && !wide;

            final Widget shell =
                useXRFrame
                    ? ScreenWrapper(
                      forceFrameOnWideWeb: true,
                      // iPhone XR logical size:
                      maxFrameSize: const Size(414, 896),
                      // Render smaller on desktop web to match DevTools-style preview.
                      desktopScale: 1.00,
                      // Optional, debug-only: route + effective size
                      onDebugTick: () {
                        if (kDebugMode) {
                          final rn =
                              ModalRoute.of(context)?.settings.name ??
                              '(unknown)';
                          debugPrint(
                            '[XR] useXRFrame=$useXRFrame adminWide=${adminIsWide.value} '
                            'route=$rn viewport=${MediaQuery.of(context).size}',
                          );
                        }
                      },
                      child: content,
                    )
                    : content;

            final List<Widget> overlays = [];

            if (kShowAdminFab &&
                isWhitelistedUid(FirebaseAuth.instance.currentUser?.uid)) {
              overlays.add(
                Positioned(
                  right: 16,
                  bottom: 16 + MediaQuery.of(context).viewPadding.bottom,
                  child: FloatingActionButton.small(
                    heroTag: 'adminFab',
                    onPressed: () async {
                      // Web: open Admin in a new tab/window (unconstrained).
                      if (kIsWeb) {
                        final bool usesHash =
                            Uri.base.fragment.isNotEmpty ||
                            Uri.base.toString().contains('#/');
                        final String url =
                            usesHash
                                ? '${Uri.base.origin}${Uri.base.path}#${AdminDashboardScreen.routeName}'
                                : Uri(
                                  scheme: Uri.base.scheme,
                                  host: Uri.base.host,
                                  port: Uri.base.hasPort ? Uri.base.port : null,
                                  path: AdminDashboardScreen.routeName,
                                ).toString();
                        await launchUrl(
                          Uri.parse(url),
                          webOnlyWindowName: '_blank',
                        );
                        return;
                      }
                      // Mobile/Desktop: normal in-app route (flip wide first).
                      adminIsWide.value = true;
                      appNavigatorKey.currentState?.pushNamed(
                        AdminDashboardScreen.routeName,
                      );
                    },
                    child: const Icon(Icons.admin_panel_settings),
                  ),
                ),
              );
            }

            if (kUseFirestoreEmu) {
              overlays.add(
                Positioned(
                  right: 12,
                  bottom: 12 + MediaQuery.of(context).viewPadding.bottom + 56,
                  child: const _DevSeedButtons(),
                ),
              );
            }

            if (overlays.isEmpty) return shell;
            return Stack(children: [shell, ...overlays]);
          },
        );
      },
    );
  }
}

////////////////////////////////////////////////////////////////////////////////
// DEV OVERLAY: Seed buttons (emulator-only)
////////////////////////////////////////////////////////////////////////////////

class _DevSeedButtons extends StatelessWidget {
  const _DevSeedButtons();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Seed Question (current user)
        FloatingActionButton.extended(
          heroTag: 'seed_question_fab',
          onPressed: () async {
            try {
              final id = await seedTodayQuestionCurrentUser();
              final navCtx = appNavigatorKey.currentContext;
              if (navCtx != null) {
                ScaffoldMessenger.of(navCtx).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Seeded question: $id',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              }
            } catch (e) {
              final navCtx = appNavigatorKey.currentContext;
              if (navCtx != null) {
                ScaffoldMessenger.of(
                  navCtx,
                ).showSnackBar(SnackBar(content: Text('Seed failed: $e')));
              }
            }
          },
          label: const Text('Seed Question'),
          icon: const Icon(Icons.help_center),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        const SizedBox(height: 12),
        // Seed Inbox swatch (self)
        FloatingActionButton.extended(
          heroTag: 'seed_inbox_fab',
          onPressed: () async {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            final navCtx = appNavigatorKey.currentContext;
            if (uid == null) {
              if (navCtx != null) {
                ScaffoldMessenger.of(navCtx).showSnackBar(
                  const SnackBar(content: Text('Sign in first to seed Inbox.')),
                );
              }
              return;
            }
            try {
              await seedSelfInboxTest();
              if (navCtx != null) {
                ScaffoldMessenger.of(navCtx).showSnackBar(
                  const SnackBar(content: Text('Seeded test swatch – Inbox')),
                );
              }
            } catch (e) {
              if (navCtx != null) {
                ScaffoldMessenger.of(
                  navCtx,
                ).showSnackBar(SnackBar(content: Text('Seed failed: $e')));
              }
            }
          },
          label: const Text('Seed Inbox'),
          icon: const Icon(Icons.inbox),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
      ],
    );
  }
}

////////////////////////////////////////////////////////////////////////////////
// DEEP LINK GATE: /answer/<id> fetch and forward
////////////////////////////////////////////////////////////////////////////////

class _AnswerLinkGate extends StatelessWidget {
  final String answerId;
  const _AnswerLinkGate({required this.answerId});

  @override
  Widget build(BuildContext context) {
    final repo = AnswerRepositoryFirestore(
      firestore: FirebaseFirestore.instance,
    );
    return FutureBuilder<Answer?>(
      future: repo.getAnswerById(answerId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final a = snap.data;
        if (a == null) {
          return const Scaffold(body: Center(child: Text('Swatch not found')));
        }
        return AnswerDetailsScreen(answer: a);
      },
    );
  }
}

/// Dev helper: create a self-sent Inbox swatch for the current user.
Future<void> seedSelfInboxTest() async {
  final me = FirebaseAuth.instance.currentUser?.uid;
  if (me == null) throw StateError('Sign in first');

  final repo = SwatchRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );

  await repo.saveSwatch(
    swatchData: {
      'color': 0xFF3366FF,
      'title': 'Test swatch',
      'senderName': 'Emulator',
      'message': 'hello from emu',
    },
    status: 'sent',
    recipientId: me,
  );

  debugPrint('[SEED] Created self-sent swatch to $me');
}

/// Seed one **Question** for **today** using the **current signed-in user**.
/// Returns the new document id.
Future<String> seedTodayQuestionCurrentUser() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw StateError('Sign in first');

  final db = FirebaseFirestore.instance;
  final day = DailyClock().localDay;

  final docRef = db.collection('questions').doc(); // auto id
  final data = <String, dynamic>{
    'authorId': uid,
    'text': 'Demo: what color do you feel today?',
    'createdAt': Timestamp.now(), // rules require timestamp
    'localDay': day,
    'status': 'active',
    'visibility': 'all',
    'answersCount': 0,
  };

  await docRef.set(data, SetOptions(merge: false));

  // Verify from server (not cache)
  final snap = await docRef.get(const GetOptions(source: Source.server));
  debugPrint('[SEED] question exists=${snap.exists} id=${docRef.id} day=$day');
  if (!snap.exists) {
    throw StateError('Question not found on server; check rules/emulator.');
  }
  return docRef.id;
}
