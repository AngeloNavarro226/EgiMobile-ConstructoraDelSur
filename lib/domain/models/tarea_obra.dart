import 'estado_sincronizacion.dart';

/// Representa una tarea individual dentro del plan de trabajo de una obra.
class TareaObra {
  const TareaObra({
    required this.id,
    required this.nombre,
    this.completada = false,
    this.updatedAt,
    this.syncStatus = EstadoSincronizacion.synced,
  });

  final String id;
  final String nombre;
  final bool completada;
  final DateTime? updatedAt;
  final EstadoSincronizacion syncStatus;

  /// Devuelve una copia de la tarea con su estado actualizado.
  TareaObra copyWith({
    String? nombre,
    bool? completada,
    DateTime? updatedAt,
    EstadoSincronizacion? syncStatus,
  }) =>
      TareaObra(
        id: id,
        nombre: nombre ?? this.nombre,
        completada: completada ?? this.completada,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );

  /// Convierte la tarea a una fila compatible con la tabla `tareas_obra` de SQLite.
  Map<String, dynamic> toMap({required String obraId, required int orden}) => {
        'id': id,
        'obra_id': obraId,
        'nombre': nombre,
        'completada': completada ? 1 : 0,
        'orden': orden,
        'updated_at':
            (updatedAt ?? DateTime.utc(2026)).toUtc().toIso8601String(),
        'sync_status': syncStatus.toStorage(),
      };

  /// Reconstruye una tarea desde una fila de la tabla `tareas_obra` de SQLite.
  factory TareaObra.fromMap(Map<String, dynamic> map) {
    final valorCompletada = map['completada'];
    final estaCompletada = valorCompletada is bool
        ? valorCompletada
        : (valorCompletada as int? ?? 0) == 1;
    final updatedAtRaw = map['updated_at'] as String?;

    return TareaObra(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      completada: estaCompletada,
      updatedAt: updatedAtRaw != null ? DateTime.parse(updatedAtRaw) : null,
      syncStatus: EstadoSincronizacion.fromStorage(
        (map['sync_status'] as String?) ?? 'synced',
      ),
    );
  }

  /// Convierte la tarea a un mapa serializable en JSON.
  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'completada': completada,
      };

  /// Reconstruye una tarea desde un mapa JSON.
  factory TareaObra.fromJson(Map<String, dynamic> json) => TareaObra(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        completada: (json['completada'] as bool?) ?? false,
      );
}
