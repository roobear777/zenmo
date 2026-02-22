// lib/email_auth_screen.dart
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// for FirebaseException
import 'loading_screen.dart';
import 'services/user_identity_service.dart';

enum EmailAuthMode { signIn, signUp }

enum NameCheckState { idle, checking, available, taken, invalid }

class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key, required this.mode});
  final EmailAuthMode mode;

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _showPass = false;
  late EmailAuthMode _mode;

  // Live username check state
  Timer? _nameDebounce;
  NameCheckState _nameState = NameCheckState.idle;
  String? _nameMsg;

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _nameDebounce?.cancel();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter your email';
    if (!s.contains('@') || !s.contains('.')) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter your password';
    if (s.length < 6) return 'Minimum 6 characters';
    return null;
  }

  // Same policy used in backfill/service (2–20 chars, letters/digits/space/._-)
  static final RegExp _namePolicy = RegExp(r'^[a-zA-Z0-9._ \-]{2,20}$');

  String? _validateName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter a username';
    if (!_namePolicy.hasMatch(s)) {
      return '2–20 chars (letters, numbers, space, . _ -)';
    }
    return null;
  }

  // Flutter web sometimes wraps exceptions thrown inside JS<->Dart converted Futures
  // (e.g., from Firestore transactions) and prints a generic message.
  // This unwraps the underlying error when possible so the UI shows something useful.
  String _formatErrorMessage(Object e) {
    final s = e.toString();
    if (s.contains('Dart exception thrown from converted Future')) {
      try {
        final inner = (e as dynamic).error;
        if (inner != null) return inner.toString();
      } catch (_) {
        // ignore
      }
      return 'Something went wrong. Please try again.';
    }
    return s;
  }

  StackTrace? _tryGetConvertedFutureStack(Object e) {
    final s = e.toString();
    if (!s.contains('Dart exception thrown from converted Future')) return null;
    try {
      final innerStack = (e as dynamic).stack;
      if (innerStack is StackTrace) return innerStack;
      if (innerStack != null)
        return StackTrace.fromString(innerStack.toString());
    } catch (_) {
      // ignore
    }
    return null;
  }

  void _onNameChanged(String value) {
    // Debounce to avoid hammering Firestore
    _nameDebounce?.cancel();
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _nameState = NameCheckState.idle;
        _nameMsg = null;
      });
      return;
    }

    if (!_namePolicy.hasMatch(trimmed)) {
      setState(() {
        _nameState = NameCheckState.invalid;
        _nameMsg = '2–20 chars (letters, numbers, space, . _ -)';
      });
      return;
    }

    setState(() {
      _nameState = NameCheckState.checking;
      _nameMsg = 'Checking availability…';
    });

    _nameDebounce = Timer(const Duration(milliseconds: 400), () async {
      final lower = trimmed.toLowerCase();
      try {
        final snap =
            await FirebaseFirestore.instance
                .collection('usernames')
                .doc(lower)
                .get();
        if (!mounted) return;

        if (snap.exists) {
          // If claimed by current user (rare here), treat as available
          final owner = (snap.data()?['uid'] as String?) ?? '';
          final me = FirebaseAuth.instance.currentUser?.uid ?? '';
          final available = owner == me && me.isNotEmpty;
          setState(() {
            _nameState =
                available ? NameCheckState.available : NameCheckState.taken;
            _nameMsg =
                available
                    ? 'You already own this username'
                    : 'That username is taken';
          });
        } else {
          setState(() {
            _nameState = NameCheckState.available;
            _nameMsg = 'Username available';
          });
        }
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _nameState = NameCheckState.idle; // don’t block on transient errors
          _nameMsg = null;
        });
      }
    });
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk) return;

    final isSignUp = _mode == EmailAuthMode.signUp;

    // Optional: prevent submit when sign-up username is clearly invalid/taken
    if (isSignUp &&
        !(_nameState == NameCheckState.available ||
            _nameState == NameCheckState.idle)) {
      // idle is allowed to avoid false negatives if check failed due to network
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick an available username before continuing'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final auth = FirebaseAuth.instance;

    try {
      if (isSignUp) {
        final email = _emailCtrl.text.trim();
        final pass = _passCtrl.text.trim();
        final name = _nameCtrl.text.trim(); // username

        final cred = await auth.createUserWithEmailAndPassword(
          email: email,
          password: pass,
        );

        // Best-effort: set auth displayName
        try {
          await cred.user?.updateDisplayName(name);
          await cred.user?.reload();
        } catch (_) {
          // non-fatal
        }

        // Username claim transaction
        //
        // IMPORTANT (Flutter web): if a Firestore transaction throws inside its callback,
        // the error can surface as a generic "converted Future" wrapper.
        // We catch broadly here, unwrap the underlying error when possible, and then
        // verify whether the claim actually succeeded before deciding what to do.
        final String lower = name.toLowerCase();
        final String uid = cred.user?.uid ?? '';
        bool claimOk = false;
        try {
          await UserIdentityService().claimNameOnSignup(name);
          claimOk = true;
        } on StateError catch (e) {
          // Username policy / taken. Roll back so the user can try again cleanly.
          try {
            await cred.user?.delete();
            await auth.signOut();
          } catch (_) {}
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.message ?? 'That username is taken')),
            );
          }
          return;
        } on FirebaseException catch (e) {
          // Non-fatal: account exists. We'll verify claim below and continue to LoadingScreen.
          if (kDebugMode) {
            // ignore: avoid_print
            print(
              '[signup] claimNameOnSignup FirebaseException ${e.code}: ${e.message}',
            );
          }
        } catch (e, st) {
          // Non-fatal: unwrap web "converted Future" wrapper if present, then verify claim.
          final msg = _formatErrorMessage(e);
          if (kDebugMode) {
            // ignore: avoid_print
            print('[signup] claimNameOnSignup ERROR: $msg');
            final innerStack = _tryGetConvertedFutureStack(e);
            // ignore: avoid_print
            print(innerStack ?? st);
          }
        }

        // Verify whether the username ledger is owned by this uid (handles web wrapper cases).
        if (!claimOk && uid.isNotEmpty) {
          try {
            final snap =
                await FirebaseFirestore.instance
                    .collection('usernames')
                    .doc(lower)
                    .get();
            final owner = (snap.data()?['uid'] as String?) ?? '';
            claimOk = snap.exists && owner == uid;
          } catch (_) {
            // ignore
          }
        }

        if (!claimOk) {
          // Don't block signup on a transient setup failure; proceed to LoadingScreen.
          // (LoadingScreen/identity service can retry profile setup.)
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Account created. Finishing setup…'),
              ),
            );
          }
        }

        try {
          await cred.user?.sendEmailVerification();
        } catch (_) {}

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created. Welcome!')),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoadingScreen(initialName: name)),
        );
      } else {
        final email = _emailCtrl.text.trim();
        final pass = _passCtrl.text.trim();

        final cred = await auth.signInWithEmailAndPassword(
          email: email,
          password: pass,
        );

        final name = cred.user?.displayName;

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoadingScreen(initialName: name)),
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Authentication error';
      switch (e.code) {
        case 'user-not-found':
          msg = 'No user found with that email';
          break;
        case 'wrong-password':
          msg = 'Incorrect password';
          break;
        case 'email-already-in-use':
          msg = 'That email is already in use';
          break;
        case 'invalid-email':
          msg = 'Invalid email';
          break;
        case 'weak-password':
          msg = 'Password is too weak (min 6 characters)';
          break;
        default:
          msg = e.message ?? msg;
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } on StateError catch (e) {
      // Catch any StateError that escaped the inner try
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Something went wrong')),
        );
      }
    } catch (e, st) {
      final msg = _formatErrorMessage(e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Something went wrong: $msg')));
      }
      if (kDebugMode) {
        final innerStack = _tryGetConvertedFutureStack(e);
        // ignore: avoid_print
        print(innerStack ?? st);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _mode =
          _mode == EmailAuthMode.signIn
              ? EmailAuthMode.signUp
              : EmailAuthMode.signIn;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = _mode == EmailAuthMode.signUp;

    Icon? nameIcon;
    Color? nameColor;
    if (isSignUp) {
      switch (_nameState) {
        case NameCheckState.checking:
          nameIcon = null; // show spinner in suffix
          nameColor = Colors.grey[700];
          break;
        case NameCheckState.available:
          nameIcon = const Icon(
            Icons.check_circle,
            size: 18,
            color: Colors.green,
          );
          nameColor = Colors.green;
          break;
        case NameCheckState.taken:
          nameIcon = const Icon(Icons.cancel, size: 18, color: Colors.red);
          nameColor = Colors.red;
          break;
        case NameCheckState.invalid:
          nameIcon = const Icon(
            Icons.error_outline,
            size: 18,
            color: Colors.orange,
          );
          nameColor = Colors.orange;
          break;
        case NameCheckState.idle:
          nameIcon = null;
          nameColor = null;
          break;
      }
    }

    final canSubmit =
        !_busy &&
        (!isSignUp ||
            _nameState == NameCheckState.available ||
            _nameState == NameCheckState.idle);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(isSignUp ? 'Create account' : 'Sign in'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Colors.black12),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints:
                kIsWeb
                    ? const BoxConstraints()
                    : const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    if (isSignUp) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Username',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[800],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameCtrl,
                        textInputAction: TextInputAction.next,
                        validator: _validateName,
                        onChanged: _onNameChanged,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon:
                              _nameState == NameCheckState.checking
                                  ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                  : nameIcon,
                        ),
                      ),
                      if (_nameMsg != null) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _nameMsg!,
                            style: TextStyle(
                              fontSize: 12,
                              color: nameColor ?? Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Email',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[800],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: _validateEmail,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Password',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[800],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: !_showPass,
                      textInputAction: TextInputAction.done,
                      validator: _validatePassword,
                      onFieldSubmitted: (_) => canSubmit ? _submit() : null,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          tooltip:
                              _showPass ? 'Hide password' : 'Show password',
                          icon: Icon(
                            _showPass ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed:
                              () => setState(() => _showPass = !_showPass),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: canSubmit ? _submit : null,
                        child:
                            _busy
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : Text(isSignUp ? 'Create account' : 'Sign in'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: _busy ? null : _toggleMode,
                      child: Text(
                        isSignUp
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
