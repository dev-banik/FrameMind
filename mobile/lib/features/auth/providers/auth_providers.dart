import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap.dart';
import '../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

/// Firebase auth state. Stays loading until bootstrap finished, because
/// FirebaseAuth can't be touched before `Firebase.initializeApp()`.
final authStateProvider = StreamProvider<User?>((ref) {
  final ready = ref.watch(isBootstrappedProvider);
  if (!ready) return const Stream<User?>.empty();
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// UID of the signed-in user. User-scoped providers watch this so their data
/// is discarded when the account changes.
final currentUidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).valueOrNull?.uid,
);
