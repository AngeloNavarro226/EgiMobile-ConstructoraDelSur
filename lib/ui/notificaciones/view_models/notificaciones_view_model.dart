import 'dart:async';

import '../../../data/repositories/notificaciones_repository.dart';
import '../../../data/services/bus_de_eventos.dart';
import '../../../domain/models/evento_de_app.dart';
import '../../../domain/models/notificacion_app.dart';
import '../../core/view_model_base.dart';

/// ViewModel del apartado exclusivo del Ingeniero para enviar notificaciones
/// y programar el recordatorio automático diario de sincronización.
class NotificacionesViewModel extends ViewModelBase {
  NotificacionesViewModel({
    required NotificacionesRepository repositorio,
    BusDeEventos? busDeEventos,
  })  : _repositorio = repositorio,
        _busDeEventos = busDeEventos {
    _suscripcionEventos = _busDeEventos?.stream.listen(_procesarEventoGlobal);
  }

  final NotificacionesRepository _repositorio;
  final BusDeEventos? _busDeEventos;
  StreamSubscription<EventoDeApp>? _suscripcionEventos;

  EstadoOperacion _estado = EstadoOperacion.inicial;
  List<NotificacionApp> _notificaciones = [];
  ProgramacionRecordatorio _recordatorio = const ProgramacionRecordatorio(
    activo: true,
    hora: 18,
    minuto: 0,
  );
  bool _cargando = false;
  bool _enviando = false;
  String? _mensajeError;

  /// Estado actual de la carga del panel de notificaciones.
  EstadoOperacion get estado => _estado;

  /// Historial de notificaciones y alertas proactivas de semáforo.
  List<NotificacionApp> get notificaciones =>
      List.unmodifiable(_notificaciones);

  /// Configuración del recordatorio diario de sincronización.
  ProgramacionRecordatorio get recordatorio => _recordatorio;

  /// Indica si se están cargando los datos del panel.
  bool get cargando => _cargando;

  /// Indica si se está enviando una notificación o actualizando el recordatorio.
  bool get enviando => _enviando;

  /// Último mensaje de error, si existiera.
  String? get mensajeError => _mensajeError;

  /// Carga el historial de notificaciones y el horario del recordatorio,
  /// notificando explícitamente en `cargando`, `exito` y `error`.
  Future<void> cargar() async {
    _estado = EstadoOperacion.cargando;
    _cargando = true;
    _mensajeError = null;
    notificarSiActivo();

    try {
      _notificaciones = await _repositorio.obtenerNotificaciones();
      _recordatorio = await _repositorio.obtenerProgramacionRecordatorio();
      _cargando = false;
      _estado = EstadoOperacion.exito;
      notificarSiActivo();
    } catch (e) {
      _cargando = false;
      _estado = EstadoOperacion.error;
      _mensajeError = 'No se pudo cargar el historial de notificaciones: $e';
      notificarSiActivo();
    }
  }

  /// Actualiza el horario o estado activo del recordatorio diario.
  Future<void> actualizarRecordatorioSincronizacion({
    required bool activo,
    required int hora,
    required int minuto,
  }) async {
    _enviando = true;
    _mensajeError = null;
    notificarSiActivo();

    try {
      _recordatorio = await _repositorio.actualizarProgramacionRecordatorio(
        activo: activo,
        hora: hora,
        minuto: minuto,
      );
      _enviando = false;
      _estado = EstadoOperacion.exito;
      notificarSiActivo();
    } catch (e) {
      _enviando = false;
      _estado = EstadoOperacion.error;
      _mensajeError = 'No se pudo actualizar el recordatorio: $e';
      notificarSiActivo();
    }
  }

  /// Envía una notificación manual desde el panel del ingeniero y refresca.
  Future<void> enviarNotificacion({
    required String titulo,
    required String mensaje,
    required String destinatario,
  }) async {
    if (titulo.trim().isEmpty || mensaje.trim().isEmpty) return;

    _enviando = true;
    _mensajeError = null;
    notificarSiActivo();

    try {
      await _repositorio.enviarNotificacionManual(
        titulo: titulo,
        mensaje: mensaje,
        destinatario: destinatario,
      );
      _notificaciones = await _repositorio.obtenerNotificaciones();
      _enviando = false;
      _estado = EstadoOperacion.exito;
      notificarSiActivo();
    } catch (e) {
      _enviando = false;
      _estado = EstadoOperacion.error;
      _mensajeError = 'No se pudo enviar la notificación: $e';
      notificarSiActivo();
    }
  }

  void _procesarEventoGlobal(EventoDeApp evento) {
    switch (evento) {
      case AlertaSemaforoEmitida() || SesionIniciada():
        unawaited(cargar());
      case SesionCerrada():
        _notificaciones = [];
        _mensajeError = null;
        _estado = EstadoOperacion.inicial;
        notificarSiActivo();
      default:
        break;
    }
  }

  @override
  void dispose() {
    _suscripcionEventos?.cancel();
    super.dispose();
  }
}
