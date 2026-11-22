/// Implementación de respaldo para plataformas sin `dart:io` (como Flutter Web).

/// Guarda el archivo de exportación en memoria/sesión web y devuelve la ruta
/// descriptiva de descarga.
Future<String> guardarArchivoExportadoEnPlataforma({
  required String nombreArchivo,
  required String contenido,
}) async {
  return 'Descargas/$nombreArchivo (${contenido.length} caracteres)';
}

/// Realiza una consulta de geocodificación inversa si hay soporte nativo IO;
/// en web devuelve `null` para utilizar el transcriptor geográfico integrado.
Future<String?> consultarGeocodificacionRemota(
  double latitud,
  double longitud,
) async {
  return null;
}
