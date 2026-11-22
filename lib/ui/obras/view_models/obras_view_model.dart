import 'dart:async';

import '../../../data/repositories/autenticacion_repository.dart';
import '../../../data/repositories/notificaciones_repository.dart';
import '../../../data/repositories/obras_repository.dart';
import '../../../data/repositories/preferencias_repository.dart';
import '../../../data/services/bus_de_eventos.dart';
import '../../../data/services/generador_ids.dart';
import '../../../data/services/mapa_service.dart';
import '../../../data/services/multimedia_service.dart';
import '../../../data/services/reloj.dart';
import '../../../data/services/sincronizacion_service.dart';
import '../../../data/services/voz_a_texto_service.dart';
import '../../../domain/models/evento_de_app.dart';
import '../../../domain/models/obra.dart';
import '../../../domain/models/plantilla_obra.dart';
import '../../../domain/models/reporte_diario.dart';
import '../../../domain/models/tarea_obra.dart';
import '../../../domain/models/ubicacion_obra.dart';
import '../../../domain/models/usuario.dart';
import '../../../plataforma/politicas.dart';
import '../../core/view_model_base.dart';

/// Estado de carga para las pantallas de obras.
enum EstadoCargaObras { cargando, exito, error }

/// ViewModel que administra la visualización y acciones sobre las obras y sus
/// informes diarios, respetando los permisos de cada rol (Capataz, Ingeniero, Dueño).
class ObrasViewModel extends ViewModelBase {
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
    Reloj reloj = const RelojDelSistema(),
    GeneradorIds? generadorIds,
  })  : _obrasRepository = obrasRepository,
        _autenticacionRepository = autenticacionRepository,
        _notificacionesRepository = notificacionesRepository,
        _sincronizacionService = sincronizacionService,
        _multimediaService = multimediaService,
        _vozATextoService = vozATextoService,
        _mapaService = mapaService,
        _politicas = politicas,
        _preferenciasRepository = preferenciasRepository,
        _busDeEventos = busDeEventos,
        _reloj = reloj,
        _generadorIds = generadorIds ?? GeneradorUuidV4() {
    _suscripcionConexion =
        _sincronizacionService.alDetectarConexion.listen((_) {
      unawaited(iniciarSincronizacionConAlerta());
    });
    _suscripcionEventos = _busDeEventos?.stream.listen(_procesarEventoGlobal);
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
  final Reloj _reloj;
  final GeneradorIds _generadorIds;

  StreamSubscription<bool>? _suscripcionConexion;
  StreamSubscription<EventoDeApp>? _suscripcionEventos;
  StreamSubscription<String>? _suscripcionRealtime;
  Timer? _temporizadorAlertaSync;
  Timer? _debounceRealtime;
  Timer? _temporizadorRespaldoSync;

  EstadoCargaObras _estado = EstadoCargaObras.cargando;
  bool _guardando = false;
  bool _sincronizando = false;
  bool _syncPendienteAlTerminar = false;
  bool _cargandoReportesObra = false;
  String? _mensajeError;
  String? _mensajeErrorSincronizacion;

  List<Obra> _todasLasObras = [];
  List<ReporteDiario> _reportes = [];
  final Map<String, List<ReporteDiario>> _reportesPorObraCache = {};
  List<Usuario> _responsablesDisponibles = [];
  List<PlantillaObra> _plantillasPersonales = [];
  String _textoBusqueda = '';
  EstadoObra? _filtroEstadoSemaforo;
  bool _mostrarSoloFinalizadas = false;
  bool _mostrandoAlertaSincronizacion = false;
  bool _escuchandoDictadoVoz = false;
  bool _procesandoFoto = false;
  String? _errorVozATexto;
  String? _mensajeProgresoFoto;

  /// Estado actual de la carga de datos.
  EstadoCargaObras get estado => _estado;

  /// Indica si hay una escritura o guardado en curso.
  bool get guardando => _guardando;

  /// Indica si hay una sincronización en curso.
  bool get sincronizando => _sincronizando;

  /// Indica si se está cargando el historial de reportes de una obra.
  bool get cargandoReportesObra => _cargandoReportesObra;

  /// Indica si se está procesando una fotografía en segundo plano.
  bool get procesandoFoto => _procesandoFoto;

  /// Último mensaje de error de carga o guardado.
  String? get mensajeError => _mensajeError;

  /// Último error reportado durante la sincronización Offline-First.
  String? get mensajeErrorSincronizacion => _mensajeErrorSincronizacion;

  /// Filtro de estado de semáforo activo al tocar uno de los chips superiores.
  EstadoObra? get filtroEstadoSemaforo => _filtroEstadoSemaforo;

  /// Indica si el filtro `"Finalizadas"` está seleccionado.
  bool get mostrarSoloFinalizadas => _mostrarSoloFinalizadas;

  /// Indica si se debe mostrar la alerta de `"Comenzando sincronización"`.
  bool get mostrandoAlertaSincronizacion => _mostrandoAlertaSincronizacion;

  /// Indica si el micrófono de transcripción de voz está activo.
  bool get escuchandoDictadoVoz => _escuchandoDictadoVoz;

  /// Último mensaje de error del servicio de micrófono, si ocurrió alguno.
  String? get errorVozATexto => _errorVozATexto;

  /// Mensaje de estado del Stream + Isolate durante la compresión de fotografías.
  String? get mensajeProgresoFoto => _mensajeProgresoFoto;

  /// Usuario autenticado actualmente.
  Usuario? get usuarioActual => _autenticacionRepository.usuarioActual;

  /// Lista de capataces y el ingeniero actual disponibles para asignar como
  /// responsables de una obra nueva.
  List<Usuario> get responsablesDisponibles =>
      List.unmodifiable(_responsablesDisponibles);

  /// Tareas guardadas en el catálogo individual del ingeniero activo.
  List<PlantillaObra> get tareasGuardadas => List.unmodifiable(
        _plantillasPersonales
            .where((p) => p.tipo == TipoPlantilla.tarea)
            .toList(),
      );

  /// Materiales guardados en el catálogo individual del ingeniero activo.
  List<PlantillaObra> get materialesGuardados => List.unmodifiable(
        _plantillasPersonales
            .where((p) => p.tipo == TipoPlantilla.material)
            .toList(),
      );

  /// Indica si el usuario autenticado puede elegir la tarea actual en curso
  /// de [obra] (capataz responsable o ingeniero a cargo).
  bool puedeElegirTareaActual(Obra obra) =>
      _politicas.puedeElegirTareaActual(usuarioActual, obra);

  /// Ubicación inicial sugerida para el selector de Google Maps.
  UbicacionObra get ubicacionPorDefecto => _mapaService.ubicacionPorDefecto;

  /// Ubicaciones frecuentes en Mendoza para el selector de Google Maps.
  List<UbicacionObra> get ubicacionesSugeridas =>
      _mapaService.ubicacionesFrecuentes;

  /// Obras visibles para el usuario activo según su rol.
  List<Obra> get obrasVisiblesPorRol {
    final usuario = usuarioActual;
    if (usuario == null) return List.unmodifiable(_todasLasObras);
    if (_politicas.puedeVerTodasLasObras(usuario.rol.tipo)) {
      return List.unmodifiable(_todasLasObras);
    }
    return List.unmodifiable(
      _todasLasObras.where((o) => o.responsableId == usuario.id).toList(),
    );
  }

  /// Obras filtradas según estado de finalización, semáforo y búsqueda.
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

  /// Cuenta cuántas obras activas visibles para este rol tienen [estadoBuscado].
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

  /// Devuelve el historial de informes de una obra (priorizando la caché
  /// cargada bajo demanda desde SQLite).
  List<ReporteDiario> informesDeObra(String obraId) {
    final enCache = _reportesPorObraCache[obraId];
    if (enCache != null) return List.unmodifiable(enCache);
    return _reportes.where((r) => r.obraId == obraId).toList();
  }

  /// Carga bajo demanda el historial de reportes de una obra puntual desde SQLite.
  Future<void> cargarReportesDeObra(
    String obraId, {
    int? limite,
    int? desplazamiento,
  }) async {
    _cargandoReportesObra = true;
    _mensajeError = null;
    notificarSiActivo();
    try {
      final lista = await _obrasRepository.obtenerReportesPorObra(
        obraId,
        limite: limite,
        desplazamiento: desplazamiento,
      );
      _reportesPorObraCache[obraId] = lista;
      _cargandoReportesObra = false;
      notificarSiActivo();
    } catch (e) {
      _cargandoReportesObra = false;
      _mensajeError = 'No se pudo cargar el historial de reportes: $e';
      notificarSiActivo();
    }
  }

  /// Devuelve el último informe cargado para una obra, o `null` si aún no tiene.
  ReporteDiario? ultimoInformeDeObra(String obraId) {
    final lista = informesDeObra(obraId);
    if (lista.isEmpty) return null;
    return lista.first;
  }

  /// Transcribe el nombre del lugar al que apuntan las coordenadas elegidas.
  Future<String> obtenerNombreLugarDesdeCoordenadas(
    double latitud,
    double longitud,
  ) {
    return _mapaService.obtenerNombreLugarDesdeCoordenadas(latitud, longitud);
  }

  /// Guarda automáticamente el borrador de observaciones cuando la app pasa
  /// a segundo plano (`onHide`).
  Future<void> guardarBorradorInforme(String texto) async {
    await _preferenciasRepository?.guardarBorradorObservaciones(texto);
  }

  /// Carga las obras, reportes y responsables desde los repositorios,
  /// notificando explícitamente en `cargando`, `exito` y `error`.
  Future<void> cargar({bool forzarRecarga = false}) async {
    _estado = EstadoCargaObras.cargando;
    _mensajeError = null;
    notificarSiActivo();

    try {
      await _sincronizacionService.inicializar();
      _todasLasObras = await _obrasRepository.obtenerObras(
        forzarRecarga: forzarRecarga,
      );
      _reportes = await _obrasRepository.obtenerReportes(
        forzarRecarga: forzarRecarga,
      );
      _reportesPorObraCache.clear();
      _responsablesDisponibles =
          await _autenticacionRepository.obtenerResponsablesDisponibles(
        forzarRecarga: forzarRecarga,
      );
      _plantillasPersonales = await _cargarPlantillasUsuarioActual();
      _estado = EstadoCargaObras.exito;
      notificarSiActivo();
    } catch (e) {
      _estado = EstadoCargaObras.error;
      _mensajeError = 'Error al cargar las obras: $e';
      notificarSiActivo();
    }
  }

  /// Actualiza el filtro de búsqueda por nombre de obra.
  void actualizarBusqueda(String texto) {
    if (_textoBusqueda == texto) return;
    _textoBusqueda = texto;
    notificarSiActivo();
  }

  /// Selecciona o deselecciona un estado de semáforo como filtro de las obras.
  void seleccionarFiltroSemaforo(EstadoObra? nuevoFiltro) {
    _mostrarSoloFinalizadas = false;
    if (_filtroEstadoSemaforo == nuevoFiltro) {
      _filtroEstadoSemaforo = null;
    } else {
      _filtroEstadoSemaforo = nuevoFiltro;
    }
    notificarSiActivo();
  }

  /// Activa o desactiva el filtro de obras finalizadas.
  void alternarFiltroFinalizadas(bool activo) {
    _mostrarSoloFinalizadas = activo;
    if (activo) {
      _filtroEstadoSemaforo = null;
    }
    notificarSiActivo();
  }

  /// Dispara el ciclo real de sincronización con exclusión mutua y alerta visual.
  Future<void> iniciarSincronizacionConAlerta() async {
    if (_sincronizando) return;
    _temporizadorAlertaSync?.cancel();
    _sincronizando = true;
    _mostrandoAlertaSincronizacion = true;
    _mensajeErrorSincronizacion = null;
    notificarSiActivo();

    try {
      final resultado = await _obrasRepository.sincronizarTodo(
        permitirSimulacionLocal:
            !_autenticacionRepository.usaAutenticacionRemota,
      );
      _todasLasObras = await _obrasRepository.obtenerObras(forzarRecarga: true);
      _reportes = await _obrasRepository.obtenerReportes(forzarRecarga: true);
      _reportesPorObraCache.clear();
      _responsablesDisponibles =
          await _autenticacionRepository.obtenerResponsablesDisponibles(
        forzarRecarga: true,
      );
      _plantillasPersonales = await _cargarPlantillasUsuarioActual();
      if (resultado.tuvoErrores) {
        _mensajeErrorSincronizacion = resultado.mensajeError;
      }
      _sincronizando = false;
      notificarSiActivo();
    } catch (e) {
      _sincronizando = false;
      _mensajeErrorSincronizacion = 'Error durante la sincronización: $e';
      notificarSiActivo();
    }

    _temporizadorAlertaSync = Timer(const Duration(seconds: 2), () {
      _mostrandoAlertaSincronizacion = false;
      notificarSiActivo();
    });
  }

  /// Ejecuta sincronización bidireccional silenciosa (Push -> Pull) con
  /// re-encolado automático si llega otro cambio mientras hay una sync activa.
  Future<void> iniciarSincronizacionSilenciosa() async {
    if (!_autenticacionRepository.usaAutenticacionRemota) {
      return;
    }
    if (_sincronizando) {
      _syncPendienteAlTerminar = true;
      return;
    }

    _sincronizando = true;
    _mensajeErrorSincronizacion = null;
    notificarSiActivo();

    try {
      final resultado = await _obrasRepository.sincronizarTodo(
        permitirSimulacionLocal: false,
      );
      _todasLasObras = await _obrasRepository.obtenerObras(forzarRecarga: true);
      _reportes = await _obrasRepository.obtenerReportes(forzarRecarga: true);
      _reportesPorObraCache.clear();
      _responsablesDisponibles =
          await _autenticacionRepository.obtenerResponsablesDisponibles(
        forzarRecarga: true,
      );
      _plantillasPersonales = await _cargarPlantillasUsuarioActual();
      if (resultado.tuvoErrores) {
        _mensajeErrorSincronizacion = resultado.mensajeError;
      } else if (resultado.cambiosDescargados > 0) {
        _busDeEventos?.emitir(const ObrasActualizadas());
      }
      _sincronizando = false;
      notificarSiActivo();
    } catch (e) {
      _sincronizando = false;
      _mensajeErrorSincronizacion = 'Error durante la sincronización: $e';
      notificarSiActivo();
    }

    if (_syncPendienteAlTerminar && !estaDescartado) {
      _syncPendienteAlTerminar = false;
      await iniciarSincronizacionSilenciosa();
    }
  }

  /// Refresco manual disparado por gestos de Pull-to-Refresh en la lista.
  Future<void> refrescarManual() async {
    if (_autenticacionRepository.usaAutenticacionRemota) {
      await iniciarSincronizacionSilenciosa();
    } else {
      await cargar(forzarRecarga: true);
    }
  }

  /// Inicia la escucha Realtime de Supabase (`postgres_changes`) y un respaldo
  /// periódico suave cada 45 segundos mientras la app está en primer plano.
  void reanudarSincronizacionContinua() {
    if (estaDescartado || !_autenticacionRepository.usaAutenticacionRemota) {
      return;
    }
    _suscripcionRealtime ??= _obrasRepository.escucharCambiosRemotos().listen(
      (tabla) {
        _debounceRealtime?.cancel();
        _debounceRealtime = Timer(const Duration(milliseconds: 1200), () {
          if (estaDescartado) return;
          if (tabla == 'notificaciones') {
            _busDeEventos?.emitir(const AlertaSemaforoEmitida(obraId: ''));
          }
          unawaited(iniciarSincronizacionSilenciosa());
        });
      },
    );

    _temporizadorRespaldoSync ??= Timer.periodic(
      const Duration(seconds: 45),
      (_) {
        if (!estaDescartado) {
          unawaited(iniciarSincronizacionSilenciosa());
        }
      },
    );
  }

  /// Pausa la escucha Realtime y el temporizador periódico al pasar a segundo
  /// plano o cerrar sesión para cuidar batería y conexiones.
  void pausarSincronizacionContinua() {
    _debounceRealtime?.cancel();
    _debounceRealtime = null;
    _temporizadorRespaldoSync?.cancel();
    _temporizadorRespaldoSync = null;
    final sub = _suscripcionRealtime;
    _suscripcionRealtime = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
  }

  /// Cambia el estado del semáforo de una obra y dispara una alerta proactiva
  /// si el nuevo estado es Amarillo (`demorada`) o Rojo (`problemas`).
  Future<void> cambiarEstadoSemaforo(
    String obraId,
    EstadoObra nuevoEstado,
  ) async {
    _guardando = true;
    _mensajeError = null;
    notificarSiActivo();

    try {
      final actualizada = await _obrasRepository.cambiarEstadoSemaforo(
        obraId,
        nuevoEstado,
      );
      if (actualizada == null) {
        _guardando = false;
        notificarSiActivo();
        return;
      }

      if (nuevoEstado.requiereAlertaProactiva) {
        await _notificacionesRepository.emitirAlertaCambioSemaforo(
          obra: actualizada,
          motivo:
              'Cambio de semáforo en obra "${actualizada.nombre}" a ${nuevoEstado.etiqueta}.',
        );
      }

      _todasLasObras = await _obrasRepository.obtenerObras(forzarRecarga: true);
      _guardando = false;
      notificarSiActivo();
      unawaited(iniciarSincronizacionSilenciosa());
    } catch (e) {
      _guardando = false;
      _mensajeError = 'No se pudo actualizar el semáforo: $e';
      notificarSiActivo();
    }
  }

  /// Añade una nueva tarea a una obra mediante inserción granular.
  Future<void> agregarTareaAObra(String obraId, String nombreTarea) async {
    if (nombreTarea.trim().isEmpty) return;
    _guardando = true;
    _mensajeError = null;
    notificarSiActivo();

    try {
      await _obrasRepository.agregarTareaAObra(obraId, nombreTarea);
      _todasLasObras = await _obrasRepository.obtenerObras(forzarRecarga: true);
      _guardando = false;
      notificarSiActivo();
      unawaited(iniciarSincronizacionSilenciosa());
    } catch (e) {
      _guardando = false;
      _mensajeError = 'No se pudo agregar la tarea: $e';
      notificarSiActivo();
    }
  }

  /// Marca una tarea como completada o pendiente de forma atómica.
  Future<void> alternarTareaCompletada(String obraId, String tareaId) async {
    _guardando = true;
    _mensajeError = null;
    notificarSiActivo();

    try {
      await _obrasRepository.alternarTareaCompletada(obraId, tareaId);
      _todasLasObras = await _obrasRepository.obtenerObras(forzarRecarga: true);
      _guardando = false;
      notificarSiActivo();
      unawaited(iniciarSincronizacionSilenciosa());
    } catch (e) {
      _guardando = false;
      _mensajeError = 'No se pudo actualizar el estado de la tarea: $e';
      notificarSiActivo();
    }
  }

  /// Elige explícitamente cuál es la tarea pendiente actualmente en curso
  /// de una obra (permitido solo para el capataz responsable o el ingeniero
  /// a cargo según [Politicas.puedeElegirTareaActual]).
  Future<void> cambiarTareaActual(String obraId, String? tareaId) async {
    final obra = obtenerObraPorId(obraId);
    if (obra == null || !puedeElegirTareaActual(obra)) return;

    _guardando = true;
    _mensajeError = null;
    notificarSiActivo();

    try {
      await _obrasRepository.cambiarTareaActual(obraId, tareaId);
      _todasLasObras = await _obrasRepository.obtenerObras(forzarRecarga: true);
      _guardando = false;
      notificarSiActivo();
      unawaited(iniciarSincronizacionSilenciosa());
    } catch (e) {
      _guardando = false;
      _mensajeError = 'No se pudo actualizar la tarea actual: $e';
      notificarSiActivo();
    }
  }

  /// Añade un material nuevo a una obra en curso y dispara sincronización.
  Future<void> agregarMaterialAObra(
    String obraId,
    String nombreMaterial,
  ) async {
    if (nombreMaterial.trim().isEmpty) return;
    _guardando = true;
    _mensajeError = null;
    notificarSiActivo();

    try {
      await _obrasRepository.agregarMaterialAObra(obraId, nombreMaterial);
      _todasLasObras = await _obrasRepository.obtenerObras(forzarRecarga: true);
      _guardando = false;
      notificarSiActivo();
      unawaited(iniciarSincronizacionSilenciosa());
    } catch (e) {
      _guardando = false;
      _mensajeError = 'No se pudo agregar el material: $e';
      notificarSiActivo();
    }
  }

  /// Guarda una tarea o material frecuente en el catálogo individual del
  /// ingeniero autenticado.
  Future<void> guardarPlantillaPersonal({
    required TipoPlantilla tipo,
    required String nombre,
  }) async {
    final usuario = usuarioActual;
    if (usuario == null || nombre.trim().isEmpty) return;

    try {
      await _obrasRepository.guardarPlantilla(
        usuarioId: usuario.id,
        tipo: tipo,
        nombre: nombre,
      );
      _plantillasPersonales = await _cargarPlantillasUsuarioActual();
      notificarSiActivo();
      unawaited(iniciarSincronizacionSilenciosa());
    } catch (e) {
      _mensajeError = 'No se pudo guardar en tu catálogo: $e';
      notificarSiActivo();
    }
  }

  /// Quita una tarea o material del catálogo individual del ingeniero sin
  /// afectar obras ya creadas.
  Future<void> eliminarPlantillaPersonal(String id) async {
    try {
      await _obrasRepository.eliminarPlantilla(id);
      _plantillasPersonales = await _cargarPlantillasUsuarioActual();
      notificarSiActivo();
      unawaited(iniciarSincronizacionSilenciosa());
    } catch (e) {
      _mensajeError = 'No se pudo eliminar del catálogo: $e';
      notificarSiActivo();
    }
  }

  Future<List<PlantillaObra>> _cargarPlantillasUsuarioActual() async {
    final usuario = usuarioActual;
    if (usuario == null) return const [];
    return _obrasRepository.obtenerPlantillasUsuario(usuario.id);
  }

  /// Crea una nueva obra desde la vista del Ingeniero con IDs UUID v4 y UTC.
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
    _guardando = true;
    _mensajeError = null;
    notificarSiActivo();

    try {
      final ahoraUtc = _reloj.ahora().toUtc();
      final tareasCreadas = [
        for (final nombreTarea in nombresTareas)
          TareaObra(
            id: _generadorIds.generar(),
            nombre: nombreTarea,
            completada: false,
            updatedAt: ahoraUtc,
            syncStatus: EstadoSincronizacion.pending,
          ),
      ];

      final tienePortadaPropia = imagenPortadaPersonalizada != null &&
          imagenPortadaPersonalizada.isNotEmpty;

      final nuevaObra = Obra(
        id: _generadorIds.generar(),
        nombre: nombre.trim(),
        estado: estadoInicial,
        fechaUltimoReporte: ahoraUtc,
        responsableId: responsable.id,
        responsableNombre: responsable.nombre,
        ingenieroId: usuarioActual?.id,
        ingenieroNombre: usuarioActual?.nombre,
        tareas: tareasCreadas,
        materiales: materiales,
        ubicacion: ubicacion,
        observaciones: observaciones.trim(),
        conFoto: tienePortadaPropia,
        imagen: tienePortadaPropia
            ? imagenPortadaPersonalizada
            : 'assets/images/obra${(_todasLasObras.length % 6) + 1}.png',
        updatedAt: ahoraUtc,
        syncStatus: EstadoSincronizacion.pending,
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
      _guardando = false;
      notificarSiActivo();
      unawaited(iniciarSincronizacionSilenciosa());
    } catch (e) {
      _guardando = false;
      _mensajeError = 'No se pudo crear la obra: $e';
      notificarSiActivo();
    }
  }

  /// Registra un informe diario de terreno con ID UUID v4 y fecha UTC.
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
    _guardando = true;
    _mensajeError = null;
    notificarSiActivo();

    try {
      final ahoraUtc = _reloj.ahora().toUtc();
      final autorId = usuarioActual?.id ?? obra.responsableId;
      final autor = usuarioActual?.nombre ?? obra.responsableNombre;
      final nuevoReporte = ReporteDiario(
        id: _generadorIds.generar(),
        obraId: obra.id,
        obraNombre: obra.nombre,
        autorId: autorId,
        autorNombre: autor,
        fechaCreacionLocal: ahoraUtc,
        tareaSeleccionada: tareaSeleccionada,
        tareaCompletadaEnInforme: marcarTareaComoCompletada || finalizarObra,
        materialesUsados: materialesGastados,
        observaciones: observaciones.trim(),
        urlFotos: fotosAdjuntas,
        estadoSemaforo: estadoSemaforo,
        syncStatus: EstadoSincronizacion.pending,
        obraFinalizada: finalizarObra,
        updatedAt: ahoraUtc,
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
      _reportesPorObraCache.remove(obra.id);
      _guardando = false;
      notificarSiActivo();
      unawaited(iniciarSincronizacionSilenciosa());
    } catch (e) {
      _guardando = false;
      _mensajeError = 'No se pudo guardar el informe diario: $e';
      notificarSiActivo();
    }
  }

  /// Captura o selecciona una foto real y la procesa mediante `Stream` + `Isolate`.
  Future<FotoComprimida?> adjuntarFotoComprimida({
    required bool desdeCamara,
  }) async {
    _procesandoFoto = true;
    _mensajeError = null;
    notificarSiActivo();

    FotoComprimida? resultadoFinal;
    try {
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
        notificarSiActivo();
      }
      _procesandoFoto = false;
      notificarSiActivo();
      return resultadoFinal;
    } catch (e) {
      _procesandoFoto = false;
      _mensajeError = 'Error al procesar la fotografía: $e';
      notificarSiActivo();
      return null;
    }
  }

  /// Inicia o detiene la transcripción real de voz a texto usando el micrófono.
  Future<void> alternarDictadoPorVoz({
    required void Function(String textoReconocido) onTextoReconocido,
    required void Function(String mensajeError) onErrorMicrofono,
  }) async {
    _errorVozATexto = null;
    if (_escuchandoDictadoVoz) {
      await _vozATextoService.detener();
      _escuchandoDictadoVoz = false;
      notificarSiActivo();
      return;
    }

    _escuchandoDictadoVoz = true;
    notificarSiActivo();

    final inicioExitoso = await _vozATextoService.iniciarEscucha(
      onResultado: (texto) {
        onTextoReconocido(texto);
      },
      onError: (mensaje) {
        _errorVozATexto = mensaje;
        _escuchandoDictadoVoz = false;
        onErrorMicrofono(mensaje);
        notificarSiActivo();
      },
      onFinalizado: () {
        _escuchandoDictadoVoz = false;
        notificarSiActivo();
      },
    );

    if (!inicioExitoso) {
      _escuchandoDictadoVoz = false;
      notificarSiActivo();
    }
  }

  void _procesarEventoGlobal(EventoDeApp evento) {
    switch (evento) {
      case SesionIniciada():
        reanudarSincronizacionContinua();
        unawaited(
          cargar(forzarRecarga: true).then((_) {
            unawaited(iniciarSincronizacionSilenciosa());
          }),
        );
      case SesionCerrada():
        pausarSincronizacionContinua();
        _obrasRepository.limpiarCache();
        _todasLasObras = [];
        _reportes = [];
        _reportesPorObraCache.clear();
        _responsablesDisponibles = [];
        _plantillasPersonales = [];
        _textoBusqueda = '';
        _filtroEstadoSemaforo = null;
        _mostrarSoloFinalizadas = false;
        _mensajeError = null;
        _mensajeErrorSincronizacion = null;
        notificarSiActivo();
      default:
        break;
    }
  }

  @override
  void dispose() {
    pausarSincronizacionContinua();
    _suscripcionConexion?.cancel();
    _suscripcionEventos?.cancel();
    _temporizadorAlertaSync?.cancel();
    super.dispose();
  }
}
