import 'package:material_ui/material_ui.dart';

import '../../features/auth/domain/app_user.dart';

abstract final class AppColors {
  static const ink = Color(0xFF1E1A24);
  static const inkSoft = Color(0xFF6B6475);
  static const inkFaint = Color(0xFFA39DAB);

  /// Pembe-lila uçuk zemin.
  static const background = Color(0xFFF8EFF3);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFEDE2E8);

  /// Buzlu cam kartların dolgusu.
  static Color glass([double alpha = 0.62]) =>
      Colors.white.withValues(alpha: alpha);

  /// Normal kullanıcı akışının ana rengi: mercan.
  static const coral = Color(0xFFF0654E);
  static const coralDeep = Color(0xFFDD4D3A);
  static const coralSoft = Color(0xFFFDE5DF);

  /// Organizatör akışının ana rengi: mürdüm.
  static const plum = Color(0xFF7B4FD8);
  static const plumDeep = Color(0xFF6239C2);
  static const plumSoft = Color(0xFFEDE5FB);

  /// Arka plan lekeleri.
  static const rose = Color(0xFFF2A3C0);
  static const lilac = Color(0xFFC7B6F0);
  static const peach = Color(0xFFFFC7A6);

  // Kategori renkleri
  static const violet = Color(0xFF7B5CF0);
  static const amber = Color(0xFFF6A723);
  static const pink = Color(0xFFE85C9C);
  static const sky = Color(0xFF3B9EF5);
  static const lime = Color(0xFF5DB047);
  static const teal = Color(0xFF119D8C);

  static const error = Color(0xFFD93A3A);
  static const success = Color(0xFF1F9D57);

  static Color accentFor(UserRole role) =>
      role == UserRole.organizer ? plum : coral;
  static Color accentDeepFor(UserRole role) =>
      role == UserRole.organizer ? plumDeep : coralDeep;
  static Color accentSoftFor(UserRole role) =>
      role == UserRole.organizer ? plumSoft : coralSoft;

  /// Butonlar ve vurgular için degrade.
  static LinearGradient gradientFor(UserRole role) => role == UserRole.organizer
      ? const LinearGradient(colors: [Color(0xFF9466F0), plumDeep])
      : const LinearGradient(colors: [Color(0xFFF7836A), coralDeep]);

  /// Arka plan lekeleri; role göre ton değişir.
  static List<Color> blobsFor(UserRole role) => role == UserRole.organizer
      ? const [lilac, rose, plum]
      : const [rose, peach, lilac];
}
