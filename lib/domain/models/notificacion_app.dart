import 'estado_sincronizacion.dart';

/// Representa una notificación emitida por la aplicación (alerta proactiva de
/// cambio de semáforo amarillo/rojo registrada y enviada vía FCM).
class NotificacionApp {
  const NotificacionApp({
    required this.id,
    required this.titulo,
    required this.mensaje,
    required this.destinatario,
    required this.fechaHora,
    this.obraId,
    this.emisorId,
    this.esAlertaSemaforo = false,
    this.updatedAt,
    this.syncStatus = EstadoSincronizacion.pending,
  });

  final String id;

  /// Referencia opcional (`FK` a `obras.id`) cuando la alerta corresponde a una obra.
  final String? obraId;

  /// Usuario que disparó la alerta (`FK` a `usuarios.id`), utilizado para
  /// determinar los destinatarios push según el rol emisor.
  final String? emisorId;
  final String titulo;
  final String mensaje;
  final String destinatario;
  final DateTime fechaHora;
  final bool esAlertaSemaforo;
  final DateTime? updatedAt;
  final EstadoSincronizacion syncStatus;

  Map<String, dynamic> toMap() => {
        'id': id,
        'obra_id': obraId,
        'emisor_id': emisorId,
        'titulo': titulo,
        'mensaje': mensaje,
        'destinatario': destinatario,
        'fecha_hora': fechaHora.toUtc().toIso8601String(),
        'es_alerta_semaforo': esAlertaSemaforo ? 1 : 0,
        'updated_at': (updatedAt ?? fechaHora).toUtc().toIso8601String(),
        'sync_status': syncStatus.toStorage(),
      };

  factory NotificacionApp.fromMap(Map<String, dynamic> map) {
    final updatedAtRaw = map['updated_at'] as String?;
    return NotificacionApp(
      id: map['id'] as String,
      obraId: map['obra_id'] as String?,
      emisorId: map['emisor_id'] as String?,
      titulo: map['titulo'] as String,
      mensaje: map['mensaje'] as String,
      destinatario: map['destinatario'] as String,
      fechaHora: DateTime.parse(map['fecha_hora'] as String),
      esAlertaSemaforo: (map['es_alerta_semaforo'] as int? ?? 0) == 1,
      updatedAt: updatedAtRaw != null ? DateTime.parse(updatedAtRaw) : null,
      syncStatus: EstadoSincronizacion.fromStorage(
        (map['sync_status'] as String?) ?? 'synced',
      ),
    );
  }
}

/// Configuración del recordatorio automático diario por Ingeniero para avisar
/// al equipo cuando existan informes sin sincronizar.
class ProgramacionRecordatorio {
  const ProgramacionRecordatorio({
    this.ingenieroId,
    required this.activo,
    required this.hora,
    required this.minuto,
    this.updatedAt,
    this.syncStatus = EstadoSincronizacion.synced,
  });

  final String? ingenieroId;
  final bool activo;
  final int hora;
  final int minuto;
  final DateTime? updatedAt;
  final EstadoSincronizacion syncStatus;

  /// Minutos transcurridos desde las 00:00 (permite elegir el horario más temprano).
  int get minutosDesdeMedianoche => hora * 60 + minuto;

  /// Hora formateada en formato `HH:mm` de 24 horas.
  String get horarioFormateado =>
      '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';

  ProgramacionRecordatorio copyWith({
    String? ingenieroId,
    bool? activo,
    int? hora,
    int? minuto,
    DateTime? updatedAt,
    EstadoSincronizacion? syncStatus,
  }) =>
      ProgramacionRecordatorio(
        ingenieroId: ingenieroId ?? this.ingenieroId,
        activo: activo ?? this.activo,
        hora: hora ?? this.hora,
        minuto: minuto ?? this.minuto,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );

  Map<String, dynamic> toMap() => {
        'ingeniero_id': ingenieroId,
        'activo': activo ? 1 : 0,
        'hora': hora,
        'minuto': minuto,
        'updated_at':
            (updatedAt ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
        'sync_status': syncStatus.toStorage(),
      };

  factory ProgramacionRecordatorio.fromMap(Map<String, dynamic> map) {
    final updatedAtRaw = map['updated_at'] as String?;
    final activoRaw = map['activo'];
    final activo =
        activoRaw is bool ? activoRaw : (activoRaw as int? ?? 1) == 1;
    return ProgramacionRecordatorio(
      ingenieroId: map['ingeniero_id'] as String?,
      activo: activo,
      hora: (map['hora'] as int?) ?? 18,
      minuto: (map['minuto'] as int?) ?? 0,
      updatedAt: updatedAtRaw != null ? DateTime.parse(updatedAtRaw) : null,
      syncStatus: EstadoSincronizacion.fromStorage(
        (map['sync_status'] as String?) ?? 'synced',
      ),
    );
  }
}
