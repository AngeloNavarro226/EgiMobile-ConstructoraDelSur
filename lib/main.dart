import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/repositories/autenticacion_repository.dart';
import 'data/repositories/notificaciones_repository.dart';
import 'data/repositories/obras_repository.dart';
import 'data/repositories/preferencias_repository.dart';
import 'data/services/base_datos_local_service.dart';
import 'data/services/bus_de_eventos.dart';
import 'data/services/configuracion_supabase.dart';
import 'data/services/firebase_notificaciones_service.dart';
import 'data/services/fuente_datos_remota.dart';
import 'data/services/generador_ids.dart';
import 'data/services/mapa_service.dart';
import 'data/services/motor_sincronizacion.dart';
import 'data/services/multimedia_service.dart';
import 'data/services/reloj.dart';
import 'data/services/servicio_autenticacion_remota.dart';
import 'data/services/sincronizacion_service.dart';
import 'data/services/supabase_remote_service.dart';
import 'data/services/voz_a_texto_service.dart';
import 'domain/models/usuario.dart';
import 'plataforma/capacidades.dart';
import 'plataforma/politicas.dart';
import 'ui/autenticacion/view_models/autenticacion_view_model.dart';
import 'ui/autenticacion/widgets/login_screen.dart';
import 'ui/core/alerta_sincronizacion_banner.dart';
import 'ui/exportar/view_models/exportar_view_model.dart';
import 'ui/exportar/widgets/exportar_screen.dart';
import 'ui/notificaciones/view_models/notificaciones_view_model.dart';
import 'ui/notificaciones/widgets/notificaciones_ingeniero_screen.dart';
import 'ui/obras/view_models/obras_view_model.dart';
import 'ui/obras/widgets/agregar_obra_screen.dart';
import 'ui/obras/widgets/inicio_capataz_screen.dart';
import 'ui/obras/widgets/inicio_duenio_screen.dart';
import 'ui/obras/widgets/inicio_ingeniero_screen.dart';
import 'ui/perfil/view_models/perfil_view_model.dart';
import 'ui/perfil/widgets/perfil_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Capacidades y políticas de plataforma/negocio
  const capacidades = Capacidades();
  const politicas = Politicas();

  // 2. Capa de datos: Firebase (si está configurado) + Supabase + Servicios
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[Firebase] Inicialización omitida (sin configuración): $e');
  }

  final configSupabase = ConfiguracionSupabase.desdeEntorno();
  SupabaseClient? clienteSupabase;
  if (configSupabase.estaConfigurado) {
    await Supabase.initialize(
      url: configSupabase.url,
      publishableKey: configSupabase.publishableKey,
    );
    clienteSupabase = Supabase.instance.client;
  }

  const reloj = RelojDelSistema();
  final generadorIds = GeneradorUuidV4();
  final busDeEventos = BusDeEventos();
  final FuenteDatosRemota fuenteDatosRemota = clienteSupabase != null
      ? SupabaseRemoteService(client: clienteSupabase)
      : const FuenteDatosRemotaOffline();
  final ServicioAutenticacionRemota authRemota = clienteSupabase != null
      ? SupabaseAuthService(client: clienteSupabase)
      : const ServicioAutenticacionRemotaOffline();
  final baseDatosService = BaseDatosLocalService(
    reloj: reloj,
    insertarSemillasDePrueba: clienteSupabase == null,
    nombreArchivo: clienteSupabase != null
        ? BaseDatosLocalService.nombreArchivoSupabase
        : BaseDatosLocalService.nombreArchivoDb,
  );
  final motorSincronizacion = MotorSincronizacion(
    baseDatosLocal: baseDatosService,
    fuenteRemota: fuenteDatosRemota,
    reloj: reloj,
    busDeEventos: busDeEventos,
  );
  final sincronizacionService = SincronizacionService();
  final multimediaService = MultimediaService(
    reloj: reloj,
    generadorIds: generadorIds,
  );
  final vozATextoService = VozATextoService();
  final mapaService = MapaService();

  // 3. Capa de datos: Repositorios
  final preferenciasRepository = PreferenciasRepository();
  final firebaseNotificacionesService = FirebaseNotificacionesService(
    debeMostrarPushEnPrimerPlano: () =>
        preferenciasRepository.recibirAlertasSemaforo,
  );
  unawaited(firebaseNotificacionesService.inicializarPush());

  final autenticacionRepository = AutenticacionRepository(
    baseDatosService: baseDatosService,
    preferenciasRepository: preferenciasRepository,
    authRemota: authRemota,
    fuenteRemota: fuenteDatosRemota,
    servicioPushFcm: firebaseNotificacionesService,
    reloj: reloj,
    busDeEventos: busDeEventos,
  );
  final obrasRepository = ObrasRepository(
    baseDatosService: baseDatosService,
    reloj: reloj,
    generadorIds: generadorIds,
    motorSincronizacion: motorSincronizacion,
    busDeEventos: busDeEventos,
  );
  final notificacionesRepository = NotificacionesRepository(
    baseDatosService: baseDatosService,
    notificacionesSistemaService: firebaseNotificacionesService,
    reloj: reloj,
    generadorIds: generadorIds,
    autenticacionRepository: autenticacionRepository,
    preferenciasRepository: preferenciasRepository,
    motorSincronizacion: motorSincronizacion,
    busDeEventos: busDeEventos,
  );

  // 4. Capa de UI: ViewModels inyectados por constructor
  final autenticacionViewModel = AutenticacionViewModel(
    repositorio: autenticacionRepository,
  );
  final obrasViewModel = ObrasViewModel(
    obrasRepository: obrasRepository,
    autenticacionRepository: autenticacionRepository,
    notificacionesRepository: notificacionesRepository,
    sincronizacionService: sincronizacionService,
    multimediaService: multimediaService,
    vozATextoService: vozATextoService,
    mapaService: mapaService,
    politicas: politicas,
    preferenciasRepository: preferenciasRepository,
    busDeEventos: busDeEventos,
    reloj: reloj,
    generadorIds: generadorIds,
  );

  final exportarViewModel = ExportarViewModel(
    obrasRepository: obrasRepository,
    busDeEventos: busDeEventos,
  );

  final notificacionesViewModel = NotificacionesViewModel(
    repositorio: notificacionesRepository,
    busDeEventos: busDeEventos,
  );

  final perfilViewModel = PerfilViewModel(
    autenticacionRepository: autenticacionRepository,
    preferenciasRepository: preferenciasRepository,
    sincronizacionService: sincronizacionService,
    notificacionesRepository: notificacionesRepository,
  );

  // Arranque Offline-First: cargar preferencias antes del primer frame (tema
  // oscuro y alertas) y restaurar la sesión guardada en segundo plano.
  await perfilViewModel.inicializarPreferencias();
  unawaited(autenticacionViewModel.restaurarSesion());

  runApp(
    ConstructoraApp(
      capacidades: capacidades,
      politicas: politicas,
      autenticacionViewModel: autenticacionViewModel,
      obrasViewModel: obrasViewModel,
      exportarViewModel: exportarViewModel,
      notificacionesViewModel: notificacionesViewModel,
      perfilViewModel: perfilViewModel,
    ),
  );
}

