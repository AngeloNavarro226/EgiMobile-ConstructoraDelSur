import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/obras_repository.dart';
import '../../../data/services/bus_de_eventos.dart';
import '../../../data/services/descarga_archivo_service.dart';
import '../../../domain/models/evento_de_app.dart';
import '../../../domain/models/obra.dart';
import '../../../domain/models/reporte_diario.dart';
import '../../core/view_model_base.dart';

/// Formato de exportación seleccionado para cargar en el sistema legacy SIGO.
enum FormatoExportacion { csv, json }

/// ViewModel para la pantalla de exportación compartida entre todos los perfiles.
///
/// Genera el contenido CSV/JSON de forma asíncrona en segundo plano (`Isolate`)
/// ante cambios de datos, formato o filtro, evitando recalcular en cada `build()`.
class ExportarViewModel extends ViewModelBase {
  ExportarViewModel({
    required ObrasRepository obrasRepository,
    DescargaArchivoService descargaArchivoService =
        const DescargaArchivoService(),
    BusDeEventos? busDeEventos,
  })  : _obrasRepository = obrasRepository,
        _descargaArchivoService = descargaArchivoService,
        _busDeEventos = busDeEventos {
    _suscripcionEventos = _busDeEventos?.stream.listen(_procesarEventoGlobal);
  }

  final ObrasRepository _obrasRepository;
  final DescargaArchivoService _descargaArchivoService;
  final BusDeEventos? _busDeEventos;
  StreamSubscription<EventoDeApp>? _suscripcionEventos;

  EstadoOperacion _estado = EstadoOperacion.inicial;
  FormatoExportacion _formato = FormatoExportacion.csv;
  String? _obraIdSeleccionada;
  bool _descargando = false;
  ResultadoDescargaArchivo? _ultimaDescarga;
  String? _mensajeError;
  List<Obra> _obras = [];
  List<ReporteDiario> _reportes = [];
  String _contenidoCacheado = '';

  EstadoOperacion get estado => _estado;
  FormatoExportacion get formato => _formato;
  String? get obraIdSeleccionada => _obraIdSeleccionada;
  bool get descargando => _descargando;
  ResultadoDescargaArchivo? get ultimaDescarga => _ultimaDescarga;
  String? get mensajeError => _mensajeError;
  List<Obra> get obras => List.unmodifiable(_obras);

  /// Cantidad de obras activas en el estado de semáforo indicado.
  int cantidadPorEstado(EstadoObra estado) =>
      _obras.where((o) => !o.finalizada && o.estado == estado).length;

  /// Contenido CSV o JSON precomputado listo para mostrar, copiar o descargar.
  String get contenidoExportado => _contenidoCacheado;

  /// Sincroniza el estado del ViewModel con las obras y reportes actuales
  /// y regenera el contenido exportado en segundo plano.
  Future<void> actualizarDatos() async {
    _estado = EstadoOperacion.cargando;
    _mensajeError = null;
    notificarSiActivo();

    try {
      _obras = await _obrasRepository.obtenerObras();
      _reportes = await _obrasRepository.obtenerReportes();
      _contenidoCacheado = await _generarContenidoAsincrono();
      _estado = EstadoOperacion.exito;
      notificarSiActivo();
    } catch (e) {
      _estado = EstadoOperacion.error;
      _mensajeError = 'No se pudieron actualizar los datos de exportación: $e';
      notificarSiActivo();
    }
  }

  /// Cambia entre exportación CSV y JSON regenerando el archivo en segundo plano.
  void cambiarFormato(FormatoExportacion nuevoFormato) {
    if (_formato == nuevoFormato) return;
    _formato = nuevoFormato;
    unawaited(_regenerarContenido());
  }

  /// Filtra la exportación para una obra específica o todas (`null`).
  void seleccionarObraFiltro(String? obraId) {
    if (_obraIdSeleccionada == obraId) return;
    _obraIdSeleccionada = obraId;
    unawaited(_regenerarContenido());
  }

  Future<void> _regenerarContenido() async {
    _estado = EstadoOperacion.cargando;
    _mensajeError = null;
    notificarSiActivo();

    try {
      _contenidoCacheado = await _generarContenidoAsincrono();
      _estado = EstadoOperacion.exito;
      notificarSiActivo();
    } catch (e) {
      _estado = EstadoOperacion.error;
      _mensajeError = 'No se pudo generar el archivo de exportación: $e';
      notificarSiActivo();
    }
  }

  Future<String> _generarContenidoAsincrono() async {
    final obrasSnapshot = List<Obra>.from(_obras);
    final reportesSnapshot = List<ReporteDiario>.from(_reportes);
    final formatoActual = _formato;
    final filtro = _obraIdSeleccionada;

    if (kIsWeb) {
      return formatoActual == FormatoExportacion.csv
          ? generarCsvParaSigoPuro(
              obras: obrasSnapshot,
              reportes: reportesSnapshot,
              obraIdFiltro: filtro,
            )
          : generarJsonParaSigoPuro(
              obras: obrasSnapshot,
              reportes: reportesSnapshot,
              obraIdFiltro: filtro,
            );
    }

    return Isolate.run(
      () => formatoActual == FormatoExportacion.csv
          ? generarCsvParaSigoPuro(
              obras: obrasSnapshot,
              reportes: reportesSnapshot,
              obraIdFiltro: filtro,
            )
          : generarJsonParaSigoPuro(
              obras: obrasSnapshot,
              reportes: reportesSnapshot,
              obraIdFiltro: filtro,
            ),
    );
  }

  /// Genera y descarga un archivo físico (`.csv` o `.json`) con la información
  /// y el formato seleccionado.
  Future<ResultadoDescargaArchivo?> exportarYDescargarArchivo() async {
    _descargando = true;
    _mensajeError = null;
    notificarSiActivo();

    try {
      if (_contenidoCacheado.isEmpty) {
        _contenidoCacheado = await _generarContenidoAsincrono();
      }

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
        contenido: _contenidoCacheado,
        extensionArchivo: _formato == FormatoExportacion.csv ? 'csv' : 'json',
        sufijoObra: nombreObraFiltro,
      );
      _ultimaDescarga = resultado;
      _descargando = false;
      _estado = EstadoOperacion.exito;
      notificarSiActivo();
      return resultado;
    } catch (e) {
      _descargando = false;
      _estado = EstadoOperacion.error;
      _mensajeError = 'No se pudo descargar el archivo: $e';
      notificarSiActivo();
      return null;
    }
  }

  void _procesarEventoGlobal(EventoDeApp evento) {
    switch (evento) {
      case ObrasActualizadas() ||
            InformeGuardado() ||
            SincronizacionCompletada() ||
            SesionIniciada():
        unawaited(actualizarDatos());
      case SesionCerrada():
        _obras = [];
        _reportes = [];
        _obraIdSeleccionada = null;
        _contenidoCacheado = '';
        _ultimaDescarga = null;
        _mensajeError = null;
        _estado = EstadoOperacion.inicial;
        notificarSiActivo();
      default:
        break;
    }
  }

  @override
  void dispose() {
    _suscripcionEventos?.cancel();
    super.dispose();
  }
}
