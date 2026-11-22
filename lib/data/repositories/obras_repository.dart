import 'dart:convert';

import 'package:csv/csv.dart';

import '../../domain/models/evento_de_app.dart';
import '../../domain/models/obra.dart';
import '../../domain/models/reporte_diario.dart';
import '../../domain/models/tarea_obra.dart';
import '../services/base_datos_local_service.dart';
import '../services/bus_de_eventos.dart';
import '../services/generador_ids.dart';
import '../services/motor_sincronizacion.dart';
import '../services/reloj.dart';

/// Fuente de verdad para las obras activas y los reportes diarios de obra.
///
/// Gestiona la conversión entre los mapas crudos de [BaseDatosLocalService] y
/// los modelos de dominio [Obra] y [ReporteDiario], delega la sincronización
/// bidireccional a [MotorSincronizacion] y provee exportación SIGO.
class ObrasRepository {
  ObrasRepository({
    required BaseDatosLocalService baseDatosService,
    Reloj reloj = const RelojDelSistema(),
    GeneradorIds? generadorIds,
    MotorSincronizacion? motorSincronizacion,
    BusDeEventos? busDeEventos,
  })  : _baseDatosService = baseDatosService,
        _reloj = reloj,
        _generadorIds = generadorIds ?? GeneradorUuidV4(),
        _motorSincronizacion = motorSincronizacion ??
            MotorSincronizacion(
              baseDatosLocal: baseDatosService,
              reloj: reloj,
              busDeEventos: busDeEventos,
            ),
        _busDeEventos = busDeEventos;

  final BaseDatosLocalService _baseDatosService;
  final Reloj _reloj;
  final GeneradorIds _generadorIds;
  final MotorSincronizacion _motorSincronizacion;
  final BusDeEventos? _busDeEventos;

  List<Obra>? _cacheObras;
  List<ReporteDiario>? _cacheReportes;

  /// Obtiene la lista de obras con filtro opcional por responsable y paginación.
  Future<List<Obra>> obtenerObras({
    bool forzarRecarga = false,
    int? limite,
    int? desplazamiento,
    String? responsableId,
  }) async {
    final esConsultaCompleta =
        limite == null && desplazamiento == null && responsableId == null;
    final enCache = _cacheObras;
    if (esConsultaCompleta && enCache != null && !forzarRecarga) return enCache;

    final crudos = await _baseDatosService.obtenerObrasCrudas(
      limite: limite,
      desplazamiento: desplazamiento,
      responsableId: responsableId,
    );
    final obras = crudos.map(Obra.fromMap).toList();
    if (esConsultaCompleta) {
      _cacheObras = obras;
    }
    return obras;
  }

  /// Obtiene los reportes diarios ordenados por fecha descendente.
  Future<List<ReporteDiario>> obtenerReportes({
    bool forzarRecarga = false,
    int? limite,
    int? desplazamiento,
  }) async {
    final esConsultaCompleta = limite == null && desplazamiento == null;
    final enCache = _cacheReportes;
    if (esConsultaCompleta && enCache != null && !forzarRecarga) return enCache;

    final crudos = await _baseDatosService.obtenerReportesCrudos(
      limite: limite,
      desplazamiento: desplazamiento,
    );
    final reportes = crudos.map(ReporteDiario.fromMap).toList();
    if (esConsultaCompleta) {
      _cacheReportes = reportes;
    }
    return reportes;
  }

  /// Consulta directamente en SQLite el historial de reportes de una obra puntual.
  Future<List<ReporteDiario>> obtenerReportesPorObra(
    String obraId, {
    int? limite,
    int? desplazamiento,
  }) async {
    final crudos = await _baseDatosService.obtenerReportesPorObraCrudos(
      obraId,
      limite: limite,
      desplazamiento: desplazamiento,
    );
    return crudos.map(ReporteDiario.fromMap).toList();
  }

  /// Guarda una nueva obra o actualiza una existente con `sync_status = pending`.
  Future<void> guardarObra(Obra obra) async {
    final ahoraUtc = _reloj.ahora().toUtc();
    final obraConSync = obra.copyWith(
      updatedAt: ahoraUtc,
      syncStatus: EstadoSincronizacion.pending,
    );
    final tareasMap = [
      for (var i = 0; i < obraConSync.tareas.length; i++)
        obraConSync.tareas[i]
            .copyWith(
              updatedAt: obraConSync.tareas[i].updatedAt ?? ahoraUtc,
              syncStatus: EstadoSincronizacion.pending,
            )
            .toMap(obraId: obraConSync.id, orden: i),
    ];
    await _baseDatosService.guardarObraCruda(
      obra: obraConSync.toMap(),
      tareas: tareasMap,
      materiales: obraConSync.materiales,
    );
    await obtenerObras(forzarRecarga: true);
    _busDeEventos?.emitir(ObrasActualizadas(obraId: obraConSync.id));
  }