/// Raíz de la aplicación que gestiona el tema claro/oscuro y alterna entre
/// la pantalla de inicio de sesión ([LoginScreen]) y la vista principal
/// adaptada al rol del usuario autenticado.
class ConstructoraApp extends StatelessWidget {
  const ConstructoraApp({
    super.key,
    required this.capacidades,
    required this.politicas,
    required this.autenticacionViewModel,
    required this.obrasViewModel,
    required this.exportarViewModel,
    required this.notificacionesViewModel,
    required this.perfilViewModel,
  });

  final Capacidades capacidades;
  final Politicas politicas;
  final AutenticacionViewModel autenticacionViewModel;
  final ObrasViewModel obrasViewModel;
  final ExportarViewModel exportarViewModel;
  final NotificacionesViewModel notificacionesViewModel;
  final PerfilViewModel perfilViewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        perfilViewModel,
        autenticacionViewModel,
      ]),
      builder: (context, _) {
        return MaterialApp(
          title: 'Constructora Del Sur',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: Colors.orange, useMaterial3: true),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.orange,
            brightness: Brightness.dark,
            useMaterial3: true,
          ),
          themeMode:
              perfilViewModel.modoOscuro ? ThemeMode.dark : ThemeMode.light,
          home: autenticacionViewModel.tieneSesionActiva
              ? PantallaPrincipalPorRol(
                  capacidades: capacidades,
                  politicas: politicas,
                  autenticacionViewModel: autenticacionViewModel,
                  obrasViewModel: obrasViewModel,
                  exportarViewModel: exportarViewModel,
                  notificacionesViewModel: notificacionesViewModel,
                  perfilViewModel: perfilViewModel,
                )
              : LoginScreen(viewModel: autenticacionViewModel),
        );
      },
    );
  }
}

