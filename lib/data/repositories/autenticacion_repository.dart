import '../../domain/models/usuario.dart';
import '../services/base_datos_local_service.dart';

/// Fuente de verdad para la autenticación y la gestión de los perfiles
/// almacenados en SQLite.
class AutenticacionRepository {
  AutenticacionRepository({required BaseDatosLocalService baseDatosService})
      : _baseDatosService = baseDatosService;

  final BaseDatosLocalService _baseDatosService;

  List<Usuario>? _cacheUsuarios;
  Usuario? _usuarioActual;

  /// Usuario que tiene la sesión iniciada actualmente.
  Usuario? get usuarioActual => _usuarioActual;

  /// Devuelve la lista de usuarios registrados en la base de datos local.
  Future<List<Usuario>> obtenerUsuarios({bool forzarRecarga = false}) async {
    final enCache = _cacheUsuarios;
    if (enCache != null && !forzarRecarga) return enCache;

    final crudos = await _baseDatosService.obtenerUsuariosCrudos();
    final usuarios = crudos.map(Usuario.fromMap).toList();
    _cacheUsuarios = usuarios;
    return usuarios;
  }

  /// Devuelve únicamente los usuarios que pueden ser asignados como responsables
  /// de una obra (capataces e ingenieros).
  Future<List<Usuario>> obtenerResponsablesDisponibles() async {
    final todos = await obtenerUsuarios();
    return todos
        .where(
          (u) => u.rol == RolUsuario.capataz || u.rol == RolUsuario.ingeniero,
        )
        .toList();
  }

  /// Valida las credenciales contra los 3 usuarios de prueba en SQLite.
  ///
  /// Devuelve el [Usuario] si coincide el nombre de usuario (o rol) y la
  /// contraseña, o `null` si las credenciales son inválidas.
  Future<Usuario?> iniciarSesion({
    required String identificador,
    required String contrasenia,
  }) async {
    final usuarios = await obtenerUsuarios(forzarRecarga: true);
    final identificadorNormalizado = identificador.trim().toLowerCase();

    for (final usuario in usuarios) {
      final coincideUsuario =
          usuario.username.toLowerCase() == identificadorNormalizado ||
              usuario.nombre.toLowerCase() == identificadorNormalizado ||
              usuario.rol.name.toLowerCase() == identificadorNormalizado ||
              (identificadorNormalizado == 'dueño' &&
                  usuario.rol == RolUsuario.duenio);

      if (coincideUsuario && usuario.contrasenia == contrasenia) {
        _usuarioActual = usuario;
        return usuario;
      }
    }
    return null;
  }

  /// Actualiza los datos del perfil del usuario activo en SQLite y en caché.
  Future<Usuario> actualizarPerfil({
    required String nombre,
    required String telefono,
    required String contrasenia,
  }) async {
    final actual = _usuarioActual;
    if (actual == null) {
      throw StateError('No hay una sesión activa para actualizar.');
    }

    final actualizado = actual.copyWith(
      nombre: nombre.trim(),
      telefono: telefono.trim(),
      contrasenia: contrasenia.trim(),
    );

    await _baseDatosService.actualizarUsuarioCrudo(actualizado.toMap());
    _usuarioActual = actualizado;
    await obtenerUsuarios(forzarRecarga: true);
    return actualizado;
  }

  /// Cierra la sesión actual.
  void cerrarSesion() {
    _usuarioActual = null;
  }
}
