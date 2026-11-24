import 'package:constructora_del_sur/data/repositories/autenticacion_repository.dart';
import 'package:constructora_del_sur/data/repositories/notificaciones_repository.dart';
import 'package:constructora_del_sur/data/repositories/obras_repository.dart';
import 'package:constructora_del_sur/data/repositories/preferencias_repository.dart';
import 'package:constructora_del_sur/data/services/base_datos_local_service.dart';
import 'package:constructora_del_sur/data/services/bus_de_eventos.dart';
import 'package:constructora_del_sur/data/services/mapa_service.dart';
import 'package:constructora_del_sur/data/services/multimedia_service.dart';
import 'package:constructora_del_sur/data/services/sincronizacion_service.dart';
import 'package:constructora_del_sur/data/services/voz_a_texto_service.dart';
import 'package:constructora_del_sur/main.dart';
import 'package:constructora_del_sur/ui/autenticacion/view_models/autenticacion_view_model.dart';
import 'package:constructora_del_sur/ui/exportar/view_models/exportar_view_model.dart';
import 'package:constructora_del_sur/ui/notificaciones/view_models/notificaciones_view_model.dart';
import 'package:constructora_del_sur/ui/notificaciones/widgets/notificaciones_ingeniero_screen.dart';
import 'package:constructora_del_sur/ui/obras/view_models/obras_view_model.dart';
import 'package:constructora_del_sur/ui/obras/widgets/agregar_obra_screen.dart';
import 'package:constructora_del_sur/ui/obras/widgets/crear_informe_screen.dart';
import 'package:constructora_del_sur/ui/obras/widgets/detalle_obra_sheet.dart';
import 'package:constructora_del_sur/ui/obras/widgets/inicio_capataz_screen.dart';
import 'package:constructora_del_sur/ui/perfil/view_models/perfil_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'ConstructoraApp inicia en LoginScreen, valida errores e ingresa mostrando el perfil con teléfono',
    (tester) async {
      final bus = BusDeEventos();
      final db = BaseDatosLocalService();
      final prefsRepo = PreferenciasRepository();
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        preferenciasRepository: prefsRepo,
        busDeEventos: bus,
      );
      final obrasRepo = ObrasRepository(
        baseDatosService: db,
        busDeEventos: bus,
      );
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        autenticacionRepository: authRepo,
        busDeEventos: bus,
      );
      final syncService = SincronizacionService();

      final authVm = AutenticacionViewModel(repositorio: authRepo);
      final obrasVm = ObrasViewModel(
        obrasRepository: obrasRepo,
        autenticacionRepository: authRepo,
        notificacionesRepository: notifRepo,
        sincronizacionService: syncService,
        multimediaService: MultimediaService(),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const PoliticasFalsas(),
        preferenciasRepository: prefsRepo,
        busDeEventos: bus,
      );
      final exportarVm = ExportarViewModel(
        obrasRepository: obrasRepo,
        busDeEventos: bus,
      );
      final notifVm = NotificacionesViewModel(
        repositorio: notifRepo,
        busDeEventos: bus,
      );
      final perfilVm = PerfilViewModel(
        autenticacionRepository: authRepo,
        preferenciasRepository: prefsRepo,
        sincronizacionService: syncService,
        notificacionesRepository: notifRepo,
      );

      await tester.pumpWidget(
        ConstructoraApp(
          capacidades: const CapacidadesFalsas(tieneCamara: false),
          politicas: const PoliticasFalsas(),
          autenticacionViewModel: authVm,
          obrasViewModel: obrasVm,
          exportarViewModel: exportarVm,
          notificacionesViewModel: notifVm,
          perfilViewModel: perfilVm,
        ),
      );

      expect(find.text('Constructora Del Sur'), findsOneWidget);
      expect(find.byKey(const Key('boton_iniciar_sesion')), findsOneWidget);

      // Limpieza producción: el selector demo de usuarios de prueba no existe
      expect(find.text('ingeniero / 1234'), findsNothing);
      expect(find.text('capataz / 1234'), findsNothing);
      expect(
        find.byKey(const Key('btn_toggle_visibilidad_contrasenia')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('boton_iniciar_sesion')));
      await tester.pump();

      expect(
        find.byKey(const Key('mensaje_credenciales_invalidas')),
        findsOneWidget,
      );

      // Ingresar como capataz y verificar teléfono y sincronización manual en Perfil
      await tester.enterText(
        find.byKey(const Key('campo_usuario')),
        'capataz',
      );
      await tester.enterText(
        find.byKey(const Key('campo_contrasenia')),
        '1234',
      );
      await tester.tap(find.byKey(const Key('boton_iniciar_sesion')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();

      expect(find.text('+54 9 261 555-0102'), findsOneWidget);
      expect(find.text('Sincronización manual'), findsOneWidget);
      expect(find.text('Simular detección de Internet'), findsNothing);

      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  testWidgets(
    'Añadir tarea, añadir material y cambiar tarea actual en DetalleObraEnriquecidoSheet cierran sin errores de ciclo de vida',
    (tester) async {
      final bus = BusDeEventos();
      final db = BaseDatosLocalService();
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        busDeEventos: bus,
      );
      final obrasRepo = ObrasRepository(
        baseDatosService: db,
        busDeEventos: bus,
      );
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        autenticacionRepository: authRepo,
        busDeEventos: bus,
      );
      final obrasVm = ObrasViewModel(
        obrasRepository: obrasRepo,
        autenticacionRepository: authRepo,
        notificacionesRepository: notifRepo,
        sincronizacionService: SincronizacionService(),
        multimediaService: MultimediaService(),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const PoliticasFalsas(),
        busDeEventos: bus,
      );

      await authRepo.iniciarSesion(
        identificador: 'ingeniero',
        contrasenia: '1234',
      );
      await obrasVm.cargar(forzarRecarga: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetalleObraEnriquecidoSheet(
              obraId: '1',
              viewModel: obrasVm,
              capacidades: const CapacidadesFalsas(),
              permiteEdicion: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Añadir tarea desde el detalle
      await tester.ensureVisible(find.text('Añadir tarea'));
      await tester.tap(find.text('Añadir tarea'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Revoque fino interior');
      await tester.tap(find.text('Agregar tarea'));
      await tester.pumpAndSettle();

      expect(
        obrasVm
            .obtenerObraPorId('1')!
            .tareas
            .any((t) => t.nombre == 'Revoque fino interior'),
        isTrue,
      );

      // 2. Añadir material desde el detalle
      await tester.ensureVisible(find.text('Añadir material'));
      await tester.tap(find.text('Añadir material'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Pintura látex');
      await tester.tap(find.widgetWithText(FilledButton, 'Añadir material'));
      await tester.pumpAndSettle();

      expect(
        obrasVm.obtenerObraPorId('1')!.materiales,
        contains('Pintura látex'),
      );

      // 3. Cambiar tarea actual
      await tester.ensureVisible(find.text('Cambiar'));
      await tester.tap(find.text('Cambiar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revoque fino interior'));
      await tester.pumpAndSettle();

      expect(
        obrasVm.obtenerObraPorId('1')!.tareaActual,
        'Revoque fino interior',
      );

      obrasVm.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  testWidgets(
    'NotificacionesIngenieroScreen oculta envío manual y permite configurar el recordatorio diario',
    (tester) async {
      final bus = BusDeEventos();
      final db = BaseDatosLocalService();
      final prefsRepo = PreferenciasRepository();
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        preferenciasRepository: prefsRepo,
        busDeEventos: bus,
      );
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        autenticacionRepository: authRepo,
        preferenciasRepository: prefsRepo,
        busDeEventos: bus,
      );
      final notifVm = NotificacionesViewModel(
        repositorio: notifRepo,
        busDeEventos: bus,
      );

      await authRepo.iniciarSesion(
        identificador: 'ingeniero',
        contrasenia: '1234',
      );
      await notifVm.cargar();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificacionesIngenieroScreen(viewModel: notifVm),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // El apartado de prueba de envío manual fue eliminado
      expect(
        find.text('Enviar notificación mediante la aplicación'),
        findsNothing,
      );
      expect(find.text('Enviar notificación push'), findsNothing);

      // Permanece el recordatorio diario y el historial de alertas de semáforo
      expect(
        find.text('Recordatorio diario de sincronización'),
        findsOneWidget,
      );
      expect(find.text('Modificar horario'), findsOneWidget);
      expect(find.textContaining('Historial de alertas de semáforo'),
          findsOneWidget);

      // Alternar el switch actualiza el estado y SharedPreferences
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(notifVm.recordatorio.activo, isFalse);
      expect(prefsRepo.recordatorioLocal.activo, isFalse);
      expect(notifFalsas.recordatorioCancelado, isTrue);

      // El selector de horario del recordatorio usa formato de 24hs (sin AM/PM)
      await tester.tap(
        find.byKey(const Key('btn_modificar_horario_recordatorio')),
      );
      await tester.pumpAndSettle();
      expect(find.text('AM'), findsNothing);
      expect(find.text('PM'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      notifVm.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  testWidgets(
    'AgregarObraScreen renderiza sin overflow en pantalla angosta (360px)',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final bus = BusDeEventos();
      final db = BaseDatosLocalService();
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        busDeEventos: bus,
      );
      final obrasRepo = ObrasRepository(
        baseDatosService: db,
        busDeEventos: bus,
      );
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        autenticacionRepository: authRepo,
        busDeEventos: bus,
      );
      final obrasVm = ObrasViewModel(
        obrasRepository: obrasRepo,
        autenticacionRepository: authRepo,
        notificacionesRepository: notifRepo,
        sincronizacionService: SincronizacionService(),
        multimediaService: MultimediaService(),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const PoliticasFalsas(),
        busDeEventos: bus,
      );

      await authRepo.iniciarSesion(
        identificador: 'ingeniero',
        contrasenia: '1234',
      );
      await obrasVm.cargar(forzarRecarga: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgregarObraScreen(
              viewModel: obrasVm,
              capacidades: const CapacidadesFalsas(),
              onGuardado: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Mis tareas guardadas'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Mis tareas guardadas'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Mis materiales guardados'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Mis materiales guardados'), findsOneWidget);

      obrasVm.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  testWidgets(
    'CrearInformeScreen permite al Capataz guardar un informe diario y cierra la pantalla',
    (tester) async {
      final bus = BusDeEventos();
      final db = BaseDatosLocalService();
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        busDeEventos: bus,
      );
      final obrasRepo = ObrasRepository(
        baseDatosService: db,
        busDeEventos: bus,
      );
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        autenticacionRepository: authRepo,
        busDeEventos: bus,
      );
      final obrasVm = ObrasViewModel(
        obrasRepository: obrasRepo,
        autenticacionRepository: authRepo,
        notificacionesRepository: notifRepo,
        sincronizacionService: SincronizacionService(),
        multimediaService: MultimediaService(),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const PoliticasFalsas(),
        busDeEventos: bus,
      );

      await authRepo.iniciarSesion(
        identificador: 'capataz',
        contrasenia: '1234',
      );
      await obrasVm.cargar(forzarRecarga: true);
      final obraCapataz = obrasVm.obrasFiltradas.first;
      final reportesAntes = obrasVm.reportes.length;
      bool? resultadoPop;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    resultadoPop = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute<bool>(
                        builder: (_) => CrearInformeScreen(
                          obra: obraCapataz,
                          viewModel: obrasVm,
                          capacidades: const CapacidadesFalsas(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Abrir informe'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir informe'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('btn_guardar_informe_diario')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_guardar_informe_diario')));
      await tester.pumpAndSettle();

      expect(resultadoPop, isTrue);
      expect(obrasVm.reportes.length, reportesAntes + 1);
      expect(obrasVm.mensajeError, isNull);

      obrasVm.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  testWidgets(
    'CrearInformeScreen recupera borrador, muestra estado de tareas y permite agregar material ad-hoc',
    (tester) async {
      final bus = BusDeEventos();
      final db = BaseDatosLocalService();
      final prefsRepo = PreferenciasRepository();
      await prefsRepo.guardarBorradorObservaciones('Borrador guardado en obra');
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        preferenciasRepository: prefsRepo,
        busDeEventos: bus,
      );
      final obrasRepo = ObrasRepository(
        baseDatosService: db,
        busDeEventos: bus,
      );
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        autenticacionRepository: authRepo,
        busDeEventos: bus,
      );
      final obrasVm = ObrasViewModel(
        obrasRepository: obrasRepo,
        autenticacionRepository: authRepo,
        notificacionesRepository: notifRepo,
        sincronizacionService: SincronizacionService(),
        multimediaService: MultimediaService(),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const PoliticasFalsas(),
        preferenciasRepository: prefsRepo,
        busDeEventos: bus,
      );

      await authRepo.iniciarSesion(
        identificador: 'capataz',
        contrasenia: '1234',
      );
      await obrasVm.cargar(forzarRecarga: true);
      final obraCapataz = obrasVm.obrasFiltradas.first;

      await tester.pumpWidget(
        MaterialApp(
          home: CrearInformeScreen(
            obra: obraCapataz,
            viewModel: obrasVm,
            capacidades: const CapacidadesFalsas(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Recuperación de borrador (banner visible arriba y texto en campo de observaciones)
      expect(
        find.byKey(const Key('banner_borrador_recuperado')),
        findsOneWidget,
      );

      // Indicador de estado de tareas en dropdown
      await tester.tap(find.byKey(const Key('dropdown_tarea_informe')));
      await tester.pumpAndSettle();
      expect(find.text('Completa'), findsWidgets);
      expect(find.text('En curso'), findsWidgets);
      // Cerrar menú desplegable tocando el elemento actual
      await tester.tap(find.text(obraCapataz.tareaActual).last);
      await tester.pumpAndSettle();

      // Desplazar hasta el campo de observaciones y verificar el borrador cargado
      await tester.scrollUntilVisible(
        find.byKey(const Key('campo_observaciones_informe')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Borrador guardado en obra'), findsOneWidget);

      // Material ad-hoc
      await tester.scrollUntilVisible(
        find.byKey(const Key('campo_material_ad_hoc')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester
          .ensureVisible(find.byKey(const Key('campo_material_ad_hoc')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('campo_material_ad_hoc')),
        'Cal hidratada',
      );
      await tester.ensureVisible(
        find.byKey(const Key('btn_agregar_material_ad_hoc')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_agregar_material_ad_hoc')));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilterChip, 'Cal hidratada'),
        findsOneWidget,
      );

      // Volver arriba y descartar el borrador recuperado
      await tester.scrollUntilVisible(
        find.byKey(const Key('btn_descartar_borrador')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_descartar_borrador')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('banner_borrador_recuperado')),
        findsNothing,
      );

      obrasVm.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  testWidgets(
    'DetalleObraEnriquecidoSheet bloquea edición en obras finalizadas y permite reabrirlas',
    (tester) async {
      final bus = BusDeEventos();
      final db = BaseDatosLocalService();
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        busDeEventos: bus,
      );
      final obrasRepo = ObrasRepository(
        baseDatosService: db,
        busDeEventos: bus,
      );
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        autenticacionRepository: authRepo,
        busDeEventos: bus,
      );
      final obrasVm = ObrasViewModel(
        obrasRepository: obrasRepo,
        autenticacionRepository: authRepo,
        notificacionesRepository: notifRepo,
        sincronizacionService: SincronizacionService(),
        multimediaService: MultimediaService(),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const PoliticasFalsas(),
        busDeEventos: bus,
      );

      await authRepo.iniciarSesion(
        identificador: 'ingeniero',
        contrasenia: '1234',
      );
      await obrasVm.cargar(forzarRecarga: true);
      await obrasVm.cambiarObraFinalizada('1', finalizada: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetalleObraEnriquecidoSheet(
              obraId: '1',
              viewModel: obrasVm,
              capacidades: const CapacidadesFalsas(),
              permiteEdicion: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Modo solo lectura activo y acciones bloqueadas
      expect(
        find.byKey(const Key('card_obra_finalizada_solo_lectura')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('segmented_semaforo_detalle')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('btn_detalle_realizar_informe')),
        findsNothing,
      );

      // Reabrir obra
      await tester.ensureVisible(find.byKey(const Key('btn_reabrir_obra')));
      await tester.tap(find.byKey(const Key('btn_reabrir_obra')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_confirmar_reabrir_obra')));
      await tester.pumpAndSettle();

      expect(obrasVm.obtenerObraPorId('1')!.finalizada, isFalse);
      expect(
        find.byKey(const Key('segmented_semaforo_detalle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('btn_detalle_realizar_informe')),
        findsOneWidget,
      );

      obrasVm.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  testWidgets(
    'InicioCapatazScreen centra el mensaje vacío cuando no hay obras coincidentes y ofrece limpiar filtro',
    (tester) async {
      final bus = BusDeEventos();
      final db = BaseDatosLocalService();
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        busDeEventos: bus,
      );
      final obrasRepo = ObrasRepository(
        baseDatosService: db,
        busDeEventos: bus,
      );
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        autenticacionRepository: authRepo,
        busDeEventos: bus,
      );
      final obrasVm = ObrasViewModel(
        obrasRepository: obrasRepo,
        autenticacionRepository: authRepo,
        notificacionesRepository: notifRepo,
        sincronizacionService: SincronizacionService(),
        multimediaService: MultimediaService(),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const PoliticasFalsas(),
        busDeEventos: bus,
      );

      await authRepo.iniciarSesion(
        identificador: 'capataz',
        contrasenia: '1234',
      );
      await obrasVm.cargar(forzarRecarga: true);
      obrasVm.alternarFiltroFinalizadas(true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InicioCapatazScreen(
              viewModel: obrasVm,
              capacidades: const CapacidadesFalsas(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textoVacio = tester.widget<Text>(
        find.text('No hay obras finalizadas asignadas a tu perfil.'),
      );
      expect(textoVacio.textAlign, TextAlign.center);
      expect(
        find.byKey(const Key('btn_limpiar_filtros_vacio')),
        findsOneWidget,
      );

      obrasVm.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );
}
