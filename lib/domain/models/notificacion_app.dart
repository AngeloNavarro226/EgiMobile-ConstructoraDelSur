/// Representa una notificación emitida por la aplicación (alerta proactiva
/// de semáforo amarillo/rojo, mensaje manual del ingeniero o recordatorio diario).
class NotificacionApp {
  const NotificacionApp({
    required this.id,
    required this.titulo,
    required this.mensaje,
    required this.destinatario,
    required this.fechaHora,
    this.esAlertaSemaforo = false,
  });

  final String id;
  final String titulo;
  final String mensaje;
  final String destinatario;
  final DateTime fechaHora;
  final bool esAlertaSemaforo;

  Map<String, dynamic> toMap() => {
        'id': id,
        'titulo': titulo,
        'mensaje': mensaje,
        'destinatario': destinatario,
        'fecha_hora': fechaHora.toIso8601String(),
        'es_alerta_semaforo': esAlertaSemaforo ? 1 : 0,
      };

  factory NotificacionApp.fromMap(Map<String, dynamic> map) => NotificacionApp(
        id: map['id'] as String,
        titulo: map['titulo'] as String,
        mensaje: map['mensaje'] as String,
        destinatario: map['destinatario'] as String,
        fechaHora: DateTime.parse(map['fecha_hora'] as String),
        esAlertaSemaforo: (map['es_alerta_semaforo'] as int? ?? 0) == 1,
      );
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
