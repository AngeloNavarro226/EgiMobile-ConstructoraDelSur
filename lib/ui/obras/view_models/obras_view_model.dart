import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/autenticacion_repository.dart';
import '../../../data/repositories/notificaciones_repository.dart';
import '../../../data/repositories/obras_repository.dart';
import '../../../data/repositories/preferencias_repository.dart';
import '../../../data/services/bus_de_eventos.dart';
import '../../../data/services/mapa_service.dart';
import '../../../data/services/multimedia_service.dart';
import '../../../data/services/sincronizacion_service.dart';
import '../../../data/services/voz_a_texto_service.dart';
import '../../../domain/models/evento_de_app.dart';
import '../../../domain/models/obra.dart';
import '../../../domain/models/reporte_diario.dart';
import '../../../domain/models/tarea_obra.dart';
import '../../../domain/models/ubicacion_obra.dart';
import '../../../domain/models/usuario.dart';
import '../../../plataforma/politicas.dart';

/// Estado de carga para las pantallas de obras.
enum EstadoCargaObras { cargando, exito, error }

/// ViewModel que administra la visualización y acciones sobre las obras y sus
/// informes diarios, respetando los permisos de cada rol (Capataz, Ingeniero, Dueño).
class ObrasViewModel extends ChangeNotifier {
  ObrasViewModel({
    required ObrasRepository obrasRepository,
    required AutenticacionRepository autenticacionRepository,
    required NotificacionesRepository notificacionesRepository,
    required SincronizacionService sincronizacionService,
    required MultimediaService multimediaService,
    required VozATextoService vozATextoService,
    required MapaService mapaService,
    required Politicas politicas,
    PreferenciasRepository? preferenciasRepository,
    BusDeEventos? busDeEventos,
  })  : _obrasRepository = obrasRepository,
        _autenticacionRepository = autenticacionRepository,
        _notificacionesRepository = notificacionesRepository,
        _sincronizacionService = sincronizacionService,
        _multimediaService = multimediaService,
        _vozATextoService = vozATextoService,
        _mapaService = mapaService,
        _politicas = politicas,
        _preferenciasRepository = preferenciasRepository,
        _busDeEventos = busDeEventos {
    _suscripcionConexion =
        _sincronizacionService.alDetectarConexion.listen((_) {
      unawaited(iniciarSincronizacionConAlerta());
    });
  }

  final ObrasRepository _obrasRepository;
  final AutenticacionRepository _autenticacionRepository;
  final NotificacionesRepository _notificacionesRepository;
  final SincronizacionService _sincronizacionService;
  final MultimediaService _multimediaService;
  final VozATextoService _vozATextoService;
  final MapaService _mapaService;
  final Politicas _politicas;
  final PreferenciasRepository? _preferenciasRepository;
  final BusDeEventos? _busDeEventos;

  StreamSubscription<bool>? _suscripcionConexion;
  Timer? _temporizadorAlertaSync;

  EstadoCargaObras _estado = EstadoCargaObras.cargando;
  List<Obra> _todasLasObras = [];
  List<ReporteDiario> _reportes = [];
  List<Usuario> _responsablesDisponibles = [];
  String _textoBusqueda = '';
  EstadoObra? _filtroEstadoSemaforo;
  bool _mostrarSoloFinalizadas = false;
  bool _mostrandoAlertaSincronizacion = false;
  bool _escuchandoDictadoVoz = false;
  String? _errorVozATexto;
  String? _mensajeProgresoFoto;

  /// Estado actual de la carga de datos.
  EstadoCargaObras get estado => _estado;

  /// Filtro de estado de semáforo activo al tocar uno de los chips superiores
  /// (`null` muestra todos los estados activos).
  EstadoObra? get filtroEstadoSemaforo => _filtroEstadoSemaforo;

  /// Indica si el filtro `"Finalizadas"` está seleccionado.
  ///
  /// Cuando es `false` (por defecto), las obras finalizadas se ocultan de las
  /// vistas principales; cuando es `true`, se muestran únicamente las obras
  /// finalizadas.
  bool get mostrarSoloFinalizadas => _mostrarSoloFinalizadas;