  /// Cambia el estado del semáforo de una obra mediante escritura granular.
  Future<Obra?> cambiarEstadoSemaforo(
    String obraId,
    EstadoObra nuevoEstado,
  ) async {
    final obras = await obtenerObras();
    final indice = obras.indexWhere((o) => o.id == obraId);
    if (indice == -1) return null;

    final ahoraUtc = _reloj.ahora().toUtc();
    await _baseDatosService.actualizarSemaforoObraCruda(
      obraId: obraId,
      estadoSemaforo: nuevoEstado.toStorage(),
      fechaUltimoReporteUtc: ahoraUtc,
      updatedAtUtc: ahoraUtc,
    );
    final recargadas = await obtenerObras(forzarRecarga: true);
    _busDeEventos?.emitir(ObrasActualizadas(obraId: obraId));
    for (final obra in recargadas) {
      if (obra.id == obraId) return obra;
    }
    return null;
  }

  /// Marca una obra como finalizada o activa en SQLite.
  Future<Obra?> cambiarObraFinalizada(
    String obraId, {
    required bool finalizada,
  }) async {
    final obras = await obtenerObras();
    final indice = obras.indexWhere((o) => o.id == obraId);
    if (indice == -1) return null;

    final ahoraUtc = _reloj.ahora().toUtc();
    final obraActual = obras[indice];
    final tareasActualizadas = finalizada
        ? [
            for (final t in obraActual.tareas)
              t.copyWith(
                completada: true,
                updatedAt: ahoraUtc,
                syncStatus: EstadoSincronizacion.pending,
              ),
          ]
        : obraActual.tareas;

    final actualizada = obraActual.copyWith(
      finalizada: finalizada,
      tareas: tareasActualizadas,
      fechaUltimoReporte: ahoraUtc,
      updatedAt: ahoraUtc,
      syncStatus: EstadoSincronizacion.pending,
    );
    await guardarObra(actualizada);
    return actualizada;
  }

  /// Agrega una sola tarea a la obra mediante inserción granular (sin reescribir
  /// toda la obra ni el resto de tareas).
  Future<Obra?> agregarTareaAObra(String obraId, String nombreTarea) async {
    final obras = await obtenerObras();
    final indice = obras.indexWhere((o) => o.id == obraId);
    if (indice == -1) return null;

    final obraActual = obras[indice];
    final ahoraUtc = _reloj.ahora().toUtc();
    final nuevaTarea = TareaObra(
      id: _generadorIds.generar(),
      nombre: nombreTarea.trim(),
      completada: false,
      updatedAt: ahoraUtc,
      syncStatus: EstadoSincronizacion.pending,
    );
    await _baseDatosService.insertarTareaCruda(
      nuevaTarea.toMap(obraId: obraId, orden: obraActual.tareas.length),
    );
    final recargadas = await obtenerObras(forzarRecarga: true);
    _busDeEventos?.emitir(ObrasActualizadas(obraId: obraId));
    for (final obra in recargadas) {
      if (obra.id == obraId) return obra;
    }
    return null;
  }

  /// Alterna el estado de completitud de una única tarea de forma atómica.
  Future<Obra?> alternarTareaCompletada(String obraId, String tareaId) async {
    final obras = await obtenerObras();
    final indice = obras.indexWhere((o) => o.id == obraId);
    if (indice == -1) return null;

    final obraActual = obras[indice];
    TareaObra? objetivo;
    for (final tarea in obraActual.tareas) {
      if (tarea.id == tareaId) {
        objetivo = tarea;
        break;
      }
    }
    if (objetivo == null) return null;

    await _baseDatosService.actualizarEstadoTareaCruda(
      tareaId: tareaId,
      completada: !objetivo.completada,
      updatedAtUtc: _reloj.ahora().toUtc(),
    );
    final recargadas = await obtenerObras(forzarRecarga: true);
    _busDeEventos?.emitir(ObrasActualizadas(obraId: obraId));
    for (final obra in recargadas) {
      if (obra.id == obraId) return obra;
    }
    return null;
  }

