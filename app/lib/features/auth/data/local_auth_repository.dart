import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_user.dart';
import 'auth_repository.dart';

/// Supabase anahtarları verilmediğinde kullanılan, cihazda saklanan demo
/// auth'u. Yalnızca geliştirme içindir; gerçek kullanıcı verisi tutmaz.
class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository(this._prefs);

  final SharedPreferences _prefs;
  final _controller = StreamController<AppUser?>.broadcast();

  static const _accountsKey = 'demo_auth.accounts';
  static const _sessionKey = 'demo_auth.session';
  static const _latency = Duration(milliseconds: 450);

  Map<String, dynamic> _accounts() =>
      jsonDecode(_prefs.getString(_accountsKey) ?? '{}')
          as Map<String, dynamic>;

  Future<void> _saveAccounts(Map<String, dynamic> accounts) =>
      _prefs.setString(_accountsKey, jsonEncode(accounts));

  String _hash(String email, String password) =>
      sha256.convert(utf8.encode('$email:$password')).toString();

  AppUser _userFrom(String email, Map<String, dynamic> account) =>
      AppUser.fromProfileJson(
        account['profile'] as Map<String, dynamic>,
        email: email,
      );

  Future<AppUser> _startSession(String email) async {
    await _prefs.setString(_sessionKey, email);
    final user = _userFrom(email, _accounts()[email] as Map<String, dynamic>);
    _controller.add(user);
    return user;
  }

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;

  @override
  Future<AppUser?> currentUser() async {
    final email = _prefs.getString(_sessionKey);
    if (email == null) return null;
    final account = _accounts()[email] as Map<String, dynamic>?;
    return account == null ? null : _userFrom(email, account);
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    await Future<void>.delayed(_latency);
    final key = email.trim().toLowerCase();
    final account = _accounts()[key] as Map<String, dynamic>?;
    if (account == null || account['password'] != _hash(key, password)) {
      throw const AuthFailure('E-posta veya şifre hatalı.');
    }
    _ensureRole(_userFrom(key, account), role);
    return _startSession(key);
  }

  @override
  Future<AppUser> signUp({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    String? organizationName,
  }) async {
    await Future<void>.delayed(_latency);
    final key = email.trim().toLowerCase();
    final accounts = _accounts();
    if (accounts.containsKey(key)) {
      throw const AuthFailure(
        'Bu e-posta ile zaten bir hesap var. Giriş yapmayı dene.',
      );
    }
    final user = AppUser(
      id: _randomId(),
      email: key,
      fullName: fullName.trim(),
      role: role,
      organizerStatus: role == UserRole.organizer
          ? OrganizerStatus.pending
          : null,
      organization: role == UserRole.organizer
          ? Organization(name: organizationName?.trim() ?? '')
          : null,
      kvkkConsentAt: DateTime.now(),
    );
    accounts[key] = {
      'password': _hash(key, password),
      'profile': user.toProfileJson(),
    };
    await _saveAccounts(accounts);
    return _startSession(key);
  }

  @override
  Future<AppUser?> signInWithGoogle({required UserRole role}) async {
    // Demo modunda Google hesabı taklit edilir; gerçek OAuth Supabase ile çalışır.
    final email = role == UserRole.organizer
        ? 'demo.organizator@gmail.com'
        : 'demo.kullanici@gmail.com';
    final accounts = _accounts();
    if (!accounts.containsKey(email)) {
      return signUp(
        fullName: role == UserRole.organizer
            ? 'Demo Organizatör'
            : 'Demo Kullanıcı',
        email: email,
        password: _randomId(),
        role: role,
        organizationName: role == UserRole.organizer ? 'Demo Sahne' : null,
      );
    }
    await Future<void>.delayed(_latency);
    _ensureRole(
      _userFrom(email, accounts[email] as Map<String, dynamic>),
      role,
    );
    return _startSession(email);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await Future<void>.delayed(_latency);
  }

  @override
  Future<AppUser> updateProfile(AppUser user) async {
    final accounts = _accounts();
    final account = accounts[user.email] as Map<String, dynamic>?;
    if (account == null) {
      throw const AuthFailure('Oturum bulunamadı, tekrar giriş yap.');
    }
    account['profile'] = user.toProfileJson();
    await _saveAccounts(accounts);
    _controller.add(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    await _prefs.remove(_sessionKey);
    _controller.add(null);
  }

  @override
  Future<void> deleteAccount() async {
    final email = _prefs.getString(_sessionKey);
    if (email != null) {
      final accounts = _accounts()..remove(email);
      await _saveAccounts(accounts);
    }
    await signOut();
  }

  void _ensureRole(AppUser user, UserRole expected) {
    if (user.role == expected) return;
    throw AuthFailure(
      user.isOrganizer
          ? 'Bu bir organizatör hesabı. Organizatör girişini kullan.'
          : 'Bu hesap organizatör değil. Kullanıcı girişini kullan.',
    );
  }

  static String _randomId() {
    final rand = Random.secure();
    return List.generate(
      16,
      (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
