import 'dart:async';

import '../../domain/models/estado_sincronizacion.dart';
import '../../domain/models/evento_de_app.dart';
import '../../domain/models/notificacion_app.dart';
import '../../domain/models/obra.dart';
import '../../domain/models/usuario.dart';
import '../../plataforma/politicas.dart';
import '../services/base_datos_local_service.dart';
import '../services/bus_de_eventos.dart';
import '../services/generador_ids.dart';
import '../services/motor_sincronizacion.dart';
import '../services/notificaciones_sistema_service.dart';
import '../services/reloj.dart';
import 'autenticacion_repository.dart';
import 'preferencias_repository.dart';

/// Fuente de verdad para las alertas proactivas de cambio de semáforo
/// (Amarillo / Rojo) enviadas vía FCM y el recordatorio diario de
/// sincronización configurable por ingeniero.
class NotificacionesRepository {
  NotificacionesRepository({
    required BaseDatosLocalService baseDatosService,
    ServicioDeNotificaciones? notificacionesSistemaService,
    PoliticaDeAvisos politicaDeAvisos = const PoliticaDeAvisos(),
    Reloj reloj = const RelojDelSistema(),
    GeneradorIds? generadorIds,
    AutenticacionRepository? autenticacionRepository,
    PreferenciasRepository? preferenciasRepository,
    MotorSincronizacion? motorSincronizacion,
    BusDeEventos? busDeEventos,
  })  : _baseDatosService = baseDatosService,
        _notificacionesSistemaService =
            notificacionesSistemaService ?? NotificacionesSistemaService(),
        _politicaDeAvisos = politicaDeAvisos,
        _reloj = reloj,
        _generadorIds = generadorIds ?? GeneradorUuidV4(),
        _autenticacionRepository = autenticacionRepository,
        _preferenciasRepository = preferenciasRepository,
        _motorSincronizacion = motorSincronizacion,
        _busDeEventos = busDeEventos;

  final BaseDatosLocalService _baseDatosService;
  final ServicioDeNotificaciones _notificacionesSistemaService;
  final PoliticaDeAvisos _politicaDeAvisos;
  final Reloj _reloj;
  final GeneradorIds _generadorIds;
  final AutenticacionRepository? _autenticacionRepository;
  final PreferenciasRepository? _preferenciasRepository;
  final MotorSincronizacion? _motorSincronizacion;
  final BusDeEventos? _busDeEventos;

  /// Flujo de toques sobre notificaciones push o recordatorios del sistema.
  Stream<String> get toques => _notificacionesSistemaService.toques;

  /// Solicita permiso de notificaciones en contexto (nunca en `main()`).
  Future<bool> solicitarPermisoEnContexto() {
    return _notificacionesSistemaService.pedirPermiso();
  }

  /// Obtiene el historial de alertas de cambio de semáforo registradas.
  Future<List<NotificacionApp>> obtenerNotificaciones() async {
    final crudas = await _baseDatosService.obtenerNotificacionesCrudas();
    return crudas.map(NotificacionApp.fromMap).toList();
  }

  /// Registra una alerta proactiva cuando una obra pasa a estado Amarillo
  /// (`demorada`) o Rojo (`problemas`) según [PoliticaDeAvisos]:
  /// - Si el cambio lo realiza un **Capataz**: notifica al **Ingeniero a cargo**
  ///   (`obra.ingenieroId`) y al **Dueño**.
  /// - Si el cambio lo realiza un **Ingeniero**: notifica al **Capataz a cargo**
  ///   (`obra.responsableId`) y al **Dueño**.
  ///
  /// Persiste la alerta en SQLite (`pending`) y dispara la sincronización
  /// inmediata con Supabase para que la Edge Function despache los push FCM
  /// reales a los dispositivos destinatarios (sin autonotificar al emisor).
  Future<NotificacionApp?> emitirAlertaCambioSemaforo({
    required Obra obra,
    required String motivo,
    Usuario? emisor,
  }) async {
    if (!_politicaDeAvisos.debeAvisar(obra.estado)) return null;

    final ahoraUtc = _reloj.ahora().toUtc();
    final emisorEfectivo = emisor ?? _autenticacionRepository?.usuarioActual;
    final usuarios =
        await _autenticacionRepository?.obtenerUsuarios() ?? const <Usuario>[];
    final destinatarios = _politicaDeAvisos.resolverDestinatariosAlertaSemaforo(
      obra: obra,
      emisor: emisorEfectivo,
      usuarios: usuarios,
    );

    final destinatarioTexto = destinatarios.isNotEmpty
        ? destinatarios.map((u) => u.nombre).join(' / ')
        : (emisorEfectivo?.rol.tipo == RolUsuario.ingeniero
            ? 'Capataz a cargo y Gerencia'
            : 'Ingeniero a cargo y Gerencia');

    final alerta = NotificacionApp(
      id: _generadorIds.generar(),
      obraId: obra.id,
      emisorId: emisorEfectivo?.id,
      titulo:
          'Alerta ${obra.estado.nombreColor}: ${obra.nombre} (${obra.estado.etiqueta})',
      mensaje: motivo.trim().isEmpty
          ? 'La obra cambió su semáforo a ${obra.estado.etiqueta}.'
          : motivo.trim(),
      destinatario: destinatarioTexto,
      fechaHora: ahoraUtc,
      esAlertaSemaforo: true,
      updatedAt: ahoraUtc,
      syncStatus: EstadoSincronizacion.pending,
    );

    await _baseDatosService.guardarNotificacionCruda(alerta.toMap());
    _busDeEventos?.emitir(AlertaSemaforoEmitida(obraId: obra.id));

    if (_motorSincronizacion != null) {
      unawaited(_motorSincronizacion.sincronizarTodo());
    }
    return alerta;
  }

