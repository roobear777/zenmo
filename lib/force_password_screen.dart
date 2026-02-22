import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'loading_screen.dart';

class ForcePasswordScreen extends StatefulWidget {
  const ForcePasswordScreen({super.key, this.email});
  final String? email; // optional; will fall back to currentUser.email

  @override
  State<ForcePasswordScreen> createState() => _ForcePasswordScreenState();
}

class _ForcePasswordScreenState extends State<ForcePasswordScreen> {
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _currentCtrl = TextEditingController();

  bool _needReauth = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _obscureCurrent = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    _currentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'No signed-in user found.');
      return;
    }

    final email = widget.email ?? user.email;
    if (email == null || email.isEmpty) {
      setState(() => _error = 'This account has no email address.');
      return;
    }

    final newPw = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    if (newPw.isEmpty || newPw.length < 8) {
      setState(() => _error = 'Please enter at least 8 characters.');
      return;
    }
    if (newPw != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      if (_needReauth) {
        final currentPw = _currentCtrl.text;
        if (currentPw.isEmpty) {
          throw FirebaseAuthException(
            code: 'missing-current-password',
            message: 'Please enter your current password to continue.',
          );
        }
        final cred = EmailAuthProvider.credential(
          email: email,
          password: currentPw,
        );
        await user.reauthenticateWithCredential(cred);
      }

      await user.updatePassword(newPw);

      // Clear BOTH flags (new + legacy) on success
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'pwResetRequired': false,
        'mustChangePassword': false,
        'passwordChangedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoadingScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        setState(() {
          _needReauth = true;
          _error = 'For security, please enter your current password.';
        });
      } else {
        setState(() => _error = e.message ?? 'Could not update password.');
      }
    } catch (e) {
      setState(() => _error = 'Could not update password: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_submitting;

    return WillPopScope(
      onWillPop: () async => false, // block system back
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Update Password'),
          automaticallyImplyLeading: false, // hide back arrow
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'We’ve migrated your account.\nPlease set a new password to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 24),

                    // New password
                    TextField(
                      controller: _newCtrl,
                      obscureText: _obscureNew,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        hintText: 'At least 8 characters',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureNew
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed:
                              () => setState(() => _obscureNew = !_obscureNew),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),

                    // Confirm
                    TextField(
                      controller: _confirmCtrl,
                      obscureText: _obscureConfirm,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Confirm new password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed:
                              () => setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              ),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),

                    // Current password (only if required)
                    if (_needReauth) ...[
                      TextField(
                        controller: _currentCtrl,
                        obscureText: _obscureCurrent,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Current password',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureCurrent
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed:
                                () => setState(
                                  () => _obscureCurrent = !_obscureCurrent,
                                ),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (_error != null) ...[
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                    ],

                    SizedBox(
                      width: 240,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: canSubmit ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5F6572),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          elevation: 0,
                        ),
                        child:
                            _submitting
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Text(
                                  'Save new password',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
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
