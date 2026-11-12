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

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasMapbox => mapboxPublicToken.isNotEmpty;
}
