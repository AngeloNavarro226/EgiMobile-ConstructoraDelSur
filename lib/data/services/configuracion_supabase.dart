/// Configuración de conexión a Supabase inyectada por tiempo de compilación
/// mediante `--dart-define` o `--dart-define-from-file=.env.json`.
///
/// Nunca hardcodea URLs ni claves en el código fuente versionado.
class ConfiguracionSupabase {
  const ConfiguracionSupabase({
    required this.url,
    required this.publishableKey,
  });

  /// Lee las variables definidas en compilación (`SUPABASE_URL`,
  /// `SUPABASE_PUBLISHABLE_KEY` o la clave legacy `SUPABASE_ANON_KEY`).
  factory ConfiguracionSupabase.desdeEntorno() {
    const urlEnv = String.fromEnvironment('SUPABASE_URL');
    const publishableEnv = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    const anonLegacyEnv = String.fromEnvironment('SUPABASE_ANON_KEY');

    return ConfiguracionSupabase(
      url: urlEnv.trim(),
      publishableKey: publishableEnv.trim().isNotEmpty
          ? publishableEnv.trim()
          : anonLegacyEnv.trim(),
    );
  }

  final String url;
  final String publishableKey;

  /// Indica si se proporcionaron tanto la URL como la clave pública.
  bool get estaConfigurado => url.isNotEmpty && publishableKey.isNotEmpty;
}
