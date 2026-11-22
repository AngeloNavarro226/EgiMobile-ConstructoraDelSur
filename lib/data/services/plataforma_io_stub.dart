/// Implementación de respaldo para plataformas sin `dart:io` (como Flutter Web).
library;

import 'dart:typed_data';

/// Guarda el archivo de exportación en memoria/sesión web y devuelve la ruta
/// descriptiva de descarga.
Future<String> guardarArchivoExportadoEnPlataforma({
  required String nombreArchivo,
  required String contenido,
}) async {
  return 'Descargas/$nombreArchivo (${contenido.length} caracteres)';
}

/// En Web no existe sistema de archivos nativo; devuelve el nombre lógico.
Future<String> guardarFotoEnAlmacenamientoLocal({
  required String nombreArchivo,
  required Uint8List bytes,
}) async {
  return 'web_media/$nombreArchivo';
}

/// En Web no se leen archivos locales con `dart:io`; devuelve `null`.
Future<Uint8List?> leerBytesDeArchivoLocal(String ruta) async => null;

/// Realiza una consulta de geocodificación inversa si hay soporte nativo IO;
/// en web devuelve `null` para utilizar el transcriptor geográfico integrado.
Future<String?> consultarGeocodificacionRemota(
  double latitud,
  double longitud,
) async {
  return null;
}
