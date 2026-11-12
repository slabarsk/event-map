/// Derleme zamanı ayarları: `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
/// Anahtarlar verilmezse uygulama cihazda saklanan demo auth ile çalışır.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
