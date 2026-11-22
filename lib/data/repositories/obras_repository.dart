import 'dart:convert';

import 'package:csv/csv.dart';

import '../../domain/models/obra.dart';
import '../../domain/models/reporte_diario.dart';
import '../../domain/models/tarea_obra.dart';
import '../services/base_datos_local_service.dart';
import '../services/reloj.dart';

/// Fuente de verdad para las obras activas y los reportes diarios de obra.
///
/// Gestiona la conversión entre los mapas crudos de [BaseDatosLocalService] y
/// los modelos de dominio [Obra] y [ReporteDiario], manteniendo una caché en
/// memoria y proveyendo la exportación compatible con el sistema legacy SIGO.
class ObrasRepository {
  ObrasRepository({
    required BaseDatosLocalService baseDatosService,
    Reloj reloj = const RelojDelSistema(),
  })  : _baseDatosService = baseDatosService,
        _reloj = reloj;

  final BaseDatosLocalService _baseDatosService;
  final Reloj _reloj;

  List<Obra>? _cacheObras;
  List<ReporteDiario>? _cacheReportes;

  /// Obtiene la lista de todas las obras registradas.
  Future<List<Obra>> obtenerObras({bool forzarRecarga = false}) async {
    final enCache = _cacheObras;
    if (enCache != null && !forzarRecarga) return enCache;

    final crudos = await _baseDatosService.obtenerObrasCrudas();
    final obras = crudos.map(Obra.fromMap).toList();
    _cacheObras = obras;
    return obras;
  }

  /// Obtiene todos los reportes diarios ordenados por fecha descendente.
  Future<List<ReporteDiario>> obtenerReportes({
    bool forzarRecarga = false,
  }) async {
    final enCache = _cacheReportes;
    if (enCache != null && !forzarRecarga) return enCache;

    final crudos = await _baseDatosService.obtenerReportesCrudos();
    final reportes = crudos.map(ReporteDiario.fromMap).toList();
    _cacheReportes = reportes;
    return reportes;
  }

  /// Filtra el historial de reportes diarios correspondientes a una obra puntual.
  Future<List<ReporteDiario>> obtenerReportesPorObra(String obraId) async {
    final todos = await obtenerReportes();
    return todos.where((r) => r.obraId == obraId).toList();
  }

  /// Guarda una nueva obra o actualiza una existente en SQLite y refresca la caché.
  Future<void> guardarObra(Obra obra) async {
    await _baseDatosService.guardarObraCruda(obra.toMap());
    await obtenerObras(forzarRecarga: true);
  }

  /// Cambia el estado del semáforo de una obra y devuelve la obra actualizada.
  Future<Obra?> cambiarEstadoSemaforo(
    String obraId,
    EstadoObra nuevoEstado,
  ) async {
    final obras = await obtenerObras();
    final indice = obras.indexWhere((o) => o.id == obraId);
    if (indice == -1) return null;

    final actualizada = obras[indice].copyWith(
      estado: nuevoEstado,
      fechaUltimoReporte: _reloj.ahora(),
    );
    await guardarObra(actualizada);
    return actualizada;
  }

  /// Marca una obra como finalizada o activa en SQLite.
  Future<Obra?> cambiarObraFinalizada(
    String obraId, {
    required bool finalizada,
  }) async {
    final obras = await obtenerObras();
    final indice = obras.indexWhere((o) => o.id == obraId);
    if (indice == -1) return null;

    final obraActual = obras[indice];
    final tareasActualizadas = finalizada
        ? [for (final t in obraActual.tareas) t.copyWith(completada: true)]
        : obraActual.tareas;

    final actualizada = obraActual.copyWith(
      finalizada: finalizada,
      tareas: tareasActualizadas,
      fechaUltimoReporte: _reloj.ahora(),
    );
    await guardarObra(actualizada);
    return actualizada;
  }

  /// Agrega una nueva tarea al listado de tareas de una obra, recalculando
  /// automáticamente su porcentaje de avance.
  Future<Obra?> agregarTareaAObra(String obraId, String nombreTarea) async {
    final obras = await obtenerObras();
    final indice = obras.indexWhere((o) => o.id == obraId);
    if (indice == -1) return null;

    final obraActual = obras[indice];
    final nuevaTarea = TareaObra(
      id: 't_${_reloj.ahora().microsecondsSinceEpoch}',
      nombre: nombreTarea.trim(),
      completada: false,
    );
    final actualizada = obraActual.copyWith(
      tareas: [...obraActual.tareas, nuevaTarea],
    );
    await guardarObra(actualizada);
    return actualizada;
  }

  /// Alterna el estado de completitud de una tarea de la obra, lo que actualiza
  /// automáticamente la barra porcentual de progreso.
  Future<Obra?> alternarTareaCompletada(String obraId, String tareaId) async {
    final obras = await obtenerObras();
    final indice = obras.indexWhere((o) => o.id == obraId);
    if (indice == -1) return null;

    final obraActual = obras[indice];
    final nuevasTareas = obraActual.tareas.map((tarea) {
      if (tarea.id != tareaId) return tarea;
      return tarea.copyWith(completada: !tarea.completada);
    }).toList();

    final actualizada = obraActual.copyWith(tareas: nuevasTareas);
    await guardarObra(actualizada);
    return actualizada;
  }

