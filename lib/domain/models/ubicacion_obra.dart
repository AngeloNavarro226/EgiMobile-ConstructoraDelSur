/// Coordenadas geográficas y dirección de una obra seleccionada en el mapa.
class UbicacionObra {
  const UbicacionObra({
    required this.latitud,
    required this.longitud,
    required this.direccion,
  });

  final double latitud;
  final double longitud;
  final String direccion;

  /// Texto formateado con la dirección y coordenadas para mostrar en la vista.
  String get etiquetaCompleta =>
      '$direccion (${latitud.toStringAsFixed(4)}, ${longitud.toStringAsFixed(4)})';

  /// Convierte la ubicación a un mapa JSON para persistencia en SQLite.
  Map<String, dynamic> toJson() => {
        'latitud': latitud,
        'longitud': longitud,
        'direccion': direccion,
      };

  /// Reconstruye la ubicación desde un mapa JSON.
  factory UbicacionObra.fromJson(Map<String, dynamic> json) => UbicacionObra(
        latitud: (json['latitud'] as num).toDouble(),
        longitud: (json['longitud'] as num).toDouble(),
        direccion: json['direccion'] as String,
      );
}
