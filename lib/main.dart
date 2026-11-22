import 'dart:async';

import 'package:flutter/material.dart';

import 'data/repositories/autenticacion_repository.dart';
import 'data/repositories/notificaciones_repository.dart';
import 'data/repositories/obras_repository.dart';
import 'data/repositories/preferencias_repository.dart';
import 'data/services/base_datos_local_service.dart';
import 'data/services/bus_de_eventos.dart';
import 'data/services/mapa_service.dart';
import 'data/services/multimedia_service.dart';
import 'data/services/notificaciones_sistema_service.dart';
import 'data/services/sincronizacion_service.dart';
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Capacidades y políticas de plataforma/negocio
  const capacidades = Capacidades();
  const politicas = Politicas();

  // 2. Capa de datos: Servicios
  final baseDatosService = BaseDatosLocalService();
  final sincronizacionService = SincronizacionService();
  final multimediaService = MultimediaService();
  final vozATextoService = VozATextoService();
  final mapaService = MapaService();
  final notificacionesSistemaService = NotificacionesSistemaService();
  final busDeEventos = BusDeEventos();

  // 3. Capa de datos: Repositorios
  final autenticacionRepository = AutenticacionRepository(
    baseDatosService: baseDatosService,
  );
  final obrasRepository = ObrasRepository(
    baseDatosService: baseDatosService,
  );
  final notificacionesRepository = NotificacionesRepository(
    baseDatosService: baseDatosService,
    notificacionesSistemaService: notificacionesSistemaService,
  );
  final preferenciasRepository = PreferenciasRepository();
  unawaited(preferenciasRepository.inicializar());

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
  );
  unawaited(obrasViewModel.cargar());

  final exportarViewModel = ExportarViewModel(
    obrasRepository: obrasRepository,
  );
  unawaited(exportarViewModel.actualizarDatos());

  final notificacionesViewModel = NotificacionesViewModel(
    repositorio: notificacionesRepository,
  );
  unawaited(notificacionesViewModel.cargar());

  final perfilViewModel = PerfilViewModel(
    autenticacionRepository: autenticacionRepository,
    preferenciasRepository: preferenciasRepository,
    sincronizacionService: sincronizacionService,
    notificacionesRepository: notificacionesRepository,
  );

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
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        unawaited(widget.obrasViewModel.cargar(forzarRecarga: true));
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rol =
        widget.autenticacionViewModel.usuarioActual?.rol ?? RolUsuario.ingeniero;

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
            BarraNavegacionSuperior(
              items: [for (final d in destinos) (d.icono, d.etiqueta)],
              indice: indiceSeguro,
              onSeleccion: (nuevoIndice) =>
                  setState(() => _indice = nuevoIndice),
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

/// Barra superior con la estética original de la aplicación.
class BarraNavegacionSuperior extends StatelessWidget {
  const BarraNavegacionSuperior({
    super.key,
    required this.items,
    required this.indice,
    required this.onSeleccion,
  });

  final List<(IconData, String)> items;
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
                      Icon(
                        items[i].$1,
                        color: i == indice ? colores.primary : colores.onSurface,
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
