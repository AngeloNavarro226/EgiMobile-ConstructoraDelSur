import 'dart:convert';
import 'dart:io';

/// Implementación  sobre `dart:io` para Android, iOS, Windows, macOS y Linux.

/// Escribe físicamente el archivo `.csv` o `.json` en el almacenamiento del
/// dispositivo (intentando primero la carpeta pública `Download` en Android o
/// el directorio de descargas/temporal del sistema) y devuelve la ruta completa.
Future<String> guardarArchivoExportadoEnPlataforma({
  required String nombreArchivo,
  required String contenido,
}) async {
  final directoriosCandidatos = <Directory>[
    Directory('/storage/emulated/0/Download'),
    Directory.systemTemp,
  ];

  for (final dir in directoriosCandidatos) {
    try {
      if (await dir.exists()) {
        final separador = Platform.pathSeparator;
        final rutaCompleta = '${dir.path}$separador$nombreArchivo';
        final archivo = File(rutaCompleta);
        await archivo.writeAsString(contenido, flush: true);
        return archivo.path;
      }
    } catch (_) {
      // Si el directorio público de descargas requiere permisos adicionales en
      // una versión específica de Android, continúa con Directory.systemTemp.
    }
  }

  final archivoFallback = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}$nombreArchivo',
  );
  await archivoFallback.writeAsString(contenido, flush: true);
  return archivoFallback.path;
}

/// Consulta el nombre real de la calle y localidad mediante geocodificación
/// inversa HTTP aplicando `.timeout(const Duration(seconds: 3))`
Future<String?> consultarGeocodificacionRemota(
  double latitud,
  double longitud,
) async {
  final cliente = HttpClient();
  try {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?format=jsonv2'
      '&lat=${latitud.toStringAsFixed(6)}&lon=${longitud.toStringAsFixed(6)}'
      '&accept-language=es',
    );
    final peticion = await cliente
        .getUrl(uri)
        .timeout(const Duration(seconds: 3));
    peticion.headers.set(
      HttpHeaders.userAgentHeader,
      'ConstructoraDelSurApp/2.3 (Mendoza)',
    );
    final respuesta = await peticion
        .close()
        .timeout(const Duration(seconds: 3));
    if (respuesta.statusCode != 200) return null;

    final cuerpo = await respuesta
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 3));
    final json = jsonDecode(cuerpo) as Map<String, dynamic>;

    final address = json['address'] as Map<String, dynamic>?;
    if (address != null) {
      final calle = (address['road'] ??
              address['pedestrian'] ??
              address['suburb'] ??
              address['neighbourhood'])
          ?.toString();
      final altura = address['house_number']?.toString();
      final localidad = (address['city'] ??
              address['town'] ??
              address['municipality'] ??
              address['county'] ??
              address['state_district'])
          ?.toString();
      final provincia = (address['state'] ?? 'Mendoza').toString();

      final partes = <String>[
        if (calle != null && calle.isNotEmpty)
          altura != null ? '$calle $altura' : calle,
        if (localidad != null && localidad.isNotEmpty) localidad,
        if (provincia.isNotEmpty) provincia,
      ];
      if (partes.isNotEmpty) {
        return partes.join(', ');
      }
    }

    final displayName = json['display_name']?.toString();
    if (displayName != null && displayName.trim().isNotEmpty) {
      final fragmentos = displayName.split(',').take(3).map((e) => e.trim());
      return fragmentos.join(', ');
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    cliente.close(force: true);
  }
}