  /// Indica si se debe mostrar la alerta de 2 segundos `"Comenzando sincronización"`.
  bool get mostrandoAlertaSincronizacion => _mostrandoAlertaSincronizacion;

  /// Indica si el micrófono de transcripción de voz está activo.
  bool get escuchandoDictadoVoz => _escuchandoDictadoVoz;

  /// Último mensaje de error del servicio de micrófono, si ocurrió alguno.
  String? get errorVozATexto => _errorVozATexto;

  /// Mensaje de estado del Stream + Isolate durante la compresión de fotografías.
  String? get mensajeProgresoFoto => _mensajeProgresoFoto;

  /// Usuario autenticado actualmente.
  Usuario? get usuarioActual => _autenticacionRepository.usuarioActual;

  /// Lista de capataces/ingenieros disponibles para asignar como responsables.
  List<Usuario> get responsablesDisponibles =>
      List.unmodifiable(_responsablesDisponibles);

  /// Ubicación inicial sugerida para el selector de Google Maps.
  UbicacionObra get ubicacionPorDefecto => _mapaService.ubicacionPorDefecto;

  /// Ubicaciones frecuentes en Mendoza para el selector de Google Maps.
  List<UbicacionObra> get ubicacionesSugeridas =>
      _mapaService.ubicacionesFrecuentes;

  /// Obras visibles para el usuario activo según su rol:
  /// - Capataz: solo ve las obras de las que es responsable.
  /// - Ingeniero y Dueño: ven todas las obras.
  List<Obra> get obrasVisiblesPorRol {
    final usuario = usuarioActual;
    if (usuario == null) return List.unmodifiable(_todasLasObras);
    if (_politicas.puedeVerTodasLasObras(usuario.rol)) {
      return List.unmodifiable(_todasLasObras);
    }
    return List.unmodifiable(
      _todasLasObras.where((o) => o.responsableId == usuario.id).toList(),
    );
  }

  /// Obras filtradas según:
  /// 1. Si [mostrarSoloFinalizadas] es `true`, muestra únicamente las obras
  ///    con `finalizada == true`.
  /// 2. Si [mostrarSoloFinalizadas] es `false` (por defecto), oculta las obras
  ///    finalizadas y aplica el filtro de chip de semáforo ([filtroEstadoSemaforo]).
  /// 3. Aplica el texto de búsqueda por nombre.
  List<Obra> get obrasFiltradas {
    Iterable<Obra> resultado = obrasVisiblesPorRol;

    if (_mostrarSoloFinalizadas) {
      resultado = resultado.where((o) => o.finalizada);
    } else {
      resultado = resultado.where((o) => !o.finalizada);
      if (_filtroEstadoSemaforo != null) {
        resultado = resultado.where((o) => o.estado == _filtroEstadoSemaforo);
      }
    }

    if (_textoBusqueda.trim().isNotEmpty) {
      final consulta = _textoBusqueda.trim().toLowerCase();
      resultado =
          resultado.where((o) => o.nombre.toLowerCase().contains(consulta));
    }

    return List.unmodifiable(resultado.toList());
  }

  /// Todos los reportes diarios cargados localmente.
  List<ReporteDiario> get reportes => List.unmodifiable(_reportes);

  /// Cantidad de reportes pendientes de sincronización (`sync_status = pending`).
  int get cantidadReportesPendientes => _reportes
      .where((r) => r.syncStatus == EstadoSincronizacion.pending)
      .length;

  /// Cuenta cuántas obras activas (no finalizadas) visibles para este rol
  /// tienen el [EstadoObra] indicado.
  int cantidadPorEstado(EstadoObra estadoBuscado) => obrasVisiblesPorRol
      .where((o) => !o.finalizada && o.estado == estadoBuscado)
      .length;

  /// Cuenta cuántas obras visibles para este rol están marcadas como finalizadas.
  int get cantidadFinalizadas =>
      obrasVisiblesPorRol.where((o) => o.finalizada).length;

