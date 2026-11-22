/// Representa una tarea individual dentro del plan de trabajo de una obra.
class TareaObra {
  const TareaObra({
    required this.id,
    required this.nombre,
    this.completada = false,
  });

  final String id;
  final String nombre;
  final bool completada;

  /// Devuelve una copia de la tarea con su estado actualizado.
  TareaObra copyWith({
    String? nombre,
    bool? completada,
  }) =>
      TareaObra(
        id: id,
        nombre: nombre ?? this.nombre,
        completada: completada ?? this.completada,
      );

  /// Convierte la tarea a un mapa serializable en JSON para SQLite.
  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'completada': completada,
      };

  /// Reconstruye una tarea desde un mapa JSON almacenado en SQLite.
  factory TareaObra.fromJson(Map<String, dynamic> json) => TareaObra(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        completada: (json['completada'] as bool?) ?? false,
      );
}
