import '../../domain/models/estado_sincronizacion.dart';
import '../../domain/models/evento_de_app.dart';
import '../../domain/models/usuario.dart';
import '../services/base_datos_local_service.dart';
import '../services/bus_de_eventos.dart';
import '../services/reloj.dart';
import 'preferencias_repository.dart';

/// Fuente de verdad para la autenticación, la sesión offline persistida y la
/// gestión de perfiles y roles almacenados en SQLite.
class AutenticacionRepository {
  AutenticacionRepository({
    required BaseDatosLocalService baseDatosService,
    PreferenciasRepository? preferenciasRepository,
    Reloj reloj = const RelojDelSistema(),
    BusDeEventos? busDeEventos,
  })  : _baseDatosService = baseDatosService,
        _preferenciasRepository = preferenciasRepository,
        _reloj = reloj,
        _busDeEventos = busDeEventos;

  final BaseDatosLocalService _baseDatosService;
  final PreferenciasRepository? _preferenciasRepository;
  final Reloj _reloj;
  final BusDeEventos? _busDeEventos;

  List<Rol>? _cacheRoles;
  List<Usuario>? _cacheUsuarios;
  Usuario? _usuarioActual;

  /// Usuario que tiene la sesión iniciada actualmente.
  Usuario? get usuarioActual => _usuarioActual;

  /// Devuelve el catálogo de roles registrados en la tabla `roles`.
  Future<List<Rol>> obtenerRoles({bool forzarRecarga = false}) async {
    final enCache = _cacheRoles;
    if (enCache != null && !forzarRecarga) return enCache;

    final crudos = await _baseDatosService.obtenerRolesCrudos();
    final roles = crudos.map(Rol.fromMap).toList();
    _cacheRoles = roles;
    return roles;
  }

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
          (u) =>
              u.rol.tipo == RolUsuario.capataz ||
              u.rol.tipo == RolUsuario.ingeniero,
        )
        .toList();
  }

  /// Restaura la sesión local guardada para operar offline al reabrir la app.
  Future<Usuario?> restaurarSesionGuardada() async {
    final usuarioId = await _preferenciasRepository?.obtenerUsuarioSesionId();
    if (usuarioId == null || usuarioId.isEmpty) return null;

    final usuarios = await obtenerUsuarios(forzarRecarga: true);
    for (final usuario in usuarios) {
      if (usuario.id == usuarioId) {
        _usuarioActual = usuario;
        _busDeEventos?.emitir(SesionIniciada(usuarioId: usuario.id));
        return usuario;
      }
    }
    return null;
  }

  /// Valida las credenciales contra los usuarios locales en SQLite y persiste
  /// el identificador de sesión para soporte offline.
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
              usuario.rol.codigo.toLowerCase() == identificadorNormalizado ||
              (identificadorNormalizado == 'dueño' &&
                  usuario.rol.tipo == RolUsuario.duenio);

      if (coincideUsuario && usuario.contrasenia == contrasenia) {
        _usuarioActual = usuario;
        await _preferenciasRepository?.guardarUsuarioSesionId(usuario.id);
        _busDeEventos?.emitir(SesionIniciada(usuarioId: usuario.id));
        return usuario;
      }
    }
    return null;
  }

  /// Actualiza los datos del perfil (nombre, teléfono y contraseña) del
  /// usuario activo en SQLite con `sync_status = pending` y `updated_at` UTC.
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
      updatedAt: _reloj.ahora().toUtc(),
      syncStatus: EstadoSincronizacion.pending,
    );

    await _baseDatosService.actualizarUsuarioCrudo(actualizado.toMap());
    _usuarioActual = actualizado;
    await obtenerUsuarios(forzarRecarga: true);
    return actualizado;
  }

  /// Cierra la sesión actual, limpia la sesión persistida y las cachés locales.
  Future<void> cerrarSesion() async {
    _usuarioActual = null;
    _cacheUsuarios = null;
    await _preferenciasRepository?.limpiarSesion();
    _busDeEventos?.emitir(const SesionCerrada());
  }
}
