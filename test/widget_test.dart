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
import 'package:constructora_del_sur/ui/obras/view_models/obras_view_model.dart';
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

      await tester.tap(find.byKey(const Key('boton_iniciar_sesion')));
      await tester.pump();

      expect(
        find.byKey(const Key('mensaje_credenciales_invalidas')),
        findsOneWidget,
      );

      // Ingresar como capataz y verificar teléfono visible en Perfil
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

      await notifFalsas.dispose();
      await bus.dispose();
    },
  );
}