  /// Registra un nuevo reporte diario con `sync_status = pending` y actualiza
  /// la obra asociada.
  Future<Obra?> registrarReporteDiario(ReporteDiario reporte) async {
    final ahoraUtc = _reloj.ahora().toUtc();
    final reporteNormalizado = reporte.copyWith(
      syncStatus: EstadoSincronizacion.pending,
      updatedAt: ahoraUtc,
    );
    await _baseDatosService.guardarReporteCrudo(
      reporte: reporteNormalizado.toMap(),
      materiales: reporteNormalizado.materialesUsados,
      fotos: reporteNormalizado.urlFotos
          .map((foto) => foto.toMap(reporteId: reporteNormalizado.id))
          .toList(),
    );
    await obtenerReportes(forzarRecarga: true);

    final obras = await obtenerObras();
    final indice = obras.indexWhere((o) => o.id == reporteNormalizado.obraId);
    if (indice == -1) return null;

    final obraActual = obras[indice];
    final tareasActualizadas = obraActual.tareas.map((t) {
      if (reporteNormalizado.obraFinalizada) {
        return t.copyWith(
          completada: true,
          updatedAt: ahoraUtc,
          syncStatus: EstadoSincronizacion.pending,
        );
      }
      if (t.nombre == reporteNormalizado.tareaSeleccionada &&
          reporteNormalizado.tareaCompletadaEnInforme) {
        return t.copyWith(
          completada: true,
          updatedAt: ahoraUtc,
          syncStatus: EstadoSincronizacion.pending,
        );
      }
      return t;
    }).toList();

    final obraActualizada = obraActual.copyWith(
      estado: reporteNormalizado.estadoSemaforo,
      fechaUltimoReporte: reporteNormalizado.fechaCreacionLocal,
      observaciones: reporteNormalizado.observaciones.isNotEmpty
          ? reporteNormalizado.observaciones
          : obraActual.observaciones,
      conFoto: reporteNormalizado.urlFotos.isNotEmpty || obraActual.conFoto,
      tareas: tareasActualizadas,
      finalizada: reporteNormalizado.obraFinalizada || obraActual.finalizada,
      updatedAt: ahoraUtc,
      syncStatus: EstadoSincronizacion.pending,
    );

    await guardarObra(obraActualizada);
    return obraActualizada;
  }

  /// Ejecuta el ciclo Push -> Pull del [MotorSincronizacion] y refresca cachés.
  Future<ResultadoSincronizacion> sincronizarTodo({
    bool permitirSimulacionLocal = true,
  }) async {
    final resultado = await _motorSincronizacion.sincronizarTodo(
      permitirSimulacionLocal: permitirSimulacionLocal,
    );
    await obtenerObras(forzarRecarga: true);
    await obtenerReportes(forzarRecarga: true);
    return resultado;
  }

  /// Flujo en tiempo real de tablas modificadas en Supabase por otros usuarios.
  Stream<String> escucharCambiosRemotos() =>
      _motorSincronizacion.escucharCambiosRemotos();

  /// Mantiene compatibilidad directa devolviendo la cantidad sincronizada.
  Future<int> sincronizarReportesPendientes() async {
    final resultado = await sincronizarTodo(permitirSimulacionLocal: true);
    return resultado.sincronizados;
  }

  /// Vacía las cachés en memoria al cerrar sesión.
  void limpiarCache() {
    _cacheObras = null;
    _cacheReportes = null;
  }

  /// Genera el contenido CSV utilizando el paquete `csv` de Dart para cargar
  /// en el sistema legacy SIGO.
  String generarCsvParaSigo({
    required List<Obra> obras,
    required List<ReporteDiario> reportes,
    String? obraIdFiltro,
  }) =>
      generarCsvParaSigoPuro(
        obras: obras,
        reportes: reportes,
        obraIdFiltro: obraIdFiltro,
      );

  /// Genera el contenido JSON estructurado para integración o auditoría SIGO.
  String generarJsonParaSigo({
    required List<Obra> obras,
    required List<ReporteDiario> reportes,
    String? obraIdFiltro,
  }) =>
      generarJsonParaSigoPuro(
        obras: obras,
        reportes: reportes,
        obraIdFiltro: obraIdFiltro,
      );
}

/// Función pura de nivel superior para ejecutar la exportación CSV en `Isolate.run`.
String generarCsvParaSigoPuro({
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
    final cantReportes = reportes.where((r) => r.obraId == obra.id).length;
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

/// Función pura de nivel superior para ejecutar la exportación JSON en `Isolate.run`.
String generarJsonParaSigoPuro({
  required List<Obra> obras,
  required List<ReporteDiario> reportes,
  String? obraIdFiltro,
}) {
  final obrasFiltradas = obraIdFiltro == null
      ? obras
      : obras.where((o) => o.id == obraIdFiltro).toList();

  final lista = obrasFiltradas.map((obra) {
    final reportesDeObra = reportes.where((r) => r.obraId == obra.id).toList();
    return {
      'id': obra.id,
      'obra': obra.nombre,
      'responsable': obra.responsableNombre,
      'ubicacion': obra.ubicacion.toJson(),
      'tarea_actual': obra.tareaActual,
      'tareas_completas': obra.tareasCompletas.map((t) => t.nombre).toList(),
      'tareas_pendientes': obra.tareasPendientes.map((t) => t.nombre).toList(),
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