  /// Busca una obra puntual por su identificador.
  Obra? obtenerObraPorId(String id) {
    for (final obra in _todasLasObras) {
      if (obra.id == id) return obra;
    }
    return null;
  }

  /// Devuelve el historial de informes pasados de una obra específica.
  List<ReporteDiario> informesDeObra(String obraId) =>
      _reportes.where((r) => r.obraId == obraId).toList();

  /// Devuelve el último informe cargado para una obra, o `null` si aún no tiene.
  ReporteDiario? ultimoInformeDeObra(String obraId) {
    final lista = informesDeObra(obraId);
    if (lista.isEmpty) return null;
    return lista.first;
  }

  /// Transcribe el nombre del lugar al que apuntan las coordenadas elegidas
  /// en Google Maps.
  Future<String> obtenerNombreLugarDesdeCoordenadas(
    double latitud,
    double longitud,
  ) {
    return _mapaService.obtenerNombreLugarDesdeCoordenadas(latitud, longitud);
  }

  /// Guarda automáticamente el borrador de observaciones cuando la app pasa
  /// a segundo plano (`onHide`)
  Future<void> guardarBorradorInforme(String texto) async {
    await _preferenciasRepository?.guardarBorradorObservaciones(texto);
  }

  /// Carga las obras, reportes y responsables desde los repositorios.
  Future<void> cargar({bool forzarRecarga = false}) async {
    _estado = EstadoCargaObras.cargando;
    notifyListeners();
    try {
      await _sincronizacionService.inicializar();
      _todasLasObras = await _obrasRepository.obtenerObras(
        forzarRecarga: forzarRecarga,
      );
      _reportes = await _obrasRepository.obtenerReportes(
        forzarRecarga: forzarRecarga,
      );
      _responsablesDisponibles =
          await _autenticacionRepository.obtenerResponsablesDisponibles();
      _estado = EstadoCargaObras.exito;
    } catch (_) {
      _estado = EstadoCargaObras.error;
    } finally {
      notifyListeners();
    }
  }

  /// Actualiza el filtro de búsqueda por nombre de obra.
  void actualizarBusqueda(String texto) {
    _textoBusqueda = texto;
    notifyListeners();
  }

  /// Selecciona o deselecciona un estado de semáforo como filtro de las obras.
  void seleccionarFiltroSemaforo(EstadoObra? nuevoFiltro) {
    _mostrarSoloFinalizadas = false;
    if (_filtroEstadoSemaforo == nuevoFiltro) {
      _filtroEstadoSemaforo = null;
    } else {
      _filtroEstadoSemaforo = nuevoFiltro;
    }
    notifyListeners();
  }

  /// Activa o desactiva el filtro de obras finalizadas (cuando está activo,
  /// muestra solo las obras finalizadas; cuando está inactivo, se ocultan).
  void alternarFiltroFinalizadas(bool activo) {
    _mostrarSoloFinalizadas = activo;
    if (activo) {
      _filtroEstadoSemaforo = null;
    }
    notifyListeners();
  }

  /// Dispara la alerta visual de `"Comenzando sincronización"` durante 2 segundos
  /// y actualiza los reportes pendientes a estado `synced`.
  Future<void> iniciarSincronizacionConAlerta() async {
    _temporizadorAlertaSync?.cancel();
    _mostrandoAlertaSincronizacion = true;
    notifyListeners();

    final sincronizados = await _obrasRepository.sincronizarReportesPendientes();
    _reportes = await _obrasRepository.obtenerReportes(forzarRecarga: true);
    _busDeEventos?.emitir(SincronizacionCompletada(sincronizados));

    _temporizadorAlertaSync = Timer(const Duration(seconds: 2), () {
      _mostrandoAlertaSincronizacion = false;
      notifyListeners();
    });
  }

