import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/network/api_exception.dart';

class AuthFailure extends AppException {
  const AuthFailure(super.message);
}

/// Wraps Firebase Auth + Google / Apple providers. Methods return `null` when
/// the user cancels a provider flow and throw [AuthFailure] on errors.
class AuthRepository {
  AuthRepository();

  // Resolved lazily: Firebase is initialised by the splash screen.
  FirebaseAuth get _auth => FirebaseAuth.instance;

  final GoogleSignIn _google = GoogleSignIn(scopes: const ['email', 'profile']);

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final account = await _google.signIn();
      if (account == null) return null; // cancelled
      final auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageFor(e));
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_canceled') return null;
      throw AuthFailure(
        e.code == 'network_error'
            ? 'Network error. Check your connection and try again.'
            : 'Google sign-in failed. Please try again.',
      );
    }
  }

  Future<UserCredential?> signInWithApple() async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    try {
      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final idToken = apple.identityToken;
      if (idToken == null) {
        throw const AuthFailure('Apple sign-in did not return an identity token.');
      }
      final credential = OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
        accessToken: apple.authorizationCode,
      );
      final result = await _auth.signInWithCredential(credential);

      // Apple only shares the name on the very first sign-in.
      final user = result.user;
      final fullName = [apple.givenName, apple.familyName]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(' ');
      if (user != null &&
          (user.displayName == null || user.displayName!.isEmpty) &&
          fullName.isNotEmpty) {
        await user.updateDisplayName(fullName);
      }
      return result;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw AuthFailure('Apple sign-in failed: ${e.message}');
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageFor(e));
    }
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageFor(e));
    }
  }

  Future<UserCredential> registerWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (name.trim().isNotEmpty) {
        await result.user?.updateDisplayName(name.trim());
        await result.user?.reload();
      }
      return result;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageFor(e));
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageFor(e));
    }
  }

  Future<void> signOut() async {
    try {
      if (await _google.isSignedIn()) {
        await _google.signOut();
      }
    } catch (_) {
      // Google session cleanup is best-effort.
    }
    await _auth.signOut();
  }

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  static String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists for that email. Try signing in.';
      case 'weak-password':
        return 'Please choose a stronger password (at least 6 characters).';
      case 'account-exists-with-different-credential':
        return 'An account already exists with a different sign-in method.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}
