import '../../domain/models/aviso.dart';
import '../../domain/models/notificacion_app.dart';
import '../../domain/models/obra.dart';
import '../../plataforma/politicas.dart';
import '../services/base_datos_local_service.dart';
import '../services/notificaciones_sistema_service.dart';
import '../services/reloj.dart';

/// Fuente de verdad para las notificaciones push simuladas, alertas proactivas
/// de cambio de semáforo (Amarillo / Rojo) y el horario del recordatorio diario.
///
/// [ServicioDeNotificaciones] y consulta [PoliticaDeAvisos] antes de disparar
/// avisos en la barra superior del teléfono.
class NotificacionesRepository {
  NotificacionesRepository({
    required BaseDatosLocalService baseDatosService,
    ServicioDeNotificaciones? notificacionesSistemaService,
    PoliticaDeAvisos politicaDeAvisos = const PoliticaDeAvisos(),
    Reloj reloj = const RelojDelSistema(),
  })  : _baseDatosService = baseDatosService,
        _notificacionesSistemaService =
            notificacionesSistemaService ?? NotificacionesSistemaService(),
        _politicaDeAvisos = politicaDeAvisos,
        _reloj = reloj;

  final BaseDatosLocalService _baseDatosService;
  final ServicioDeNotificaciones _notificacionesSistemaService;
  final PoliticaDeAvisos _politicaDeAvisos;
  final Reloj _reloj;

  /// Solicita permiso de notificaciones en contexto cuando el usuario interactúa
  /// con las alertas
  Future<bool> solicitarPermisoEnContexto() {
    return _notificacionesSistemaService.pedirPermiso();
  }

  /// Obtiene la lista histórica de notificaciones enviadas.
  Future<List<NotificacionApp>> obtenerNotificaciones() async {
    final crudas = await _baseDatosService.obtenerNotificacionesCrudas();
    return crudas.map(NotificacionApp.fromMap).toList();
  }

  /// Registra y envía una notificación manual desde el panel del ingeniero
  /// tanto en SQLite como en la barra de estado del dispositivo.
  Future<NotificacionApp> enviarNotificacionManual({
    required String titulo,
    required String mensaje,
    required String destinatario,
  }) async {
    final ahora = _reloj.ahora();
    final nueva = NotificacionApp(
      id: 'notif_${ahora.microsecondsSinceEpoch}',
      titulo: titulo.trim(),
      mensaje: mensaje.trim(),
      destinatario: destinatario.trim(),
      fechaHora: ahora,
      esAlertaSemaforo: false,
    );
    await _baseDatosService.guardarNotificacionCruda(nueva.toMap());
    await _notificacionesSistemaService.mostrar(
      Aviso(
        id: ahora.millisecondsSinceEpoch % 100000,
        titulo: nueva.titulo,
        cuerpo: '${nueva.mensaje} (Para: ${nueva.destinatario})',
        alTocar: 'notificaciones',
      ),
    );
    return nueva;
  }

  /// Registra una alerta proactiva automática dirigida al Ingeniero y al Dueño
  /// cuando una obra pasa a estado Amarillo (`demorada`) o Rojo (`problemas`)
  /// según [PoliticaDeAvisos], y la muestra en la barra superior del teléfono.
  Future<NotificacionApp?> emitirAlertaCambioSemaforo({
    required Obra obra,
    required String motivo,
  }) async {
    if (!_politicaDeAvisos.debeAvisar(obra.estado)) return null;

    final ahora = _reloj.ahora();
    final alerta = NotificacionApp(
      id: 'alerta_${ahora.microsecondsSinceEpoch}',
      titulo:
          'Alerta ${obra.estado.nombreColor}: ${obra.nombre} (${obra.estado.etiqueta})',
      mensaje: motivo.trim().isEmpty
          ? 'La obra cambió su semáforo a ${obra.estado.etiqueta}.'
          : motivo.trim(),
      destinatario: 'Ing. Braulio Hormigón y Roberto Del Sur (Dueño)',
      fechaHora: ahora,
      esAlertaSemaforo: true,
    );
    await _baseDatosService.guardarNotificacionCruda(alerta.toMap());
    await _notificacionesSistemaService.mostrar(
      Aviso(
        id: obra.id.hashCode.abs() % 100000 + 1,
        titulo: alerta.titulo,
        cuerpo: alerta.mensaje,
        alTocar: 'obra:${obra.id}',
      ),
    );
    return alerta;
  }

  /// Obtiene la configuración actual del recordatorio diario de sincronización.
  Future<ProgramacionRecordatorio> obtenerProgramacionRecordatorio() async {
    final mapa = await _baseDatosService.obtenerConfiguracionRecordatorio();
    return ProgramacionRecordatorio(
      activo: (mapa['activo'] as int? ?? 1) == 1,
      hora: (mapa['hora'] as int?) ?? 18,
      minuto: (mapa['minuto'] as int?) ?? 0,
    );
  }

  /// Guarda el nuevo horario del recordatorio automático diario para abrir la
  /// aplicación y sincronizar los datos, mostrando una confirmación en la barra
  /// de notificaciones del sistema.
  Future<ProgramacionRecordatorio> actualizarProgramacionRecordatorio({
    required bool activo,
    required int hora,
    required int minuto,
  }) async {
    await _baseDatosService.guardarConfiguracionRecordatorio(
      activo: activo,
      hora: hora,
      minuto: minuto,
    );
    final programacion = ProgramacionRecordatorio(
      activo: activo,
      hora: hora,
      minuto: minuto,
    );
    if (activo) {
      // Aviso inmediato de confirmación + alarma diaria real del sistema.
      await _notificacionesSistemaService.mostrar(
        Aviso(
          id: 90001,
          titulo:
              'Recordatorio diario programado (${programacion.horarioFormateado} hs)',
          cuerpo:
              'Recibirás un aviso diario para abrir Constructora Del Sur y sincronizar los reportes.',
          alTocar: 'sincronizar',
        ),
      );
      await _notificacionesSistemaService.programarRecordatorioDiario(
        hora: hora,
        minuto: minuto,
        titulo: 'Constructora Del Sur',
        mensaje: 'Es hora de abrir la app y sincronizar los reportes del día.',
      );
    } else {
      await _notificacionesSistemaService.cancelar(90001);
      await _notificacionesSistemaService.cancelarRecordatorioDiario();
    }
    return programacion;
  }
}