  /// Cambia el estado del semáforo de una obra y dispara una alerta proactiva
  /// si el nuevo estado es Amarillo (`demorada`) o Rojo (`problemas`).
  Future<void> cambiarEstadoSemaforo(
    String obraId,
    EstadoObra nuevoEstado,
  ) async {
    final actualizada = await _obrasRepository.cambiarEstadoSemaforo(
      obraId,
      nuevoEstado,
    );
    if (actualizada == null) return;

    if (nuevoEstado.requiereAlertaProactiva) {
      await _notificacionesRepository.emitirAlertaCambioSemaforo(
        obra: actualizada,
        motivo:
            'Cambio de semáforo en obra "${actualizada.nombre}" a ${nuevoEstado.etiqueta}.',
      );
    }

    _todasLasObras = await _obrasRepository.obtenerObras(forzarRecarga: true);
    notifyListeners();
  }

  /// Añade una nueva tarea a una obra y recalcula automáticamente su porcentaje.
  Future<void> agregarTareaAObra(String obraId, String nombreTarea) async {
    if (nombreTarea.trim().isEmpty) return;
    await _obrasRepository.agregarTareaAObra(obraId, nombreTarea);
    _todasLasObras = await _obrasRepository.obtenerObras(forzarRecarga: true);
    notifyListeners();
  }

  /// Marca una tarea como completada o pendiente directamente sin requerir un
  /// informe, actualizando automáticamente la barra porcentual de progreso.
  Future<void> alternarTareaCompletada(String obraId, String tareaId) async {
    await _obrasRepository.alternarTareaCompletada(obraId, tareaId);
    _todasLasObras = await _obrasRepository.obtenerObras(forzarRecarga: true);
    notifyListeners();
  }

  /// Crea una nueva obra desde la vista del Ingeniero con listado de tareas,
  /// responsable asignado, materiales a utilizar, ubicación de Google Maps y
  /// fotografía de portada personalizada opcional.
  Future<void> crearNuevaObra({
    required String nombre,
    required Usuario responsable,
    required List<String> nombresTareas,
    required List<String> materiales,
    required UbicacionObra ubicacion,
    required EstadoObra estadoInicial,
    required String observaciones,
    String? imagenPortadaPersonalizada,
  }) async {
    final tareasCreadas = [
      for (var i = 0; i < nombresTareas.length; i++)
        TareaObra(
          id: 't_${DateTime.now().microsecondsSinceEpoch}_$i',
          nombre: nombresTareas[i],
          completada: false,
        ),
    ];

    final tienePortadaPropia = imagenPortadaPersonalizada != null &&
        imagenPortadaPersonalizada.isNotEmpty;

    final nuevaObra = Obra(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      nombre: nombre.trim(),
      estado: estadoInicial,
      fechaUltimoReporte: DateTime.now(),
      responsableId: responsable.id,
      responsableNombre: responsable.nombre,
      tareas: tareasCreadas,
      materiales: materiales,
      ubicacion: ubicacion,
      observaciones: observaciones.trim(),
      conFoto: tienePortadaPropia,
      imagen: tienePortadaPropia
          ? imagenPortadaPersonalizada
          : 'assets/images/obra${(_todasLasObras.length % 6) + 1}.png',
    );

    await _obrasRepository.guardarObra(nuevaObra);
    if (estadoInicial.requiereAlertaProactiva) {
      await _notificacionesRepository.emitirAlertaCambioSemaforo(
        obra: nuevaObra,
        motivo: observaciones.trim().isEmpty
            ? 'Obra creada en estado ${estadoInicial.etiqueta}.'
            : observaciones.trim(),
      );
    }

    _todasLasObras = await _obrasRepository.obtenerObras(forzarRecarga: true);
    notifyListeners();
  }

