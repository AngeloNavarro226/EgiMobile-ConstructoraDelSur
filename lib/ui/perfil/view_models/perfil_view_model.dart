import 'dart:async';

import '../../../data/repositories/autenticacion_repository.dart';
import '../../../data/repositories/notificaciones_repository.dart';
import '../../../data/repositories/preferencias_repository.dart';
import '../../../data/services/sincronizacion_service.dart';
import '../../../domain/models/usuario.dart';
import '../../core/view_model_base.dart';

/// ViewModel de la pantalla de Perfil (compartida por Ingeniero, Capataz y Dueño).
///
/// Gestiona la carga inicial de preferencias persistidas, la edición del
/// perfil en SQLite (incluyendo `telefono`), el cambio de tema oscuro y la
/// preferencia de alertas.
class PerfilViewModel extends ViewModelBase {
  PerfilViewModel({
    required AutenticacionRepository autenticacionRepository,
    required PreferenciasRepository preferenciasRepository,
    required SincronizacionService sincronizacionService,
    NotificacionesRepository? notificacionesRepository,
  })  : _autenticacionRepository = autenticacionRepository,
        _preferenciasRepository = preferenciasRepository,
        _sincronizacionService = sincronizacionService,
        _notificacionesRepository = notificacionesRepository;

  final AutenticacionRepository _autenticacionRepository;
  final PreferenciasRepository _preferenciasRepository;
  final SincronizacionService _sincronizacionService;
  final NotificacionesRepository? _notificacionesRepository;

  EstadoOperacion _estado = EstadoOperacion.inicial;
  bool _guardando = false;
  String? _mensajeError;

  /// Estado de la última operación ejecutada en Perfil.
  EstadoOperacion get estado => _estado;

  /// Indica si se están guardando cambios de perfil.
  bool get guardando => _guardando;

  /// Último mensaje de error, si ocurrió alguno.
  String? get mensajeError => _mensajeError;

  /// Usuario autenticado actualmente.
  Usuario? get usuarioActual => _autenticacionRepository.usuarioActual;

  /// Indica si el modo oscuro está activo.
  bool get modoOscuro => _preferenciasRepository.modoOscuro;

  /// Indica si las alertas de cambio de semáforo están habilitadas.
  bool get notificacionesActivas =>
      _preferenciasRepository.recibirAlertasSemaforo;

  /// Carga las preferencias guardadas (`modoOscuro`, alertas) desde disco y
  /// notifica explícitamente a la app para aplicar el tema al iniciar.
  Future<void> inicializarPreferencias() async {
    _estado = EstadoOperacion.cargando;
    _mensajeError = null;
    notificarSiActivo();

    try {
      await _preferenciasRepository.inicializar();
      _estado = EstadoOperacion.exito;
      notificarSiActivo();
    } catch (e) {
      _estado = EstadoOperacion.error;
      _mensajeError = 'No se pudieron cargar las preferencias: $e';
      notificarSiActivo();
    }
  }

  /// Alterna entre el modo claro y oscuro.
  void alternarModoOscuro() {
    _preferenciasRepository.alternarModoOscuro();
    notificarSiActivo();
  }

  /// Activa o desactiva la recepción de alertas proactivas.
  void cambiarNotificaciones(bool valor) {
    _preferenciasRepository.cambiarRecibirAlertas(valor);
    if (valor) {
      unawaited(
        _notificacionesRepository?.solicitarPermisoEnContexto() ??
            Future<bool>.value(true),
      );
    }
    notificarSiActivo();
  }

  /// Actualiza el nombre, teléfono y contraseña del perfil en SQLite.
  Future<bool> actualizarDatosPerfil({
    required String nombre,
    required String telefono,
    required String contrasenia,
  }) async {
    _guardando = true;
    _estado = EstadoOperacion.cargando;
    _mensajeError = null;
    notificarSiActivo();

    try {
      await _autenticacionRepository.actualizarPerfil(
        nombre: nombre,
        telefono: telefono,
        contrasenia: contrasenia,
      );
      _guardando = false;
      _estado = EstadoOperacion.exito;
      notificarSiActivo();
      return true;
    } catch (e) {
      _guardando = false;
      _estado = EstadoOperacion.error;
      _mensajeError = 'No se pudo actualizar el perfil: $e';
      notificarSiActivo();
      return false;
    }
  }

  /// Dispara una sincronización manual mediante el servicio de conectividad.
  Future<void> sincronizarManualmente() async {
    await _sincronizacionService.dispararDeteccionDeInternet();
  }
}
