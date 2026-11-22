import 'package:flutter/foundation.dart';

import '../../../data/repositories/notificaciones_repository.dart';
import '../../../domain/models/notificacion_app.dart';

/// ViewModel del apartado exclusivo del Ingeniero para enviar notificaciones
/// mediante la aplicación y programar el horario del recordatorio automático
/// diario para abrir la aplicación y sincronizar los datos.
class NotificacionesViewModel extends ChangeNotifier {
  NotificacionesViewModel({
    required NotificacionesRepository repositorio,
  }) : _repositorio = repositorio;

  final NotificacionesRepository _repositorio;

  List<NotificacionApp> _notificaciones = [];
  ProgramacionRecordatorio _recordatorio = const ProgramacionRecordatorio(
    activo: true,
    hora: 18,
    minuto: 0,
  );
  bool _cargando = false;

  /// Historial de notificaciones y alertas proactivas de semáforo.
  List<NotificacionApp> get notificaciones =>
      List.unmodifiable(_notificaciones);

  /// Configuración del recordatorio diario de sincronización.
  ProgramacionRecordatorio get recordatorio => _recordatorio;

  /// Indica si se están cargando los datos del panel.
  bool get cargando => _cargando;

  /// Carga el historial de notificaciones y el horario del recordatorio.
  Future<void> cargar() async {
    _cargando = true;
    notifyListeners();
    _notificaciones = await _repositorio.obtenerNotificaciones();
    _recordatorio = await _repositorio.obtenerProgramacionRecordatorio();
    _cargando = false;
    notifyListeners();
  }

  /// Actualiza el horario o estado activo del recordatorio diario de
  /// abrir la aplicación para sincronizar los datos una vez al día.
  Future<void> actualizarRecordatorioSincronizacion({
    required bool activo,
    required int hora,
    required int minuto,
  }) async {
    _recordatorio = await _repositorio.actualizarProgramacionRecordatorio(
      activo: activo,
      hora: hora,
      minuto: minuto,
    );
    notifyListeners();
  }

  /// Envía una notificación manual desde el panel del ingeniero hacia los
  /// perfiles seleccionados y refresca el historial.
  Future<void> enviarNotificacion({
    required String titulo,
    required String mensaje,
    required String destinatario,
  }) async {
    if (titulo.trim().isEmpty || mensaje.trim().isEmpty) return;
    await _repositorio.enviarNotificacionManual(
      titulo: titulo,
      mensaje: mensaje,
      destinatario: destinatario,
    );
    _notificaciones = await _repositorio.obtenerNotificaciones();
    notifyListeners();
  }
}
