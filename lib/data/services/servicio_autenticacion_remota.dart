import 'package:supabase_flutter/supabase_flutter.dart';

/// Contrato remoto para desacoplar [AutenticacionRepository] del proveedor
/// concreto de autenticación (Supabase Auth en producción, Fake en tests).
abstract interface class ServicioAutenticacionRemota {
  /// Indica si la autenticación remota está configurada y habilitada.
  bool get estaDisponible;

  /// Identificador (`auth.users.id`) de la sesión persistida actualmente, si existe.
  String? get usuarioAuthIdActual;

  /// Autentica con correo y contraseña y devuelve el perfil de `public.usuarios`
  /// enriquecido con `rol_codigo` y `rol_nombre`, o `null` si las credenciales
  /// son inválidas.
  Future<Map<String, dynamic>?> iniciarSesion({
    required String email,
    required String password,
  });

  /// Descarga el perfil actualizado del usuario autenticado desde el servidor.
  /// Devuelve `null` si no hay sesión o no hay conectividad (permite fallback
  /// offline al perfil cacheado en SQLite).
  Future<Map<String, dynamic>?> obtenerPerfilActual();

  /// Actualiza la contraseña en Supabase Auth cuando hay conectividad.
  Future<void> actualizarContrasenia(String nuevaContrasenia);

  /// Cierra la sesión remota y limpia los tokens persistidos en el dispositivo.
  Future<void> cerrarSesion();
}

/// Implementación local/offline cuando Supabase no está configurado.
class ServicioAutenticacionRemotaOffline
    implements ServicioAutenticacionRemota {
  const ServicioAutenticacionRemotaOffline();

  @override
  bool get estaDisponible => false;

  @override
  String? get usuarioAuthIdActual => null;

  @override
  Future<Map<String, dynamic>?> iniciarSesion({
    required String email,
    required String password,
  }) async =>
      null;

  @override
  Future<Map<String, dynamic>?> obtenerPerfilActual() async => null;

  @override
  Future<void> actualizarContrasenia(String nuevaContrasenia) async {}

  @override
  Future<void> cerrarSesion() async {}
}

/// Implementación real sobre `supabase_flutter` (Supabase Auth + `public.usuarios`).
class SupabaseAuthService implements ServicioAutenticacionRemota {
  SupabaseAuthService({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  @override
  bool get estaDisponible => true;

  @override
  String? get usuarioAuthIdActual => _client.auth.currentSession?.user.id;

  @override
  Future<Map<String, dynamic>?> iniciarSesion({
    required String email,
    required String password,
  }) async {
    try {
      final respuesta = await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = respuesta.user;
      if (user == null) return null;

      return await _consultarPerfilPorAuthId(user.id);
    } on AuthException catch (e) {
      final mensaje = e.message.toLowerCase();
      if (mensaje.contains('invalid login credentials') ||
          e.statusCode == '400') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>?> obtenerPerfilActual() async {
    final authUserId = usuarioAuthIdActual;
    if (authUserId == null) return null;
    try {
      return await _consultarPerfilPorAuthId(authUserId);
    } catch (_) {
      // Sin conectividad: el repositorio usará el perfil cacheado en SQLite.
      return null;
    }
  }

  @override
  Future<void> actualizarContrasenia(String nuevaContrasenia) async {
    if (_client.auth.currentSession == null) return;
    if (nuevaContrasenia.trim().length < 6) return;
    await _client.auth.updateUser(
      UserAttributes(password: nuevaContrasenia.trim()),
    );
  }

  @override
  Future<void> cerrarSesion() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Incluso sin conexión, signOut limpia la sesión local en el dispositivo.
    }
  }

  Future<Map<String, dynamic>?> _consultarPerfilPorAuthId(
    String authUserId,
  ) async {
    final fila = await _client
        .from('usuarios')
        .select(
          'id, auth_user_id, username, rol_id, nombre, telefono, updated_at, '
          'roles(codigo, nombre)',
        )
        .or('auth_user_id.eq.$authUserId,id.eq.$authUserId')
        .maybeSingle();

    if (fila == null) return null;
    return mapearPerfilSupabaseALocal(fila);
  }
}

/// Normaliza una fila de `public.usuarios` (con relación `roles`) al formato
/// esperado por `BaseDatosLocalService` y `Usuario.fromMap`.
Map<String, dynamic> mapearPerfilSupabaseALocal(Map<String, dynamic> fila) {
  final rolData = fila['roles'] as Map<String, dynamic>?;
  return {
    'id': fila['id'] as String,
    'username': fila['username'] as String,
    'rol_id': fila['rol_id'] as String,
    'nombre': fila['nombre'] as String,
    'contrasenia': '',
    'telefono': (fila['telefono'] as String?) ?? '',
    'updated_at': fila['updated_at'] as String?,
    'sync_status': 'synced',
    if (rolData != null) ...{
      'rol_codigo': rolData['codigo'] as String?,
      'rol_nombre': rolData['nombre'] as String?,
    },
  };
}