  /// Obtiene la configuración del recordatorio diario correspondiente al
  /// [ingenieroId] (o al usuario autenticado actual si se omite).
  Future<ProgramacionRecordatorio> obtenerProgramacionRecordatorio({
    String? ingenieroId,
  }) async {
    final idObjetivo =
        ingenieroId ?? _autenticacionRepository?.usuarioActual?.id;
    final mapa = await _baseDatosService.obtenerConfiguracionRecordatorio(
      ingenieroId: idObjetivo,
    );
    return ProgramacionRecordatorio.fromMap(mapa);
  }

  /// Obtiene todas las configuraciones de recordatorio sincronizadas
  /// indexadas por `ingeniero_id`.
  Future<Map<String, ProgramacionRecordatorio>>
      obtenerConfiguracionesPorIngeniero() async {
    final filas =
        await _baseDatosService.obtenerTodasLasConfiguracionesRecordatorio();
    final resultado = <String, ProgramacionRecordatorio>{};
    for (final fila in filas) {
      final config = ProgramacionRecordatorio.fromMap(fila);
      final id = config.ingenieroId;
      if (id != null && id.isNotEmpty) {
        resultado[id] = config;
      }
    }
    return resultado;
  }

  /// Guarda la configuración del recordatorio diario propia del ingeniero
  /// (`ingeniero_id`), actualiza su copia local en `SharedPreferences` y
  /// `AlarmManager`, y la encola para sincronizar con Supabase.
  Future<ProgramacionRecordatorio> actualizarProgramacionRecordatorio({
    String? ingenieroId,
    required bool activo,
    required int hora,
    required int minuto,
  }) async {
    final idObjetivo =
        ingenieroId ?? _autenticacionRepository?.usuarioActual?.id;
    final ahoraUtc = _reloj.ahora().toUtc();

    await _baseDatosService.guardarConfiguracionRecordatorio(
      ingenieroId: idObjetivo,
      activo: activo,
      hora: hora,
      minuto: minuto,
      syncStatus: 'pending',
    );

    final programacion = ProgramacionRecordatorio(
      ingenieroId: idObjetivo,
      activo: activo,
      hora: hora,
      minuto: minuto,
      updatedAt: ahoraUtc,
      syncStatus: EstadoSincronizacion.pending,
    );

    await _aplicarAlarmaLocal(programacion, solicitarPermiso: true);

    if (_motorSincronizacion != null) {
      unawaited(_motorSincronizacion.sincronizarTodo());
    }
    return programacion;
  }

  /// Reprograma automáticamente la alarma local de Android y su copia en
  /// `SharedPreferences` según el rol del [usuario] autenticado:
  /// - **Capataz:** toma la configuración más temprana activa entre los
  ///   ingenieros a cargo de sus obras (`obra.ingenieroId`).
  /// - **Ingeniero:** aplica su propia configuración guardada.
  /// - **Dueño:** cancela cualquier recordatorio de sincronización local.
  Future<ProgramacionRecordatorio?> sincronizarRecordatorioLocalParaUsuario({
    required Usuario usuario,
    required List<Obra> obras,
  }) async {
    if (usuario.rol.tipo == RolUsuario.duenio) {
      await cancelarRecordatorioLocal();
      return null;
    }

    if (usuario.rol.tipo == RolUsuario.capataz) {
      final obrasPropias =
          obras.where((o) => o.responsableId == usuario.id).toList();
      final configs = await obtenerConfiguracionesPorIngeniero();
      final efectivo = _politicaDeAvisos.resolverRecordatorioMasTemprano(
        obrasDelCapataz: obrasPropias,
        configuracionesPorIngeniero: configs,
      );
      if (efectivo == null) {
        await cancelarRecordatorioLocal();
        return null;
      }
      await _aplicarAlarmaLocal(efectivo, solicitarPermiso: false);
      return efectivo;
    }

    final propia = await obtenerProgramacionRecordatorio(
      ingenieroId: usuario.id,
    );
    await _aplicarAlarmaLocal(propia, solicitarPermiso: false);
    return propia.activo ? propia : null;
  }

  /// Cancela la alarma local y marca el recordatorio inactivo en `SharedPreferences`.
  Future<void> cancelarRecordatorioLocal() async {
    await _preferenciasRepository?.desactivarRecordatorioLocal();
    await _notificacionesSistemaService.cancelarRecordatorioDiario();
  }

  Future<void> _aplicarAlarmaLocal(
    ProgramacionRecordatorio programacion, {
    required bool solicitarPermiso,
  }) async {
    final nombreDb = _baseDatosService.nombreArchivoActivo;
    if (programacion.activo) {
      if (solicitarPermiso) {
        await _notificacionesSistemaService.pedirPermiso();
      }
      await _preferenciasRepository?.guardarRecordatorioLocal(
        activo: true,
        hora: programacion.hora,
        minuto: programacion.minuto,
        nombreBaseDatos: nombreDb,
      );
      await _notificacionesSistemaService.programarRecordatorioDiario(
        hora: programacion.hora,
        minuto: programacion.minuto,
        titulo: 'Constructora Del Sur',
        mensaje: 'Abrí la app para sincronizar los reportes del día.',
        nombreBaseDatos: nombreDb,
      );
    } else {
      await _preferenciasRepository?.guardarRecordatorioLocal(
        activo: false,
        hora: programacion.hora,
        minuto: programacion.minuto,
        nombreBaseDatos: nombreDb,
      );
      await _notificacionesSistemaService.cancelarRecordatorioDiario();
    }
  }
}
