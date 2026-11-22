import 'plataforma_io_stub.dart'
    if (dart.library.io) 'plataforma_io_real.dart';

/// Resultado de la descarga de un archivo de exportación para SIGO.
class ResultadoDescargaArchivo {
  const ResultadoDescargaArchivo({
    required this.nombreArchivo,
    required this.rutaGuardada,
    required this.bytesEscritos,
  });

  final String nombreArchivo;
  final String rutaGuardada;
  final int bytesEscritos;
}

/// Servicio que genera y descarga un archivo real (`.csv` o `.json`) con la
/// información de las obras e informes en el formato seleccionado.
class DescargaArchivoService {
  const DescargaArchivoService();

  /// Guarda el contenido exportado en un archivo físico y devuelve su ubicación.
  Future<ResultadoDescargaArchivo> descargarArchivo({
    required String contenido,
    required String extensionArchivo,
    String? sufijoObra,
  }) async {
    final ahora = DateTime.now();
    final fecha =
        '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}';
    final limpio = (sufijoObra == null || sufijoObra.trim().isEmpty)
        ? 'todas_las_obras'
        : sufijoObra
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final nombreArchivo = 'exportacion_sigo_${limpio}_$fecha.$extensionArchivo';

    final rutaGuardada = await guardarArchivoExportadoEnPlataforma(
      nombreArchivo: nombreArchivo,
      contenido: contenido,
    );

    return ResultadoDescargaArchivo(
      nombreArchivo: nombreArchivo,
      rutaGuardada: rutaGuardada,
      bytesEscritos: contenido.length,
    );
  }
}
