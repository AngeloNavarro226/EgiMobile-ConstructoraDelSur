import 'estado_sincronizacion.dart';

/// Representa una notificación emitida por la aplicación (alerta proactiva
/// de semáforo amarillo/rojo, mensaje manual del ingeniero o recordatorio diario).
class NotificacionApp {
  const NotificacionApp({
    required this.id,
    required this.titulo,
    required this.mensaje,
    required this.destinatario,
    required this.fechaHora,
    this.obraId,
    this.esAlertaSemaforo = false,
    this.updatedAt,
    this.syncStatus = EstadoSincronizacion.pending,
  });

  final String id;

  /// Referencia opcional (`FK` a `obras.id`) cuando la alerta corresponde a una obra.
  final String? obraId;
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

/// Configuración del recordatorio automático diario para abrir la aplicación
/// y sincronizar los datos pendientes.
class ProgramacionRecordatorio {
  const ProgramacionRecordatorio({
    required this.activo,
    required this.hora,
    required this.minuto,
  });

  final bool activo;
  final int hora;
  final int minuto;

  /// Hora formateada en formato `HH:mm` de 24 horas.
  String get horarioFormateado =>
      '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';

  ProgramacionRecordatorio copyWith({
    bool? activo,
    int? hora,
    int? minuto,
  }) =>
      ProgramacionRecordatorio(
        activo: activo ?? this.activo,
        hora: hora ?? this.hora,
        minuto: minuto ?? this.minuto,
      );
}