  /// Registra un informe diario de terreno con opciones rápidas (tarea y materiales),
  /// observaciones (con soporte de dictado por voz), fotografías comprimidas y
  /// opción para marcar la obra como finalizada.
  Future<void> guardarInformeDiario({
    required Obra obra,
    required String tareaSeleccionada,
    required bool marcarTareaComoCompletada,
    required List<String> materialesGastados,
    required String observaciones,
    required EstadoObra estadoSemaforo,
    required List<FotoComprimida> fotosAdjuntas,
    bool finalizarObra = false,
  }) async {
    final autor = usuarioActual?.nombre ?? obra.responsableNombre;
    final nuevoReporte = ReporteDiario(
      id: 'rep_${DateTime.now().microsecondsSinceEpoch}',
      obraId: obra.id,
      obraNombre: obra.nombre,
      fechaCreacionLocal: DateTime.now(),
      tareaSeleccionada: tareaSeleccionada,
      tareaCompletadaEnInforme: marcarTareaComoCompletada || finalizarObra,
      materialesUsados: materialesGastados,
      observaciones: observaciones.trim(),
      urlFotos: fotosAdjuntas,
      estadoSemaforo: estadoSemaforo,
      autorNombre: autor,
      syncStatus: EstadoSincronizacion.pending,
      obraFinalizada: finalizarObra,
    );

    final obraActualizada =
        await _obrasRepository.registrarReporteDiario(nuevoReporte);

    await _preferenciasRepository?.limpiarBorradorObservaciones();
    _busDeEventos?.emitir(
      InformeGuardado(
        obraId: obra.id,
        obraFinalizada: finalizarObra,
      ),
    );

    if (obraActualizada != null && estadoSemaforo.requiereAlertaProactiva) {
      await _notificacionesRepository.emitirAlertaCambioSemaforo(
        obra: obraActualizada,
        motivo: observaciones.trim().isEmpty
            ? 'Informe diario reportó estado ${estadoSemaforo.etiqueta} en tarea "$tareaSeleccionada".'
            : observaciones.trim(),
      );
    }

    _todasLasObras = await _obrasRepository.obtenerObras(forzarRecarga: true);
    _reportes = await _obrasRepository.obtenerReportes(forzarRecarga: true);
    notifyListeners();
  }

  /// Captura o selecciona una foto real y la procesa mediante `Stream` +
  /// `Isolate` + `Workmanager` con compresión 800x600 al 70% (< 200 KB).
  Future<FotoComprimida?> adjuntarFotoComprimida({
    required bool desdeCamara,
  }) async {
    FotoComprimida? resultadoFinal;
    await for (final progreso in _multimediaService.capturarYProcesarFoto(
      desdeCamara: desdeCamara,
      anchoObjetivo: _politicas.resolucionAnchoFoto,
      altoObjetivo: _politicas.resolucionAltoFoto,
      calidadObjetivo: _politicas.calidadCompresionFoto,
      pesoMaximoKb: _politicas.pesoMaximoFotoKb,
    )) {
      _mensajeProgresoFoto = progreso.etapa;
      if (progreso.fotoComprimida != null) {
        resultadoFinal = progreso.fotoComprimida;
      }
      notifyListeners();
    }
    return resultadoFinal;
  }

  /// Inicia o detiene la transcripción real de voz a texto usando el micrófono
  /// del dispositivo (`speech_to_text`), sin textos hardcodeados.
  Future<void> alternarDictadoPorVoz({
    required void Function(String textoReconocido) onTextoReconocido,
    required void Function(String mensajeError) onErrorMicrofono,
  }) async {
    _errorVozATexto = null;
    if (_escuchandoDictadoVoz) {
      await _vozATextoService.detener();
      _escuchandoDictadoVoz = false;
      notifyListeners();
      return;
    }

    _escuchandoDictadoVoz = true;
    notifyListeners();

    final inicioExitoso = await _vozATextoService.iniciarEscucha(
      onResultado: (texto) {
        onTextoReconocido(texto);
      },
      onError: (mensaje) {
        _errorVozATexto = mensaje;
        _escuchandoDictadoVoz = false;
        onErrorMicrofono(mensaje);
        notifyListeners();
      },
      onFinalizado: () {
        _escuchandoDictadoVoz = false;
        notifyListeners();
      },
    );

    if (!inicioExitoso) {
      _escuchandoDictadoVoz = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _suscripcionConexion?.cancel();
    _temporizadorAlertaSync?.cancel();
    super.dispose();
  }
}
