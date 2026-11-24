import 'dart:math' as math;

import '../../domain/models/ubicacion_obra.dart';
import 'plataforma_io_stub.dart' if (dart.library.io) 'plataforma_io_real.dart';

/// Servicio que provee ubicaciones geográficas de referencia en Mendoza y
/// geocodificación inversa (transcripción del nombre del lugar a partir de
/// las coordenadas seleccionadas en el mapa).
class MapaService {
  /// Ubicación inicial por defecto centrada en el Gran Mendoza.
  UbicacionObra get ubicacionPorDefecto => const UbicacionObra(
        latitud: -32.8895,
        longitud: -68.8458,
        direccion: 'Av. San Martín 1100, Ciudad de Mendoza',
      );

  /// Ubicaciones sugeridas para selección rápida o marcadores en el mapa.
  List<UbicacionObra> get ubicacionesFrecuentes => const [
        UbicacionObra(
          latitud: -32.8489,
          longitud: -68.8392,
          direccion: 'Av. San Martín 1450, Las Heras, Mendoza',
        ),
        UbicacionObra(
          latitud: -32.8895,
          longitud: -68.8458,
          direccion: 'Av. Belgrano 820, Ciudad de Mendoza',
        ),
        UbicacionObra(
          latitud: -32.9254,
          longitud: -68.8130,
          direccion: 'Carril Rodríguez Peña 2300, Godoy Cruz, Mendoza',
        ),
        UbicacionObra(
          latitud: -32.9612,
          longitud: -68.8540,
          direccion: 'Ruta Panamericana Km 12, Luján de Cuyo, Mendoza',
        ),
        UbicacionObra(
          latitud: -32.9050,
          longitud: -68.7850,
          direccion: 'Acceso Este Lateral Norte, Guaymallén, Mendoza',
        ),
      ];

  /// Transcribe el nombre del lugar y dirección a partir de las coordenadas
  /// seleccionadas en el mapa.
  ///
  /// Primero consulta geocodificación inversa con un timeout de 3 segundos
  ///si el dispositivo está offline o sin red,
  /// transcribe automáticamente el corredor vial y departamento de Mendoza
  /// más cercano para garantizar que siempre muestre el nombre del lugar.
  Future<String> obtenerNombreLugarDesdeCoordenadas(
    double latitud,
    double longitud,
  ) async {
    try {
      final remoto = await consultarGeocodificacionRemota(latitud, longitud)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (remoto != null && remoto.trim().isNotEmpty) {
        return remoto;
      }
    } catch (_) {
      // Fallback inmediato al transcriptor geográfico local Offline-First.
    }
    return transcribirLugarLocalmente(latitud, longitud);
  }

  /// Resuelve de forma determinística el nombre de la zona, arteria principal
  /// y departamento según las coordenadas cuando se trabaja sin internet.
  String transcribirLugarLocalmente(double latitud, double longitud) {
    const puntosReferencia = <(double, double, String)>[
      (-32.8489, -68.8392, 'Av. San Martín, Las Heras, Mendoza'),
      (-32.8150, -68.8210, 'Ruta Nacional 40 Norte, Las Heras, Mendoza'),
      (-32.8895, -68.8458, 'Microcentro / Av. San Martín, Ciudad de Mendoza'),
      (
        -32.8930,
        -68.8615,
        'Av. Emilio Civit / Parque Gral. San Martín, Mendoza'
      ),
      (-32.9254, -68.8130, 'Carril Rodríguez Peña, Godoy Cruz, Mendoza'),
      (-32.9180, -68.8440, 'Centro / Av. San Martín Sur, Godoy Cruz, Mendoza'),
      (-32.9050, -68.7850, 'Acceso Este / Dorrego, Guaymallén, Mendoza'),
      (-32.8840, -68.7980, 'Av. Bandera de los Andes, Guaymallén, Mendoza'),
      (
        -32.9612,
        -68.8540,
        'Chacras de Coria / Ruta Panamericana, Luján de Cuyo'
      ),
      (-33.0350, -68.8780, 'Centro de Luján de Cuyo, Mendoza'),
      (-32.9770, -68.7880, 'Centro de Maipú / Calle Ozamis, Maipú, Mendoza'),
    ];

    var mejorNombre = 'Zona Gran Mendoza';
    var menorDistancia = double.infinity;

    for (final punto in puntosReferencia) {
      final dLat = latitud - punto.$1;
      final dLng = longitud - punto.$2;
      final distancia = math.sqrt(dLat * dLat + dLng * dLng);
      if (distancia < menorDistancia) {
        menorDistancia = distancia;
        mejorNombre = punto.$3;
      }
    }

    if (menorDistancia <= 0.12) {
      final cuadraEstimada =
          ((latitud.abs() * 10000).round() % 2800 + 100).toString();
      return '$mejorNombre (alt. aprox. $cuadraEstimada)';
    }

    return 'Coordenadas en Mapa (${latitud.toStringAsFixed(4)}, ${longitud.toStringAsFixed(4)})';
  }
}
