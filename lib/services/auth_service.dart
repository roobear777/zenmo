import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Wraps FirebaseAuth for anonymous sign-in and email/password admin login.
class AuthService {
  static const _kAdminUid1 = 'OpWxbjKjOuYSLopBew8uHQlMY1F2';
  static const _kAdminUid2 = 'qjvsPsCL9uZS6ba3x4cqJPWXaSb2';

  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// The currently signed-in user, or null.
  User? get currentUser => _auth.currentUser;

  /// True only for the two whitelisted admin UIDs.
  bool get isWhitelisted {
    final uid = currentUser?.uid;
    return uid == _kAdminUid1 || uid == _kAdminUid2;
  }

  /// Signs in anonymously if no session exists. Errors are swallowed.
  Future<void> ensureAnonymousSignIn() async {
    if (_auth.currentUser != null) return;
    try {
      await _auth.signInAnonymously();
    } catch (e) {
      debugPrint('AuthService: anonymous sign-in failed: $e');
    }
  }

  /// Signs in with email and password. Throws [FirebaseAuthException] on failure.
  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }
}
