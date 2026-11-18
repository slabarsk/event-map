/// Derleme zamanı ayarları: `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
/// Anahtarlar verilmezse uygulama cihazda saklanan demo auth ile çalışır.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Harita tile'ları için Mapbox public token (`pk.`). Verilmezse geliştirme
  /// sırasında OpenStreetMap tile'ları kullanılır.
  static const mapboxPublicToken = String.fromEnvironment(
    'MAPBOX_PUBLIC_TOKEN',
  );

  /// `--dart-define=ADMIN_ONLY=true`: yalnızca yönetim paneli derlemesi
  /// (GitHub Pages). Tüm rotalar panele gider; admin olmayan oturum kapatılır.
  static const adminOnly = bool.fromEnvironment('ADMIN_ONLY');

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasMapbox => mapboxPublicToken.isNotEmpty;
}