  /// Registra un nuevo reporte diario con `sync_status = pending` y actualiza
  /// la obra asociada (observaciones, estado del semáforo, tarea completada y
  /// finalización de la obra si corresponde).
  Future<Obra?> registrarReporteDiario(ReporteDiario reporte) async {
    await _baseDatosService.guardarReporteCrudo(reporte.toMap());
    await obtenerReportes(forzarRecarga: true);

    final obras = await obtenerObras();
    final indice = obras.indexWhere((o) => o.id == reporte.obraId);
    if (indice == -1) return null;

    final obraActual = obras[indice];
    final tareasActualizadas = obraActual.tareas.map((t) {
      if (reporte.obraFinalizada) {
        return t.copyWith(completada: true);
      }
      if (t.nombre == reporte.tareaSeleccionada &&
          reporte.tareaCompletadaEnInforme) {
        return t.copyWith(completada: true);
      }
      return t;
    }).toList();

    final obraActualizada = obraActual.copyWith(
      estado: reporte.estadoSemaforo,
      fechaUltimoReporte: reporte.fechaCreacionLocal,
      observaciones: reporte.observaciones.isNotEmpty
          ? reporte.observaciones
          : obraActual.observaciones,
      conFoto: reporte.urlFotos.isNotEmpty || obraActual.conFoto,
      tareas: tareasActualizadas,
      finalizada: reporte.obraFinalizada || obraActual.finalizada,
    );

    await guardarObra(obraActualizada);
    return obraActualizada;
  }

  /// Sincroniza los reportes locales pendientes (`pending` -> `synced`).
  Future<int> sincronizarReportesPendientes() async {
    final cantidad = await _baseDatosService.marcarReportesComoSincronizados(
      _reloj.ahora(),
    );
    await obtenerReportes(forzarRecarga: true);
    return cantidad;
  }

  /// Genera el contenido CSV utilizando el paquete `csv` de Dart para cargar
  /// en el sistema legacy SIGO. Permite exportar todas las obras o una puntual.
  String generarCsvParaSigo({
    required List<Obra> obras,
    required List<ReporteDiario> reportes,
    String? obraIdFiltro,
  }) {
    final obrasFiltradas = obraIdFiltro == null
        ? obras
        : obras.where((o) => o.id == obraIdFiltro).toList();

    final filas = <List<dynamic>>[
      [
        'obra_id',
        'obra',
        'responsable',
        'ubicacion',
        'tarea_actual',
        'tareas_completas',
        'tareas_totales',
        'avance_pct',
        'estado_semaforo',
        'finalizada',
        'materiales_asignados',
        'observaciones',
        'fecha_ultimo_reporte',
        'reportes_cargados',
      ],
    ];

    for (final obra in obrasFiltradas) {
      final cantReportes =
          reportes.where((r) => r.obraId == obra.id).length;
      filas.add([
        obra.id,
        obra.nombre,
        obra.responsableNombre,
        obra.ubicacion.direccion,
        obra.tareaActual,
        obra.tareasCompletas.length,
        obra.tareas.length,
        obra.porcentajeAvance,
        obra.estado.etiqueta,
        obra.finalizada ? 'Si' : 'No',
        obra.materiales.join(' | '),
        obra.observaciones,
        obra.fechaUltimoReporte.toIso8601String().substring(0, 10),
        cantReportes,
      ]);
    }

    return const ListToCsvConverter().convert(filas);
  }

  /// Genera el contenido JSON estructurado para integración o auditoría SIGO.
  String generarJsonParaSigo({
    required List<Obra> obras,
    required List<ReporteDiario> reportes,
    String? obraIdFiltro,
  }) {
    final obrasFiltradas = obraIdFiltro == null
        ? obras
        : obras.where((o) => o.id == obraIdFiltro).toList();

    final lista = obrasFiltradas.map((obra) {
      final reportesDeObra =
          reportes.where((r) => r.obraId == obra.id).toList();
      return {
        'id': obra.id,
        'obra': obra.nombre,
        'responsable': obra.responsableNombre,
        'ubicacion': obra.ubicacion.toJson(),
        'tarea_actual': obra.tareaActual,
        'tareas_completas': obra.tareasCompletas.map((t) => t.nombre).toList(),
        'tareas_pendientes':
            obra.tareasPendientes.map((t) => t.nombre).toList(),
        'avance_pct': obra.porcentajeAvance,
        'estado': obra.estado.etiqueta,
        'finalizada': obra.finalizada,
        'materiales': obra.materiales,
        'observaciones': obra.observaciones,
        'fecha_ultimo_reporte':
            obra.fechaUltimoReporte.toIso8601String().substring(0, 10),
        'historial_informes': reportesDeObra
            .map(
              (r) => {
                'id': r.id,
                'fecha': r.fechaCreacionLocal.toIso8601String().substring(0, 16),
                'tarea': r.tareaSeleccionada,
                'materiales_gastados': r.materialesUsados,
                'observaciones': r.observaciones,
                'sync_status': r.syncStatus.name,
                'obra_finalizada': r.obraFinalizada,
                'fotos_comprimidas': r.urlFotos.length,
              },
            )
            .toList(),
      };
    }).toList();

    return const JsonEncoder.withIndent('  ').convert(lista);
  }
}
