import '../domain/app_user.dart';

/// Ekranlarda doğrudan gösterilebilen, Türkçe mesajlı auth hatası.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Giriş ekranının rolü ile hesabın rolü uyuşmadığında gösterilecek mesaj.
String roleMismatchMessage(AppUser user, UserRole expected) {
  if (expected == UserRole.admin) {
    return 'Bu hesabın yönetim paneline erişim yetkisi yok.';
  }
  if (user.isAdmin) {
    return 'Bu bir admin hesabı. Yönetim paneli girişini (/admin) kullan.';
  }
  return user.isOrganizer
      ? 'Bu bir organizatör hesabı. Organizatör girişini kullan.'
      : 'Bu hesap organizatör değil. Kullanıcı girişini kullan.';
}

abstract class AuthRepository {
  /// Oturum değiştiğinde (giriş, çıkış, profil güncellemesi) yeni değeri yayar.
  Stream<AppUser?> authStateChanges();

  Future<AppUser?> currentUser();

  /// [role] kullanıcının hangi giriş ekranını kullandığıdır. Hesabın rolü
  /// farklıysa [AuthFailure] fırlatılır.
  Future<AppUser> signIn({
    required String email,
    required String password,
    required UserRole role,
  });

  Future<AppUser> signUp({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    String? organizationName,
  });

  /// Google ile giriş. Web'de sayfa yönlendirmesiyle tamamlanabilir; bu
  /// durumda sonuç [authStateChanges] üzerinden gelir ve null döner.
  Future<AppUser?> signInWithGoogle({required UserRole role});

  Future<void> sendPasswordReset(String email);

  Future<AppUser> updateProfile(AppUser user);

  Future<void> signOut();

  /// Hesabı ve profili kalıcı olarak siler (KVKK).
  Future<void> deleteAccount();
}
