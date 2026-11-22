import '../../domain/models/estado_sincronizacion.dart';
import '../../domain/models/evento_de_app.dart';
import '../../domain/models/usuario.dart';
import '../services/base_datos_local_service.dart';
import '../services/bus_de_eventos.dart';
import '../services/reloj.dart';
import '../services/servicio_autenticacion_remota.dart';
import 'preferencias_repository.dart';

/// Fuente de verdad para la autenticación (Supabase Auth + respaldo SQLite
/// Offline-First), la sesión persistida y la gestión de perfiles y roles.
class AutenticacionRepository {
  AutenticacionRepository({
    required BaseDatosLocalService baseDatosService,
    PreferenciasRepository? preferenciasRepository,
    ServicioAutenticacionRemota authRemota =
        const ServicioAutenticacionRemotaOffline(),
    Reloj reloj = const RelojDelSistema(),
    BusDeEventos? busDeEventos,
  })  : _baseDatosService = baseDatosService,
        _preferenciasRepository = preferenciasRepository,
        _authRemota = authRemota,
        _reloj = reloj,
        _busDeEventos = busDeEventos;

  static const dominioCorreoCorporativo = 'constructoradelsur.com';

  final BaseDatosLocalService _baseDatosService;
  final PreferenciasRepository? _preferenciasRepository;
  final ServicioAutenticacionRemota _authRemota;
  final Reloj _reloj;
  final BusDeEventos? _busDeEventos;

  List<Rol>? _cacheRoles;
  List<Usuario>? _cacheUsuarios;
  Usuario? _usuarioActual;

  /// Usuario que tiene la sesión iniciada actualmente.
  Usuario? get usuarioActual => _usuarioActual;

  /// Indica si la autenticación remota con Supabase Auth está activa.
  bool get usaAutenticacionRemota => _authRemota.estaDisponible;

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

  /// Restaura la sesión persistida (Supabase Auth + caché SQLite) para operar
  /// 100% offline al reabrir la aplicación sin señal.
  Future<Usuario?> restaurarSesionGuardada() async {
    if (_authRemota.estaDisponible) {
      final authId = _authRemota.usuarioAuthIdActual;
      if (authId == null || authId.isEmpty) {
        return null;
      }

      // Si hay red, refresca el perfil remoto y lo cachea en SQLite.
      final perfilRemoto = await _authRemota.obtenerPerfilActual();
      if (perfilRemoto != null) {
        await _guardarPerfilEnCacheLocal(perfilRemoto);
        final usuario = Usuario.fromMap(perfilRemoto);
        _usuarioActual = usuario;
        await _preferenciasRepository?.guardarUsuarioSesionId(usuario.id);
        _busDeEventos?.emitir(SesionIniciada(usuarioId: usuario.id));
        return usuario;
      }

      // Sin red: cae al perfil cacheado en SQLite local.
      final usuarios = await obtenerUsuarios(forzarRecarga: true);
      final sesionLocalId =
          await _preferenciasRepository?.obtenerUsuarioSesionId();
      for (final usuario in usuarios) {
        if (usuario.id == authId || usuario.id == sesionLocalId) {
          _usuarioActual = usuario;
          _busDeEventos?.emitir(SesionIniciada(usuarioId: usuario.id));
          return usuario;
        }
      }
      return null;
    }

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

  /// Autentica contra Supabase Auth (si está activo) o contra SQLite local.
  ///
  /// En modo Supabase acepta tanto correo completo (`capataz@constructoradelsur.com`)
  /// como nombre de usuario corto (`capataz`), resolviéndolo al dominio corporativo.
  Future<Usuario?> iniciarSesion({
    required String identificador,
    required String contrasenia,
  }) async {
    if (_authRemota.estaDisponible) {
      final email = _normalizarEmailParaAuth(identificador);
      final perfilRemoto = await _authRemota.iniciarSesion(
        email: email,
        password: contrasenia,
      );
      if (perfilRemoto == null) return null;

      await _guardarPerfilEnCacheLocal(perfilRemoto);
      final usuario = Usuario.fromMap(perfilRemoto);
      _usuarioActual = usuario;
      await _preferenciasRepository?.guardarUsuarioSesionId(usuario.id);
      _busDeEventos?.emitir(SesionIniciada(usuarioId: usuario.id));
      return usuario;
    }

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

    final contraseniaLimpia = contrasenia.trim();
    if (_authRemota.estaDisponible && contraseniaLimpia.isNotEmpty) {
      try {
        await _authRemota.actualizarContrasenia(contraseniaLimpia);
      } catch (_) {
        // Si está offline, los cambios de nombre/teléfono siguen guardándose
        // localmente en cola `pending`.
      }
    }

    final actualizado = actual.copyWith(
      nombre: nombre.trim(),
      telefono: telefono.trim(),
      contrasenia: _authRemota.estaDisponible ? '' : contraseniaLimpia,
      updatedAt: _reloj.ahora().toUtc(),
      syncStatus: EstadoSincronizacion.pending,
    );

    await _baseDatosService.actualizarUsuarioCrudo(actualizado.toMap());
    _usuarioActual = actualizado;
    await obtenerUsuarios(forzarRecarga: true);
    return actualizado;
  }

  /// Cierra la sesión remota y local, limpia preferencias y cachés.
  Future<void> cerrarSesion() async {
    if (_authRemota.estaDisponible) {
      await _authRemota.cerrarSesion();
    }
    _usuarioActual = null;
    _cacheUsuarios = null;
    await _preferenciasRepository?.limpiarSesion();
    _busDeEventos?.emitir(const SesionCerrada());
  }

  String _normalizarEmailParaAuth(String identificador) {
    final limpio = identificador.trim().toLowerCase();
    if (limpio.contains('@')) return limpio;
    final alias = limpio == 'dueño' || limpio == 'duenio' ? 'dueno' : limpio;
    return '$alias@$dominioCorreoCorporativo';
  }

  Future<void> _guardarPerfilEnCacheLocal(Map<String, dynamic> perfil) async {
    final mapaSql = <String, dynamic>{
      'id': perfil['id'],
      'username': perfil['username'],
      'rol_id': perfil['rol_id'],
      'nombre': perfil['nombre'],
      'contrasenia': '',
      'telefono': (perfil['telefono'] as String?) ?? '',
      'updated_at':
          perfil['updated_at'] ?? _reloj.ahora().toUtc().toIso8601String(),
      'sync_status': 'synced',
    };
    await _baseDatosService.guardarUsuarioCrudo(mapaSql);
    await obtenerUsuarios(forzarRecarga: true);
  }
}
