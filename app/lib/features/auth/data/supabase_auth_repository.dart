import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_user.dart';
import 'auth_repository.dart';

/// Supabase Auth + `profiles` tablosu (bkz. supabase/migrations).
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, this._prefs) {
    _sub = _client.auth.onAuthStateChange.listen((state) async {
      final session = state.session;
      if (session == null) {
        _controller.add(null);
        return;
      }
      try {
        _controller.add(await _loadProfile(session.user));
      } catch (e) {
        debugPrint('Profil yüklenemedi: $e');
      }
    });
  }

  final SupabaseClient _client;
  final SharedPreferences _prefs;
  final _controller = StreamController<AppUser?>.broadcast();
  // ignore: unused_field
  late final StreamSubscription<AuthState> _sub;

  /// Google yönlendirmesi sayfayı yeniden yükleyebildiği için seçilen rol saklanır.
  static const _pendingRoleKey = 'auth.pending_oauth_role';

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;

  @override
  Future<AppUser?> currentUser() async {
    final user = _client.auth.currentUser;
    return user == null ? null : _loadProfile(user);
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final res = await _guard(
      () => _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      ),
    );
    final user = await _loadProfile(res.user!);
    if (user.role != role) {
      await _client.auth.signOut();
      throw AuthFailure(
        user.isOrganizer
            ? 'Bu bir organizatör hesabı. Organizatör girişini kullan.'
            : 'Bu hesap organizatör değil. Kullanıcı girişini kullan.',
      );
    }
    return user;
  }

  @override
  Future<AppUser> signUp({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    String? organizationName,
  }) async {
    final res = await _guard(
      () => _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': fullName.trim(),
          'role': role.name,
          if (organizationName != null) 'org_name': organizationName.trim(),
          'kvkk_consent_at': DateTime.now().toUtc().toIso8601String(),
        },
      ),
    );
    if (res.session == null) {
      throw const AuthFailure(
        'Hesabın oluşturuldu. E-postana gelen bağlantıyla doğrulayıp giriş yap.',
      );
    }
    return _loadProfile(res.user!);
  }

  @override
  Future<AppUser?> signInWithGoogle({required UserRole role}) async {
    await _prefs.setString(_pendingRoleKey, role.name);
    await _guard(
      () => _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb
            ? Uri.base.origin
            : 'com.eventmap.app://login-callback',
      ),
    );
    return null;
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _client.auth.resetPasswordForEmail(email.trim()));

  @override
  Future<AppUser> updateProfile(AppUser user) async {
    await _guard(
      () => _client
          .from('profiles')
          .update({
            'full_name': user.fullName,
            'onboarding_completed': user.onboardingCompleted,
            'preferences': user.preferences.toJson(),
            'organization': user.organization?.toJson(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', user.id),
    );
    if (user.kvkkConsentAt != null) {
      await _guard(() => _client.rpc('record_kvkk_consent'));
    }
    final fresh = await _loadProfile(_client.auth.currentUser!);
    _controller.add(fresh);
    return fresh;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> deleteAccount() async {
    await _guard(() => _client.functions.invoke('delete-account'));
    await _client.auth.signOut();
  }

  Future<AppUser> _loadProfile(User authUser) async {
    final pendingRole = _prefs.getString(_pendingRoleKey);
    if (pendingRole != null) {
      await _prefs.remove(_pendingRoleKey);
      // Google ile organizatör olarak ilk kez gelen hesap; SQL tarafı yalnızca
      // onboarding bitmemiş 'user' hesabını yükseltir.
      if (pendingRole == UserRole.organizer.name) {
        await _client.rpc(
          'request_organizer_role',
          params: {'org_name': authUser.userMetadata?['full_name'] ?? ''},
        );
      }
    }
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', authUser.id)
        .single();
    return AppUser.fromProfileJson(row, email: authUser.email ?? '');
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException catch (e) {
      throw AuthFailure(_translate(e));
    } on PostgrestException catch (e) {
      throw AuthFailure('Sunucu hatası: ${e.message}');
    } on FunctionException catch (_) {
      throw const AuthFailure('İşlem tamamlanamadı, biraz sonra tekrar dene.');
    }
  }

  static String _translate(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login')) return 'E-posta veya şifre hatalı.';
    if (msg.contains('already registered')) {
      return 'Bu e-posta ile zaten bir hesap var. Giriş yapmayı dene.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Önce e-postanı doğrulaman gerekiyor.';
    }
    if (msg.contains('password')) return 'Şifre en az 8 karakter olmalı.';
    return e.message;
  }
}
