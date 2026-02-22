import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/user_identity_service.dart';
import '../services/identity_utils.dart'; // ← added
import 'email_auth_screen.dart'; // optional
import 'loading_screen.dart'; // zero-delay name handoff

class LoginScreen extends StatefulWidget {
  final void Function(String displayName) onLogin;

  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final List<String> users = [
    'frankie',
    'roo',
    'zina',
    'alan',
    'manuel',
    'guest',
  ];

  String? selectedUser;
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  String? error;
  bool showPassword = false;

  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;
  final UserIdentityService _userService = UserIdentityService();

  String _labelFor(String user) =>
      (user == 'guest')
          ? 'Guest'
          : '${user[0].toUpperCase()}${user.substring(1)}';

  String _emailFor(String user) =>
      (user == 'guest') ? 'guest@zenmo.app' : '$user@zenmo.app';

  Future<void> _persistDisplayName(String displayName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zenmo_display_name', displayName);
  }

  Future<void> _ensureUserProfile(User user, String displayName) async {
    if ((user.displayName ?? '').trim().isEmpty ||
        user.displayName != displayName) {
      await user.updateDisplayName(displayName);
    }
    await _fs.collection('users').doc(user.uid).set({
      'displayName': displayName,
      'email': user.email ?? '',
      'lastActive': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _setTesterFlags({required bool isTester}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('zenmo_is_tester', isTester);
    // When entering via tester picker, we explicitly mark as *not migrated*.
    if (isTester) {
      await prefs.setBool('zenmo_migrated', false);
    }
  }

  Future<void> _attemptLogin() async {
    if (selectedUser == null ||
        (passwordController.text.isEmpty && selectedUser != 'guest')) {
      setState(() => error = "Select a name and enter a password.");
      return;
    }

    setState(() {
      isLoading = true;
      error = null;
    });

    final isGuest = selectedUser == 'guest';
    final email = _emailFor(selectedUser!).trim().toLowerCase();
    final password = isGuest ? 'guest123' : passwordController.text.trim();
    final displayName = isGuest ? 'Guest User' : _labelFor(selectedUser!);

    // 🔎 mark testers so LoadingScreen / app flow can prompt migration later
    final isTester =
        isGuest ||
        ['frankie', 'roo', 'zina', 'alan', 'manuel'].contains(selectedUser);
    await _setTesterFlags(isTester: isTester);

    try {
      UserCredential cred;

      try {
        cred = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        // In DEBUG only, auto-create missing tester accounts to speed local/dev testing.
        if (e.code == 'user-not-found' && kDebugMode) {
          cred = await _auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } else {
          rethrow;
        }
      }

      final user = cred.user!;
      await _ensureUserProfile(user, displayName);
      await _persistDisplayName(displayName);

      // ▼ refresh linked-UID caches so queries reflect this session immediately
      IdentityUtils.invalidateLinkedCache();

      if (!mounted) return;

      // Optional callback for analytics/state.
      widget.onLogin(displayName);

      // 🚀 zero-delay handoff to loading screen with known name.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LoadingScreen(initialName: displayName),
        ),
      );
      return;
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
          msg = "Incorrect email or password.";
          break;
        case 'invalid-email':
          msg = "That email format looks wrong.";
          break;
        case 'too-many-requests':
          msg = "Too many attempts. Try again later.";
          break;
        default:
          msg = "Login failed: ${e.message ?? e.code}";
      }
      setState(() => error = msg);
    } catch (e) {
      setState(() => error = "Unexpected error. Please try again.");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    passwordController.dispose();
    super.dispose();
  }

  void _openEmailAuthSignIn() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const EmailAuthScreen(mode: EmailAuthMode.signIn),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text("Zenmo Login")),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 40,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Select your name:",
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 6),

                    ...users.map((user) {
                      return RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_labelFor(user)),
                        value: user,
                        groupValue: selectedUser,
                        onChanged:
                            (val) => setState(() {
                              selectedUser = val;
                              error = null;
                            }),
                      );
                    }),

                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: !showPassword,
                      decoration: InputDecoration(
                        labelText: "Password",
                        border: const OutlineInputBorder(),
                        helperText:
                            selectedUser == 'guest'
                                ? "Guest password defaults to 'guest123' (field disabled)"
                                : null,
                        suffixIcon: IconButton(
                          icon: Icon(
                            showPassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed:
                              () =>
                                  setState(() => showPassword = !showPassword),
                        ),
                      ),
                      enabled: selectedUser != 'guest',
                    ),

                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(error!, style: const TextStyle(color: Colors.red)),
                    ],

                    const Spacer(),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _attemptLogin,
                        child:
                            isLoading
                                ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                                : const Text("Login"),
                      ),
                    ),
                    const SizedBox(height: 8),

                    TextButton(
                      onPressed: isLoading ? null : _openEmailAuthSignIn,
                      child: const Text("Use email instead"),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
