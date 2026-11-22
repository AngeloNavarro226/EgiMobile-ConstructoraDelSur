import 'estado_sincronizacion.dart';

/// Tipo de elemento reutilizable guardado en el catálogo personal del ingeniero.
enum TipoPlantilla {
  tarea,
  material;

  String toStorage() => name;

  static TipoPlantilla fromStorage(String valor) => switch (valor) {
        'material' => TipoPlantilla.material,
        _ => TipoPlantilla.tarea,
      };
}

/// Elemento frecuente (tarea o material) guardado por un ingeniero para
/// agregarlo rápidamente al crear nuevas obras o editar obras en curso.
class PlantillaObra {
  const PlantillaObra({
    required this.id,
    required this.usuarioId,
    required this.tipo,
    required this.nombre,
    this.updatedAt,
    this.syncStatus = EstadoSincronizacion.synced,
    this.deletedAt,
  });

  final String id;
  final String usuarioId;
  final TipoPlantilla tipo;
  final String nombre;
  final DateTime? updatedAt;
  final EstadoSincronizacion syncStatus;
  final DateTime? deletedAt;

  PlantillaObra copyWith({
    String? usuarioId,
    TipoPlantilla? tipo,
    String? nombre,
    DateTime? updatedAt,
    EstadoSincronizacion? syncStatus,
    DateTime? deletedAt,
    bool limpiarDeletedAt = false,
  }) =>
      PlantillaObra(
        id: id,
        usuarioId: usuarioId ?? this.usuarioId,
        tipo: tipo ?? this.tipo,
        nombre: nombre ?? this.nombre,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
        deletedAt: limpiarDeletedAt ? null : (deletedAt ?? this.deletedAt),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'usuario_id': usuarioId,
        'tipo': tipo.toStorage(),
        'nombre': nombre,
        'updated_at':
            (updatedAt ?? DateTime.utc(2026)).toUtc().toIso8601String(),
        'sync_status': syncStatus.toStorage(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      };

  factory PlantillaObra.fromMap(Map<String, dynamic> map) {
    final updatedAtRaw = map['updated_at'] as String?;
    final deletedAtRaw = map['deleted_at'] as String?;
    return PlantillaObra(
      id: map['id'] as String,
      usuarioId: map['usuario_id'] as String,
      tipo: TipoPlantilla.fromStorage(map['tipo'] as String),
      nombre: map['nombre'] as String,
      updatedAt: updatedAtRaw != null ? DateTime.parse(updatedAtRaw) : null,
      syncStatus: EstadoSincronizacion.fromStorage(
        (map['sync_status'] as String?) ?? 'synced',
      ),
      deletedAt: deletedAtRaw != null ? DateTime.parse(deletedAtRaw) : null,
    );
  }
}
