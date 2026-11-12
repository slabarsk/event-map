import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../domain/app_user.dart';

/// main.dart içinde Supabase ya da demo repository ile override edilir.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw UnimplementedError('authRepositoryProvider override edilmedi'),
);

/// Oturumdaki kullanıcı. null = giriş yapılmamış.
final authControllerProvider = AsyncNotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AppUser?> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<AppUser?> build() async {
    final sub = _repo.authStateChanges().listen(
      (user) => state = AsyncData(user),
    );
    ref.onDispose(sub.cancel);
    return _repo.currentUser();
  }

  Future<void> signIn(String email, String password, UserRole role) async {
    state = AsyncData(
      await _repo.signIn(email: email, password: password, role: role),
    );
  }

  Future<void> signUp({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    String? organizationName,
  }) async {
    state = AsyncData(
      await _repo.signUp(
        fullName: fullName,
        email: email,
        password: password,
        role: role,
        organizationName: organizationName,
      ),
    );
  }

  Future<void> signInWithGoogle(UserRole role) async {
    final user = await _repo.signInWithGoogle(role: role);
    if (user != null) state = AsyncData(user);
  }

  Future<void> sendPasswordReset(String email) =>
      _repo.sendPasswordReset(email);

  Future<void> save(AppUser user) async {
    state = AsyncData(await _repo.updateProfile(user));
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AsyncData(null);
  }

  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    state = const AsyncData(null);
  }
}