/// Contenedor principal con navegación adaptada según el perfil del usuario y
/// escucha del ciclo de vida
class PantallaPrincipalPorRol extends StatefulWidget {
  const PantallaPrincipalPorRol({
    super.key,
    required this.capacidades,
    required this.politicas,
    required this.autenticacionViewModel,
    required this.obrasViewModel,
    required this.exportarViewModel,
    required this.notificacionesViewModel,
    required this.perfilViewModel,
  });

  final Capacidades capacidades;
  final Politicas politicas;
  final AutenticacionViewModel autenticacionViewModel;
  final ObrasViewModel obrasViewModel;
  final ExportarViewModel exportarViewModel;
  final NotificacionesViewModel notificacionesViewModel;
  final PerfilViewModel perfilViewModel;

  @override
  State<PantallaPrincipalPorRol> createState() =>
      _PantallaPrincipalPorRolState();
}

class _PantallaPrincipalPorRolState extends State<PantallaPrincipalPorRol> {
  int _indice = 0;
  String? _ultimoUsuarioId;
  late final AppLifecycleListener _lifecycleListener;
  StreamSubscription<String>? _suscripcionToquesPush;

  @override
  void initState() {
    super.initState();
    _ultimoUsuarioId = widget.autenticacionViewModel.usuarioActual?.id;
    _suscripcionToquesPush =
        widget.notificacionesViewModel.toques.listen(_manejarToqueNotificacion);
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (widget.autenticacionViewModel.tieneSesionActiva) {
          widget.obrasViewModel.reanudarSincronizacionContinua();
          unawaited(widget.obrasViewModel.iniciarSincronizacionSilenciosa());
        }
      },
      onHide: () {
        widget.obrasViewModel.pausarSincronizacionContinua();
      },
      onPause: () {
        widget.obrasViewModel.pausarSincronizacionContinua();
      },
    );
  }

  void _manejarToqueNotificacion(String destino) {
    if (!mounted) return;
    final rol = widget.autenticacionViewModel.usuarioActual?.rol.tipo;
    if (destino == 'notificaciones' && rol == RolUsuario.ingeniero) {
      setState(() => _indice = 3);
      unawaited(widget.notificacionesViewModel.cargar());
      return;
    }
    if (destino.startsWith('obra:')) {
      setState(() => _indice = 0);
      unawaited(widget.obrasViewModel.refrescarManual());
    }
  }

  @override
  void dispose() {
    unawaited(_suscripcionToquesPush?.cancel());
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usuarioActualId = widget.autenticacionViewModel.usuarioActual?.id;
    if (usuarioActualId != _ultimoUsuarioId) {
      _ultimoUsuarioId = usuarioActualId;
      _indice = 0;
    }

    final rol = widget.autenticacionViewModel.usuarioActual?.rol.tipo ??
        RolUsuario.ingeniero;

    final destinos = _construirDestinosParaRol(rol);
    final indiceSeguro = _indice >= destinos.length ? 0 : _indice;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ListenableBuilder(
              listenable: widget.obrasViewModel,
              builder: (context, _) => AlertaSincronizacionBanner(
                visible: widget.obrasViewModel.mostrandoAlertaSincronizacion,
              ),
            ),
            ListenableBuilder(
              listenable: Listenable.merge([
                widget.obrasViewModel,
                widget.notificacionesViewModel,
              ]),
              builder: (context, _) {
                final pendientes =
                    widget.obrasViewModel.cantidadReportesPendientes;
                final alertas =
                    widget.notificacionesViewModel.notificaciones.length;
                return BarraNavegacionSuperior(
                  items: [
                    for (final d in destinos)
                      (
                        d.icono,
                        d.etiqueta,
                        d.etiqueta == 'Alertas'
                            ? alertas
                            : (d.etiqueta == 'Perfil' ? pendientes : 0),
                      ),
                  ],
                  indice: indiceSeguro,
                  onSeleccion: (nuevoIndice) =>
                      setState(() => _indice = nuevoIndice),
                );
              },
            ),
            Expanded(
              child: IndexedStack(
                index: indiceSeguro,
                children: [for (final d in destinos) d.pantalla],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_DestinoNavegacion> _construirDestinosParaRol(RolUsuario rol) {
    final pantallaInicio = switch (rol) {
      RolUsuario.ingeniero => InicioIngenieroScreen(
          viewModel: widget.obrasViewModel,
          capacidades: widget.capacidades,
        ),
      RolUsuario.capataz => InicioCapatazScreen(
          viewModel: widget.obrasViewModel,
          capacidades: widget.capacidades,
        ),
      RolUsuario.duenio => InicioDuenioScreen(
          viewModel: widget.obrasViewModel,
          capacidades: widget.capacidades,
        ),
    };

    final pantallaExportar = ExportarScreen(
      viewModel: widget.exportarViewModel,
      obrasViewModel: widget.obrasViewModel,
    );

    final pantallaPerfil = PerfilScreen(
      viewModel: widget.perfilViewModel,
      autenticacionViewModel: widget.autenticacionViewModel,
      obrasViewModel: widget.obrasViewModel,
    );

    if (rol == RolUsuario.ingeniero) {
      return [
        _DestinoNavegacion(
          icono: Icons.home,
          etiqueta: 'Inicio',
          pantalla: pantallaInicio,
        ),
        _DestinoNavegacion(
          icono: Icons.upload_file,
          etiqueta: 'Exportar',
          pantalla: pantallaExportar,
        ),
        _DestinoNavegacion(
          icono: Icons.edit,
          etiqueta: 'Agregar Obras',
          pantalla: AgregarObraScreen(
            viewModel: widget.obrasViewModel,
            capacidades: widget.capacidades,
            onGuardado: () => setState(() => _indice = 0),
          ),
        ),
        _DestinoNavegacion(
          icono: Icons.notifications_active,
          etiqueta: 'Alertas',
          pantalla: NotificacionesIngenieroScreen(
            viewModel: widget.notificacionesViewModel,
          ),
        ),
        _DestinoNavegacion(
          icono: Icons.manage_accounts,
          etiqueta: 'Perfil',
          pantalla: pantallaPerfil,
        ),
      ];
    }

    return [
      _DestinoNavegacion(
        icono: Icons.home,
        etiqueta: 'Inicio',
        pantalla: pantallaInicio,
      ),
      _DestinoNavegacion(
        icono: Icons.upload_file,
        etiqueta: 'Exportar',
        pantalla: pantallaExportar,
      ),
      _DestinoNavegacion(
        icono: Icons.manage_accounts,
        etiqueta: 'Perfil',
        pantalla: pantallaPerfil,
      ),
    ];
  }
}

class _DestinoNavegacion {
  const _DestinoNavegacion({
    required this.icono,
    required this.etiqueta,
    required this.pantalla,
  });

  final IconData icono;
  final String etiqueta;
  final Widget pantalla;
}

/// Barra superior con la estética original de la aplicación y badges en vivo.
class BarraNavegacionSuperior extends StatelessWidget {
  const BarraNavegacionSuperior({
    super.key,
    required this.items,
    required this.indice,
    required this.onSeleccion,
  });

  final List<(IconData, String, int)> items;
  final int indice;
  final ValueChanged<int> onSeleccion;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Material(
      elevation: 2,
      color: colores.surface,
      child: SizedBox(
        height: 64,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onSeleccion(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Badge(
                        isLabelVisible: items[i].$3 > 0,
                        label: Text(
                          items[i].$3 > 99 ? '99+' : '${items[i].$3}',
                        ),
                        child: Icon(
                          items[i].$1,
                          color:
                              i == indice ? colores.primary : colores.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              i == indice ? FontWeight.bold : FontWeight.normal,
                          color:
                              i == indice ? colores.primary : colores.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
