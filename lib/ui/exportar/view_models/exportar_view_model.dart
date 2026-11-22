import 'package:flutter/foundation.dart';

import '../../../data/repositories/obras_repository.dart';
import '../../../data/services/descarga_archivo_service.dart';
import '../../../domain/models/obra.dart';
import '../../../domain/models/reporte_diario.dart';

/// Formato de exportación seleccionado para cargar en el sistema legacy SIGO.
enum FormatoExportacion { csv, json }

/// ViewModel para la pantalla de exportación compartida entre todos los perfiles.
class ExportarViewModel extends ChangeNotifier {
  ExportarViewModel({
    required ObrasRepository obrasRepository,
    DescargaArchivoService descargaArchivoService =
        const DescargaArchivoService(),
  })  : _obrasRepository = obrasRepository,
        _descargaArchivoService = descargaArchivoService;

  final ObrasRepository _obrasRepository;
  final DescargaArchivoService _descargaArchivoService;

  FormatoExportacion _formato = FormatoExportacion.csv;
  String? _obraIdSeleccionada;
  bool _descargando = false;
  ResultadoDescargaArchivo? _ultimaDescarga;
  List<Obra> _obras = [];
  List<ReporteDiario> _reportes = [];

  FormatoExportacion get formato => _formato;
  String? get obraIdSeleccionada => _obraIdSeleccionada;
  bool get descargando => _descargando;
  ResultadoDescargaArchivo? get ultimaDescarga => _ultimaDescarga;
  List<Obra> get obras => List.unmodifiable(_obras);

  /// Cantidad de obras activas en el estado de semáforo indicado.
  int cantidadPorEstado(EstadoObra estado) =>
      _obras.where((o) => !o.finalizada && o.estado == estado).length;

  /// Contenido generado en formato CSV (con el paquete `csv`) o JSON listo
  /// para descargar o copiar.
  String get contenidoExportado => _formato == FormatoExportacion.csv
      ? _obrasRepository.generarCsvParaSigo(
          obras: _obras,
          reportes: _reportes,
          obraIdFiltro: _obraIdSeleccionada,
        )
      : _obrasRepository.generarJsonParaSigo(
          obras: _obras,
          reportes: _reportes,
          obraIdFiltro: _obraIdSeleccionada,
        );

  /// Sincroniza el estado del ViewModel con las obras y reportes actuales.
  Future<void> actualizarDatos() async {
    _obras = await _obrasRepository.obtenerObras();
    _reportes = await _obrasRepository.obtenerReportes();
    notifyListeners();
  }

  /// Cambia entre exportación CSV y JSON.
  void cambiarFormato(FormatoExportacion nuevoFormato) {
    _formato = nuevoFormato;
    notifyListeners();
  }

  /// Filtra la exportación para una obra específica o todas (`null`).
  void seleccionarObraFiltro(String? obraId) {
    _obraIdSeleccionada = obraId;
    notifyListeners();
  }

  /// Genera y descarga un archivo físico (`.csv` o `.json`) con la información
  /// y el formato seleccionado.
  Future<ResultadoDescargaArchivo> exportarYDescargarArchivo() async {
    _descargando = true;
    notifyListeners();
    try {
      String? nombreObraFiltro;
      if (_obraIdSeleccionada != null) {
        for (final obra in _obras) {
          if (obra.id == _obraIdSeleccionada) {
            nombreObraFiltro = obra.nombre;
            break;
          }
        }
      }

      final resultado = await _descargaArchivoService.descargarArchivo(
        contenido: contenidoExportado,
        extensionArchivo: _formato == FormatoExportacion.csv ? 'csv' : 'json',
        sufijoObra: nombreObraFiltro,
      );
      _ultimaDescarga = resultado;
      return resultado;
    } finally {
      _descargando = false;
      notifyListeners();
    }
  }
}
