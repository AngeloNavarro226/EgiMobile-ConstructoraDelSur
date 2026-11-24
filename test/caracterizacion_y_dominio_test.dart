import 'package:constructora_del_sur/data/repositories/autenticacion_repository.dart';
import 'package:constructora_del_sur/data/repositories/notificaciones_repository.dart';
import 'package:constructora_del_sur/data/repositories/obras_repository.dart';
import 'package:constructora_del_sur/data/repositories/preferencias_repository.dart';
import 'package:constructora_del_sur/data/services/base_datos_local_service.dart';
import 'package:constructora_del_sur/data/services/bus_de_eventos.dart';
import 'package:constructora_del_sur/data/services/configuracion_supabase.dart';
import 'package:constructora_del_sur/data/services/fuente_datos_remota.dart';
import 'package:constructora_del_sur/data/services/mapa_service.dart';
import 'package:constructora_del_sur/data/services/motor_sincronizacion.dart';
import 'package:constructora_del_sur/data/services/multimedia_service.dart';
import 'package:constructora_del_sur/data/services/sincronizacion_service.dart';
import 'package:constructora_del_sur/data/services/supabase_remote_service.dart';
import 'package:constructora_del_sur/data/services/voz_a_texto_service.dart';
import 'package:constructora_del_sur/domain/models/evento_de_app.dart';
import 'package:constructora_del_sur/domain/models/formato_fecha.dart';
import 'package:constructora_del_sur/domain/models/horarios.dart';
import 'package:constructora_del_sur/domain/models/obra.dart';
import 'package:constructora_del_sur/domain/models/plantilla_obra.dart';
import 'package:constructora_del_sur/domain/models/reporte_diario.dart';
import 'package:constructora_del_sur/domain/models/tarea_obra.dart';
import 'package:constructora_del_sur/domain/models/ubicacion_obra.dart';
import 'package:constructora_del_sur/domain/models/usuario.dart';
import 'package:constructora_del_sur/plataforma/politicas.dart';
import 'package:constructora_del_sur/ui/autenticacion/view_models/autenticacion_view_model.dart';
import 'package:constructora_del_sur/ui/core/view_model_base.dart';
import 'package:constructora_del_sur/ui/exportar/view_models/exportar_view_model.dart';
import 'package:constructora_del_sur/ui/notificaciones/view_models/notificaciones_view_model.dart';
import 'package:constructora_del_sur/ui/obras/view_models/obras_view_model.dart';
import 'package:constructora_del_sur/ui/perfil/view_models/perfil_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Obra calcula automáticamente el porcentaje de avance según tareas completas',
    () {
      final obra = Obra(
        id: 'o1',
        nombre: 'Obra de prueba',
        estado: EstadoObra.aTiempo,
        fechaUltimoReporte: DateTime(2026, 9, 18),
        responsableId: 'u_capataz',
        responsableNombre: 'Carlos Méndez',
        tareas: const [
          TareaObra(id: '1', nombre: 'Excavación', completada: true),
          TareaObra(id: '2', nombre: 'Fundaciones', completada: true),
          TareaObra(id: '3', nombre: 'Mampostería', completada: false),
          TareaObra(id: '4', nombre: 'Techado', completada: false),
        ],
        materiales: const ['Cemento', 'Arena'],
        ubicacion: const UbicacionObra(
          latitud: -32.8895,
          longitud: -68.8458,
          direccion: 'Mendoza',
        ),
      );

      expect(obra.avance, 0.5);
      expect(obra.porcentajeAvance, 50);
      expect(obra.tareaActual, 'Mampostería');
      expect(obra.tareasCompletas.length, 2);
      expect(obra.tareasPendientes.length, 2);
    },
  );

  test(
    'Autenticación valida usuarios, persiste sesión offline y rechaza credenciales inválidas',
    () async {
      final db = BaseDatosLocalService();
      final prefs = PreferenciasRepository();
      final repo = AutenticacionRepository(
        baseDatosService: db,
        preferenciasRepository: prefs,
      );
      final vm = AutenticacionViewModel(repositorio: repo);

      final fallo = await vm.iniciarSesion(
        usuario: 'usuario_inexistente',
        contrasenia: '0000',
      );
      expect(fallo, isFalse);
      expect(vm.credencialesInvalidas, isTrue);

      final okCapataz = await vm.iniciarSesion(
        usuario: 'capataz',
        contrasenia: '1234',
      );
      expect(okCapataz, isTrue);
      expect(vm.credencialesInvalidas, isFalse);
      expect(vm.usuarioActual?.rol, Rol.capataz);
      expect(vm.usuarioActual?.rol.tipo, RolUsuario.capataz);
      expect(vm.usuarioActual?.telefono, '+54 9 261 555-0102');

      // Nueva instancia restaura la sesión offline desde PreferenciasRepository
      final repoRestaurado = AutenticacionRepository(
        baseDatosService: db,
        preferenciasRepository: prefs,
      );
      final vmRestaurado = AutenticacionViewModel(repositorio: repoRestaurado);
      final restaurado = await vmRestaurado.restaurarSesion();
      expect(restaurado, isTrue);
      expect(vmRestaurado.usuarioActual?.id, 'u_capataz');
    },
  );

  test(
    'Roles (1:N), columna telefono y normalización 3FN mantienen integridad sin anomalías',
    () async {
      final db = BaseDatosLocalService();
      final authRepo = AutenticacionRepository(baseDatosService: db);
      final obrasRepo = ObrasRepository(baseDatosService: db);

      final roles = await authRepo.obtenerRoles();
      expect(roles.length, 3);
      expect(
        roles.map((r) => r.codigo),
        containsAll(['ingeniero', 'capataz', 'duenio']),
      );

      final usuarios = await authRepo.obtenerUsuarios();
      expect(usuarios.length, 3);
      expect(usuarios.first.toMap().containsKey('telefono'), isTrue);
      expect(usuarios.first.toMap().containsKey('rol_id'), isTrue);

      // Escalabilidad 1:N: permite crear un segundo capataz compartiendo rol_capataz
      await db.guardarUsuarioCrudo({
        'id': 'u_capataz_2',
        'username': 'capataz2',
        'rol_id': 'rol_capataz',
        'nombre': 'Luis Gómez (Capataz)',
        'contrasenia': '1234',
        'telefono': '+54 9 261 555-0199',
      });
      final usuariosConSegundoCapataz =
          await authRepo.obtenerUsuarios(forzarRecarga: true);
      expect(usuariosConSegundoCapataz.length, 4);

      // FK inválida sobre rol_id debe fallar
      await expectLater(
        () => db.guardarUsuarioCrudo({
          'id': 'u_invalido',
          'username': 'invalido',
          'rol_id': 'rol_inexistente',
          'nombre': 'Inválido',
          'contrasenia': '1234',
          'telefono': '',
        }),
        throwsStateError,
      );

      // Editar nombre y teléfono actualiza dinámicamente obras/reportes vía JOIN
      await authRepo.iniciarSesion(
        identificador: 'capataz',
        contrasenia: '1234',
      );
      final actualizado = await authRepo.actualizarPerfil(
        nombre: 'Carlos Méndez Actualizado',
        telefono: '+54 9 261 999-8888',
        contrasenia: '1234',
      );
      expect(actualizado.telefono, '+54 9 261 999-8888');
      expect(actualizado.syncStatus, EstadoSincronizacion.pending);

      final obras = await obrasRepo.obtenerObras(forzarRecarga: true);
      final obraCapataz =
          obras.firstWhere((o) => o.responsableId == 'u_capataz');
      expect(obraCapataz.responsableNombre, 'Carlos Méndez Actualizado');

      final reportes = await obrasRepo.obtenerReportesPorObra('1');
      expect(reportes, isNotEmpty);
      expect(reportes.first.autorNombre, 'Carlos Méndez Actualizado');

      // FK inválida sobre obra_id en reporte debe fallar
      await expectLater(
        () => obrasRepo.registrarReporteDiario(
          ReporteDiario(
            id: 'rep_fk_error',
            obraId: 'obra_inexistente',
            obraNombre: '',
            autorId: 'u_capataz',
            autorNombre: 'Carlos Méndez Actualizado',
            fechaCreacionLocal: DateTime.utc(2026, 10, 15),
            tareaSeleccionada: 'Tarea',
            tareaCompletadaEnInforme: false,
            materialesUsados: const [],
            observaciones: '',
            urlFotos: const [],
            estadoSemaforo: EstadoObra.aTiempo,
          ),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'MotorSincronizacion ejecuta Push -> Pull con fotos, reintentos y local-pending wins',
    () async {
      final reloj = RelojFijo(DateTime.utc(2026, 11, 21, 15, 0));
      final db = BaseDatosLocalService(reloj: reloj);
      final bus = BusDeEventos();
      final remoto = FakeFuenteDatosRemota(simularErrorRed: true);
      final motor = MotorSincronizacion(
        baseDatosLocal: db,
        fuenteRemota: remoto,
        reloj: reloj,
        busDeEventos: bus,
      );
      final obrasRepo = ObrasRepository(
        baseDatosService: db,
        reloj: reloj,
        generadorIds: GeneradorIdsSecuencial(prefijo: 'uuid'),
        motorSincronizacion: motor,
        busDeEventos: bus,
      );

      // Crear reporte offline con foto local pendiente
      await obrasRepo.registrarReporteDiario(
        ReporteDiario(
          id: 'rep_offline_1',
          obraId: '1',
          obraNombre: 'Torre Residencial Las Heras',
          autorId: 'u_capataz',
          autorNombre: 'Carlos Méndez (Capataz)',
          fechaCreacionLocal: reloj.ahora(),
          tareaSeleccionada: 'Losa de planta alta',
          tareaCompletadaEnInforme: false,
          materialesUsados: const ['Hormigón H-21'],
          observaciones: 'Reporte cargado sin señal',
          urlFotos: const [
            FotoComprimida(
              rutaLocal: '/tmp/foto_terreno.jpg',
              origen: 'Cámara en obra',
              anchoPx: 800,
              altoPx: 600,
              calidadPct: 70,
              pesoKb: 120,
            ),
          ],
          estadoSemaforo: EstadoObra.demorada,
        ),
      );

      // 1. Con falla de red: queda pending y se registra en cola_sincronizacion
      final fallo = await obrasRepo.sincronizarTodo(
        permitirSimulacionLocal: false,
      );
      expect(fallo.tuvoErrores, isTrue);
      expect(fallo.fallidos, greaterThan(0));
      final erroresCola = await db.obtenerFallosSincronizacion();
      expect(erroresCola, isNotEmpty);

      // 2. Al recuperar red: sube foto a Storage, hace upsert y pasa a synced
      remoto.simularErrorRed = false;
      remoto.cambiosParaPull = CambiosRemotos(
        obras: [
          {
            'id': '2',
            'nombre': 'Complejo Belgrano (Remoto)',
            'estado_semaforo': 'aTiempo',
            'fecha_ultimo_reporte':
                DateTime.utc(2026, 11, 21, 14, 0).toIso8601String(),
            'responsable_id': 'u_capataz',
            'ubicacion_latitud': -32.8895,
            'ubicacion_longitud': -68.8458,
            'ubicacion_direccion': 'Av. Belgrano 820, Ciudad de Mendoza',
            'observaciones': 'Actualizado desde otro dispositivo',
            'con_foto': 1,
            'imagen': 'assets/images/obra2.png',
            'imagen_url': 'https://storage.fake.local/portada2.jpg',
            'finalizada': 0,
            'updated_at': DateTime.utc(2026, 11, 21, 14, 0).toIso8601String(),
            'tareas': const <Map<String, dynamic>>[],
            'materiales': const ['Cemento Portland'],
          },
        ],
      );

      final exito = await obrasRepo.sincronizarTodo(
        permitirSimulacionLocal: false,
      );
      expect(exito.tuvoErrores, isFalse);
      expect(
          remoto.fotosSubidas, contains('fotos-obras/1/rep_offline_1_0.jpg'));
      expect(remoto.reportesRemotos.containsKey('rep_offline_1'), isTrue);
      expect(await db.obtenerFallosSincronizacion(), isEmpty);

      final reporteSync = (await obrasRepo.obtenerReportesPorObra('1'))
          .firstWhere((r) => r.id == 'rep_offline_1');
      expect(reporteSync.syncStatus, EstadoSincronizacion.synced);
      expect(
        reporteSync.urlFotos.first.urlRemota,
        'https://storage.fake.local/fotos-obras/1/rep_offline_1_0.jpg',
      );

      // Verificar que Pull aplicó la obra remota 2
      final obra2 = (await obrasRepo.obtenerObras(forzarRecarga: true))
          .firstWhere((o) => o.id == '2');
      expect(obra2.nombre, 'Complejo Belgrano (Remoto)');
      expect(obra2.imagenUrl, 'https://storage.fake.local/portada2.jpg');

      // 3. Local-pending wins: una edición local en obra 2 no debe ser pisada por Pull
      await obrasRepo.cambiarEstadoSemaforo('2', EstadoObra.problemas);
      remoto.simularErrorRed = true;
      await motor.sincronizarTodo(permitirSimulacionLocal: false);
      final obra2TrasFallo = (await obrasRepo.obtenerObras(forzarRecarga: true))
          .firstWhere((o) => o.id == '2');
      expect(obra2TrasFallo.estado, EstadoObra.problemas);

      // 4. Reintento idempotente sin duplicados
      remoto.simularErrorRed = false;
      final reintento = await obrasRepo.sincronizarTodo(
        permitirSimulacionLocal: false,
      );
      expect(reintento.tuvoErrores, isFalse);
      expect(remoto.reportesRemotos.length, 2);

      // 5. Obra nueva con foto de portada sube automáticamente a Storage
      await obrasRepo.guardarObra(
        Obra(
          id: 'obra_portada_1',
          nombre: 'Obra Con Portada',
          estado: EstadoObra.aTiempo,
          fechaUltimoReporte: reloj.ahora(),
          responsableId: 'u_capataz',
          responsableNombre: 'Carlos Méndez (Capataz)',
          tareas: const [],
          materiales: const ['Cemento'],
          ubicacion: const UbicacionObra(
            latitud: -32.88,
            longitud: -68.84,
            direccion: 'Mendoza',
          ),
          conFoto: true,
          imagen: 'AQIDBA==',
        ),
      );
      final syncPortada = await obrasRepo.sincronizarTodo(
        permitirSimulacionLocal: false,
      );
      expect(syncPortada.tuvoErrores, isFalse);
      expect(remoto.fotosSubidas,
          contains('fotos-obras/portadas/obra_portada_1.jpg'));
      expect(
        remoto.obrasRemotas['obra_portada_1']?['imagen_url'],
        'https://storage.fake.local/fotos-obras/portadas/obra_portada_1.jpg',
      );

      await bus.dispose();
    },
  );

  test(
    'Obras finalizadas se ocultan por defecto y se muestran al activar el filtro Finalizadas',
    () async {
      final reloj = RelojFijo(DateTime.utc(2026, 10, 15, 10, 30));
      final db = BaseDatosLocalService(reloj: reloj);
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        reloj: reloj,
      );
      final obrasRepo = ObrasRepository(baseDatosService: db, reloj: reloj);
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        reloj: reloj,
        autenticacionRepository: authRepo,
      );
      final bus = BusDeEventos();

      final vm = ObrasViewModel(
        obrasRepository: obrasRepo,
        autenticacionRepository: authRepo,
        notificacionesRepository: notifRepo,
        sincronizacionService: SincronizacionService(),
        multimediaService: MultimediaService(reloj: reloj),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const PoliticasFalsas(),
        busDeEventos: bus,
        reloj: reloj,
      );
      await vm.cargar();
      await authRepo.iniciarSesion(
        identificador: 'ingeniero',
        contrasenia: '1234',
      );

      expect(vm.obrasFiltradas.length, 6);
      expect(vm.cantidadFinalizadas, 0);

      final primeraObra = vm.obrasFiltradas.first;
      await vm.guardarInformeDiario(
        obra: primeraObra,
        tareaSeleccionada: primeraObra.tareaActual,
        marcarTareaComoCompletada: true,
        materialesGastados: const ['Cemento Portland'],
        observaciones: 'Obra concluida satisfactoriamente',
        estadoSemaforo: EstadoObra.aTiempo,
        fotosAdjuntas: const [],
        finalizarObra: true,
      );

      expect(vm.cantidadFinalizadas, 1);
      expect(vm.obrasFiltradas.length, 5);
      expect(vm.obrasFiltradas.any((o) => o.id == primeraObra.id), isFalse);

      vm.alternarFiltroFinalizadas(true);
      expect(vm.mostrarSoloFinalizadas, isTrue);
      expect(vm.obrasFiltradas.length, 1);
      expect(vm.obrasFiltradas.first.id, primeraObra.id);
      expect(vm.obrasFiltradas.first.finalizada, isTrue);

      vm.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  test(
    'Todos los ViewModels notifican explícitamente en cargando, exito y error (y protegen dispose)',
    () async {
      final bus = BusDeEventos();
      final dbOk = BaseDatosLocalService();
      final dbErr = BaseDatosLocalConError();
      final notifFalsas = NotificacionesFalsas();
      final syncService = SincronizacionService();

      // 1. ObrasViewModel: éxito y error
      final obrasVmOk = ObrasViewModel(
        obrasRepository: ObrasRepository(baseDatosService: dbOk),
        autenticacionRepository:
            AutenticacionRepository(baseDatosService: dbOk),
        notificacionesRepository: NotificacionesRepository(
          baseDatosService: dbOk,
          notificacionesSistemaService: notifFalsas,
          busDeEventos: bus,
        ),
        sincronizacionService: syncService,
        multimediaService: MultimediaService(),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const PoliticasFalsas(),
        busDeEventos: bus,
      );
      final estadosObrasOk = <EstadoCargaObras>[];
      obrasVmOk.addListener(() => estadosObrasOk.add(obrasVmOk.estado));
      await obrasVmOk.cargar();
      expect(
        estadosObrasOk,
        [EstadoCargaObras.cargando, EstadoCargaObras.exito],
      );

      final obrasVmErr = ObrasViewModel(
        obrasRepository: ObrasRepository(baseDatosService: dbErr),
        autenticacionRepository:
            AutenticacionRepository(baseDatosService: dbErr),
        notificacionesRepository: NotificacionesRepository(
          baseDatosService: dbErr,
          notificacionesSistemaService: notifFalsas,
        ),
        sincronizacionService: SincronizacionService(),
        multimediaService: MultimediaService(),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const PoliticasFalsas(),
      );
      final estadosObrasErr = <EstadoCargaObras>[];
      obrasVmErr.addListener(() => estadosObrasErr.add(obrasVmErr.estado));
      await obrasVmErr.cargar();
      expect(
        estadosObrasErr,
        [EstadoCargaObras.cargando, EstadoCargaObras.error],
      );
      expect(obrasVmErr.mensajeError, isNotNull);

      // 2. AutenticacionViewModel: error de BD no bloquea estaCargando
      final authVmErr = AutenticacionViewModel(
        repositorio: AutenticacionRepository(baseDatosService: dbErr),
      );
      final estadosAuthErr = <EstadoOperacion>[];
      authVmErr.addListener(() => estadosAuthErr.add(authVmErr.estado));
      final okAuth = await authVmErr.iniciarSesion(
        usuario: 'capataz',
        contrasenia: '1234',
      );
      expect(okAuth, isFalse);
      expect(authVmErr.estaCargando, isFalse);
      expect(estadosAuthErr, [EstadoOperacion.cargando, EstadoOperacion.error]);
      expect(authVmErr.mensajeError, isNotNull);

      // 3. NotificacionesViewModel: éxito, error y refresco por BusDeEventos
      final notifVmErr = NotificacionesViewModel(
        repositorio: NotificacionesRepository(
          baseDatosService: dbErr,
          notificacionesSistemaService: notifFalsas,
        ),
      );
      final estadosNotifErr = <EstadoOperacion>[];
      notifVmErr.addListener(() => estadosNotifErr.add(notifVmErr.estado));
      await notifVmErr.cargar();
      expect(notifVmErr.cargando, isFalse);
      expect(
        estadosNotifErr,
        [EstadoOperacion.cargando, EstadoOperacion.error],
      );

      // 4. ExportarViewModel: genera contenido asíncrono y notifica estados
      final exportarVm = ExportarViewModel(
        obrasRepository: ObrasRepository(baseDatosService: dbOk),
        busDeEventos: bus,
      );
      final estadosExport = <EstadoOperacion>[];
      exportarVm.addListener(() => estadosExport.add(exportarVm.estado));
      await exportarVm.actualizarDatos();
      expect(estadosExport, [EstadoOperacion.cargando, EstadoOperacion.exito]);
      expect(exportarVm.contenidoExportado, contains('obra_id'));

      // 5. PerfilViewModel: inicializarPreferencias + editar teléfono + dispose seguro
      final prefsRepo = PreferenciasRepository();
      final authRepoOk = AutenticacionRepository(baseDatosService: dbOk);
      await authRepoOk.iniciarSesion(
        identificador: 'ingeniero',
        contrasenia: '1234',
      );
      final perfilVm = PerfilViewModel(
        autenticacionRepository: authRepoOk,
        preferenciasRepository: prefsRepo,
        sincronizacionService: syncService,
      );
      final estadosPerfil = <EstadoOperacion>[];
      perfilVm.addListener(() => estadosPerfil.add(perfilVm.estado));
      await perfilVm.inicializarPreferencias();
      expect(estadosPerfil, [EstadoOperacion.cargando, EstadoOperacion.exito]);

      final editOk = await perfilVm.actualizarDatosPerfil(
        nombre: 'Ing. Braulio',
        telefono: '+54 9 261 777-0000',
        contrasenia: '1234',
      );
      expect(editOk, isTrue);
      expect(perfilVm.usuarioActual?.telefono, '+54 9 261 777-0000');

      // Dispose seguro: no lanza excepción si se invoca después
      perfilVm.dispose();
      await perfilVm.inicializarPreferencias();

      obrasVmOk.dispose();
      obrasVmErr.dispose();
      authVmErr.dispose();
      notifVmErr.dispose();
      exportarVm.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  test(
    'NotificacionesRepository resuelve destinatarios FCM según rol emisor (Capataz vs Ingeniero) y respeta PoliticaDeAvisos',
    () async {
      final db = BaseDatosLocalService();
      final authRepo = AutenticacionRepository(baseDatosService: db);
      final notifFalsas = NotificacionesFalsas();
      final repo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        reloj: RelojFijo(DateTime.utc(2026, 10, 15, 18, 0)),
        autenticacionRepository: authRepo,
      );

      final usuarios = await authRepo.obtenerUsuarios();
      final capataz = usuarios.firstWhere((u) => u.id == 'u_capataz');
      final ingeniero = usuarios.firstWhere((u) => u.id == 'u_ingeniero');

      final obraVerde = Obra(
        id: '10',
        nombre: 'Obra Verde',
        estado: EstadoObra.aTiempo,
        fechaUltimoReporte: DateTime.utc(2026, 10, 15),
        responsableId: 'u_capataz',
        responsableNombre: 'Carlos Méndez (Capataz)',
        ingenieroId: 'u_ingeniero',
        ingenieroNombre: 'Ing. Braulio Hormigón',
        tareas: const [],
        materiales: const [],
        ubicacion: const UbicacionObra(
          latitud: -32.88,
          longitud: -68.84,
          direccion: 'Mendoza',
        ),
      );
      final alertaVerde = await repo.emitirAlertaCambioSemaforo(
        obra: obraVerde,
        motivo: 'En término',
        emisor: capataz,
      );
      expect(alertaVerde, isNull);
      expect(notifFalsas.mostradas, isEmpty);

      // 1. Cambio hecho por Capataz -> notifica al Ingeniero a cargo y al Dueño
      final obraRoja = obraVerde.copyWith(estado: EstadoObra.problemas);
      final alertaDesdeCapataz = await repo.emitirAlertaCambioSemaforo(
        obra: obraRoja,
        motivo: 'Falta de insumos',
        emisor: capataz,
      );
      expect(alertaDesdeCapataz, isNotNull);
      expect(alertaDesdeCapataz!.emisorId, 'u_capataz');
      expect(
          alertaDesdeCapataz.destinatario, contains('Ing. Braulio Hormigón'));
      expect(alertaDesdeCapataz.destinatario, contains('Roberto Del Sur'));
      expect(alertaDesdeCapataz.destinatario, isNot(contains('Carlos Méndez')));
      // No muestra notificación local falsa al propio emisor
      expect(notifFalsas.mostradas, isEmpty);

      // 2. Cambio hecho por Ingeniero -> notifica al Capataz a cargo y al Dueño
      final obraAmarilla = obraVerde.copyWith(estado: EstadoObra.demorada);
      final alertaDesdeIngeniero = await repo.emitirAlertaCambioSemaforo(
        obra: obraAmarilla,
        motivo: 'Demora en entrega de proveedor',
        emisor: ingeniero,
      );
      expect(alertaDesdeIngeniero, isNotNull);
      expect(alertaDesdeIngeniero!.emisorId, 'u_ingeniero');
      expect(
        alertaDesdeIngeniero.destinatario,
        contains('Carlos Méndez (Capataz)'),
      );
      expect(alertaDesdeIngeniero.destinatario, contains('Roberto Del Sur'));
      expect(
        alertaDesdeIngeniero.destinatario,
        isNot(contains('Ing. Braulio Hormigón')),
      );

      await notifFalsas.dispose();
    },
  );

  test(
    'Funciones puras de SegundoPlano y MapaService transcriben horarios y lugares',
    () async {
      final fijo = DateTime(2026, 6, 15, 9, 30);
      expect(horaDelRecordatorio(fijo), DateTime(2026, 6, 15, 18, 0));
      expect(
        proximaOcurrenciaDiaria(ahora: fijo, hora: 8, minuto: 0),
        DateTime(2026, 6, 16, 8, 0),
      );

      final mapa = MapaService();
      final lugar = mapa.transcribirLugarLocalmente(-32.8489, -68.8392);
      expect(lugar, contains('Las Heras'));

      final evento = const SincronizacionCompletada(3);
      expect(evento.reportesSincronizados, 3);

      // Workmanager devuelve false ante fallos transitorios para activar backoff
      final resultadoOk = await ejecutarTareaSincronizacion(
        tareaSincronizacionWorkmanager,
        null,
        ejecutor: () async => true,
      );
      final resultadoFallo = await ejecutarTareaSincronizacion(
        tareaSincronizacionWorkmanager,
        null,
        ejecutor: () async => throw StateError('Red caída'),
      );
      expect(resultadoOk, isTrue);
      expect(resultadoFallo, isFalse);
    },
  );

  test(
    'AutenticacionRepository con Supabase Auth cachea perfil sin contraseña y restaura offline',
    () async {
      final db = BaseDatosLocalService(insertarSemillasDePrueba: false);
      final prefs = PreferenciasRepository();
      final authRemota = FakeServicioAutenticacionRemota(
        perfilesPorEmail: {
          'capataz@constructoradelsur.com': {
            'id': '11111111-1111-4111-8111-111111111102',
            'username': 'capataz',
            'rol_id': 'rol_capataz',
            'rol_codigo': 'capataz',
            'rol_nombre': 'Capataz de Obra',
            'nombre': 'Carlos Méndez (Capataz)',
            'telefono': '+54 9 261 555-0102',
            'updated_at': DateTime.utc(2026, 11, 22).toIso8601String(),
          },
        },
      );
      final repo = AutenticacionRepository(
        baseDatosService: db,
        preferenciasRepository: prefs,
        authRemota: authRemota,
      );

      // Acepta username corto y lo resuelve al dominio corporativo
      final logueado = await repo.iniciarSesion(
        identificador: 'capataz',
        contrasenia: 'Password123!',
      );
      expect(logueado, isNotNull);
      expect(authRemota.ultimoEmailRecibido, 'capataz@constructoradelsur.com');
      expect(logueado!.contrasenia, isEmpty);
      expect(logueado.rol, Rol.capataz);

      // Sin red, restaura sesión desde SQLite local usando la sesión persistida
      authRemota.simularOfflineEnRefresh = true;
      final repoOffline = AutenticacionRepository(
        baseDatosService: db,
        preferenciasRepository: prefs,
        authRemota: authRemota,
      );
      final restaurado = await repoOffline.restaurarSesionGuardada();
      expect(restaurado?.id, '11111111-1111-4111-8111-111111111102');
      expect(restaurado?.telefono, '+54 9 261 555-0102');

      await repoOffline.cerrarSesion();
      expect(authRemota.cerroSesionRemota, isTrue);
      expect(repoOffline.usuarioActual, isNull);
    },
  );

  test(
    'ConfiguracionSupabase y mapeadores de SupabaseRemoteService convierten tipos SQLite <-> Postgres',
    () {
      const configVacia = ConfiguracionSupabase(url: '', publishableKey: '');
      expect(configVacia.estaConfigurado, isFalse);

      expect(
        normalizarRutaEnBucket(
          destinoStorage: 'fotos-obras/obra1/rep1_0.jpg',
          bucket: 'fotos-obras',
        ),
        'obra1/rep1_0.jpg',
      );

      final usuarioRemoto = mapearUsuarioLocalARemoto({
        'id': 'u1',
        'username': 'capataz',
        'rol_id': 'rol_capataz',
        'nombre': 'Carlos',
        'contrasenia': 'secreto',
        'telefono': '+54 9 261 555-0102',
        'sync_status': 'pending',
      });
      expect(usuarioRemoto.containsKey('contrasenia'), isFalse);
      expect(usuarioRemoto.containsKey('sync_status'), isFalse);

      final obraRemota = mapearObraLocalARemoto({
        'id': 'o1',
        'nombre': 'Torre',
        'estado_semaforo': 'aTiempo',
        'fecha_ultimo_reporte': '2026-11-22T00:00:00Z',
        'responsable_id': 'u1',
        'ingeniero_id': 'u_ing',
        'ubicacion_latitud': -32.88,
        'ubicacion_longitud': -68.84,
        'ubicacion_direccion': 'Mendoza',
        'observaciones': '',
        'con_foto': 1,
        'imagen': null,
        'imagen_url': null,
        'finalizada': 0,
      });
      expect(obraRemota['con_foto'], isTrue);
      expect(obraRemota['finalizada'], isFalse);
      expect(obraRemota['ingeniero_id'], 'u_ing');

      final obraLocal = mapearObraRemotaALocal({
        ...obraRemota,
        'updated_at': '2026-11-22T00:00:00Z',
        'obra_materiales': [
          {'nombre': 'Cemento'},
        ],
        'tareas_obra': [
          {
            'id': 't1',
            'obra_id': 'o1',
            'nombre': 'Excavación',
            'completada': true,
            'orden': 0,
            'updated_at': '2026-11-22T00:00:00Z',
          },
        ],
      });
      expect(obraLocal['con_foto'], 1);
      expect(obraLocal['finalizada'], 0);
      expect(obraLocal['ingeniero_id'], 'u_ing');
      expect(obraLocal['materiales'], ['Cemento']);
      expect((obraLocal['tareas'] as List).first['completada'], 1);
    },
  );

  test(
    'Realtime dispara Pull silencioso automático en ObrasViewModel sin pulsar Sincronizar',
    () async {
      final reloj = RelojFijo(DateTime.utc(2026, 11, 22, 5, 0));
      final db = BaseDatosLocalService(reloj: reloj);
      final bus = BusDeEventos();
      final remoto = FakeFuenteDatosRemota();
      final authRemota = FakeServicioAutenticacionRemota(
        perfilesPorEmail: {
          'ingeniero@constructoradelsur.com': {
            'id': 'u_ingeniero',
            'username': 'ingeniero',
            'rol_id': 'rol_ingeniero',
            'rol_codigo': 'ingeniero',
            'rol_nombre': 'Ingeniero Jefe de Obra',
            'nombre': 'Ing. Braulio Hormigón',
            'telefono': '+54 9 261 555-0101',
            'updated_at': reloj.ahora().toIso8601String(),
          },
        },
      );
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        authRemota: authRemota,
        reloj: reloj,
        busDeEventos: bus,
      );
      final motor = MotorSincronizacion(
        baseDatosLocal: db,
        fuenteRemota: remoto,
        reloj: reloj,
        busDeEventos: bus,
      );
      final obrasRepo = ObrasRepository(
        baseDatosService: db,
        reloj: reloj,
        motorSincronizacion: motor,
        busDeEventos: bus,
      );
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        reloj: reloj,
      );

      final vm = ObrasViewModel(
        obrasRepository: obrasRepo,
        autenticacionRepository: authRepo,
        notificacionesRepository: notifRepo,
        sincronizacionService: SincronizacionService(),
        multimediaService: MultimediaService(reloj: reloj),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const PoliticasFalsas(),
        busDeEventos: bus,
        reloj: reloj,
      );

      await authRepo.iniciarSesion(
        identificador: 'ingeniero',
        contrasenia: 'Password123!',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Otro dispositivo cambia el semáforo de la obra '2' a 'problemas'
      remoto.cambiosParaPull = CambiosRemotos(
        obras: [
          {
            'id': '2',
            'nombre': 'Complejo Comercial Belgrano',
            'estado_semaforo': 'problemas',
            'fecha_ultimo_reporte': reloj.ahora().toIso8601String(),
            'responsable_id': 'u_capataz',
            'ubicacion_latitud': -32.8895,
            'ubicacion_longitud': -68.8458,
            'ubicacion_direccion': 'Av. Belgrano 820, Ciudad de Mendoza',
            'observaciones': 'Cambio en tiempo real desde otro teléfono',
            'con_foto': 1,
            'imagen': 'assets/images/obra2.png',
            'imagen_url': null,
            'finalizada': 0,
            'updated_at': reloj.ahora().toIso8601String(),
            'tareas': const <Map<String, dynamic>>[],
            'materiales': const ['Cemento Portland'],
          },
        ],
      );

      remoto.simularCambioRemoto('obras');
      await Future<void>.delayed(const Duration(milliseconds: 1400));

      final obraActualizada = vm.obtenerObraPorId('2');
      expect(obraActualizada?.estado, EstadoObra.problemas);
      expect(
        obraActualizada?.observaciones,
        'Cambio en tiempo real desde otro teléfono',
      );

      vm.dispose();
      await remoto.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  test(
    'Crear obra como ingeniero asignada a un capataz guarda ingenieroId y responsableId',
    () async {
      final reloj = RelojFijo(DateTime.utc(2026, 11, 22, 16, 0));
      final db = BaseDatosLocalService(reloj: reloj);
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        reloj: reloj,
      );
      final obrasRepo = ObrasRepository(baseDatosService: db, reloj: reloj);
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        reloj: reloj,
        autenticacionRepository: authRepo,
      );
      final bus = BusDeEventos();

      final vm = ObrasViewModel(
        obrasRepository: obrasRepo,
        autenticacionRepository: authRepo,
        notificacionesRepository: notifRepo,
        sincronizacionService: SincronizacionService(),
        multimediaService: MultimediaService(reloj: reloj),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const PoliticasFalsas(),
        busDeEventos: bus,
        reloj: reloj,
        generadorIds: GeneradorIdsSecuencial(prefijo: 'obra_ing'),
      );

      await authRepo.iniciarSesion(
        identificador: 'ingeniero',
        contrasenia: '1234',
      );
      await vm.cargar();
      final capataz = vm.responsablesDisponibles.firstWhere(
        (u) => u.id == 'u_capataz',
      );

      await vm.crearNuevaObra(
        nombre: 'Edificio Norte',
        responsable: capataz,
        nombresTareas: const ['Replanteo'],
        materiales: const ['Cemento'],
        ubicacion: const UbicacionObra(
          latitud: -32.89,
          longitud: -68.84,
          direccion: 'Av. Colón 300, Mendoza',
        ),
        estadoInicial: EstadoObra.aTiempo,
        observaciones: 'Inicio de obra',
      );

      final creada = vm.obrasFiltradas.firstWhere(
        (o) => o.nombre == 'Edificio Norte',
      );
      expect(creada.responsableId, 'u_capataz');
      expect(creada.ingenieroId, 'u_ingeniero');
      expect(creada.ingenieroNombre, 'Ing. Braulio Hormigón');

      final recargadas = await obrasRepo.obtenerObras(forzarRecarga: true);
      final desdeBd = recargadas.firstWhere((o) => o.id == creada.id);
      expect(desdeBd.responsableId, 'u_capataz');
      expect(desdeBd.ingenieroId, 'u_ingeniero');
      expect(desdeBd.ingenieroNombre, 'Ing. Braulio Hormigón');

      vm.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  test(
    'Sync en modo Supabase refresca responsables (capataces + ingeniero actual, sin otros ingenieros)',
    () async {
      final reloj = RelojFijo(DateTime.utc(2026, 11, 22, 17, 0));
      final db = BaseDatosLocalService(
        reloj: reloj,
        insertarSemillasDePrueba: false,
      );
      final bus = BusDeEventos();
      final remoto = FakeFuenteDatosRemota(
        cambiosParaPull: CambiosRemotos(
          usuarios: [
            {
              'id': 'ing_1',
              'username': 'ing1',
              'rol_id': 'rol_ingeniero',
              'nombre': 'Ing. Braulio Hormigón',
              'contrasenia': '',
              'telefono': '',
              'updated_at': reloj.ahora().toIso8601String(),
              'sync_status': 'synced',
            },
            {
              'id': 'ing_2',
              'username': 'ing2',
              'rol_id': 'rol_ingeniero',
              'nombre': 'Ing. Sofía Acero',
              'contrasenia': '',
              'telefono': '',
              'updated_at': reloj.ahora().toIso8601String(),
              'sync_status': 'synced',
            },
            {
              'id': 'cap_1',
              'username': 'cap1',
              'rol_id': 'rol_capataz',
              'nombre': 'Carlos Méndez (Capataz)',
              'contrasenia': '',
              'telefono': '',
              'updated_at': reloj.ahora().toIso8601String(),
              'sync_status': 'synced',
            },
            {
              'id': 'dueno_1',
              'username': 'dueno',
              'rol_id': 'rol_duenio',
              'nombre': 'Roberto Del Sur (Dueño)',
              'contrasenia': '',
              'telefono': '',
              'updated_at': reloj.ahora().toIso8601String(),
              'sync_status': 'synced',
            },
          ],
        ),
      );
      final authRemota = FakeServicioAutenticacionRemota(
        perfilesPorEmail: {
          'ing1@constructoradelsur.com': {
            'id': 'ing_1',
            'username': 'ing1',
            'rol_id': 'rol_ingeniero',
            'rol_codigo': 'ingeniero',
            'rol_nombre': 'Ingeniero Jefe de Obra',
            'nombre': 'Ing. Braulio Hormigón',
            'telefono': '',
            'updated_at': reloj.ahora().toIso8601String(),
          },
        },
      );
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        authRemota: authRemota,
        reloj: reloj,
        busDeEventos: bus,
      );
      final motor = MotorSincronizacion(
        baseDatosLocal: db,
        fuenteRemota: remoto,
        reloj: reloj,
        busDeEventos: bus,
      );
      final obrasRepo = ObrasRepository(
        baseDatosService: db,
        reloj: reloj,
        motorSincronizacion: motor,
        busDeEventos: bus,
      );
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        reloj: reloj,
      );
      final vm = ObrasViewModel(
        obrasRepository: obrasRepo,
        autenticacionRepository: authRepo,
        notificacionesRepository: notifRepo,
        sincronizacionService: SincronizacionService(),
        multimediaService: MultimediaService(reloj: reloj),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const Politicas(),
        busDeEventos: bus,
        reloj: reloj,
      );

      await authRepo.iniciarSesion(
        identificador: 'ing1',
        contrasenia: 'Password123!',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final ids = vm.responsablesDisponibles.map((u) => u.id).toList();
      expect(ids, ['cap_1', 'ing_1']);
      expect(ids, isNot(contains('ing_2')));
      expect(ids, isNot(contains('dueno_1')));

      vm.dispose();
      await remoto.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  test(
    'Catálogo individual por ingeniero, obra sin materiales iniciales, alta de material en curso y tarea actual elegible',
    () async {
      final reloj = RelojFijo(DateTime.utc(2026, 11, 22, 17, 15));
      final db = BaseDatosLocalService(reloj: reloj);
      final bus = BusDeEventos();
      final remoto = FakeFuenteDatosRemota();
      final motor = MotorSincronizacion(
        baseDatosLocal: db,
        fuenteRemota: remoto,
        reloj: reloj,
        busDeEventos: bus,
      );
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        reloj: reloj,
      );
      final obrasRepo = ObrasRepository(
        baseDatosService: db,
        reloj: reloj,
        motorSincronizacion: motor,
        busDeEventos: bus,
        generadorIds: GeneradorIdsSecuencial(prefijo: 'cat'),
      );
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        reloj: reloj,
      );
      final vm = ObrasViewModel(
        obrasRepository: obrasRepo,
        autenticacionRepository: authRepo,
        notificacionesRepository: notifRepo,
        sincronizacionService: SincronizacionService(),
        multimediaService: MultimediaService(reloj: reloj),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const Politicas(),
        busDeEventos: bus,
        reloj: reloj,
        generadorIds: GeneradorIdsSecuencial(prefijo: 'vm_cat'),
      );

      await authRepo.iniciarSesion(
        identificador: 'ingeniero',
        contrasenia: '1234',
      );
      await vm.cargar(forzarRecarga: true);

      // 1. Catálogo personal del ingeniero: guardar, sincronizar y eliminar
      await vm.guardarPlantillaPersonal(
        tipo: TipoPlantilla.tarea,
        nombre: 'Impermeabilización de terraza',
      );
      await vm.guardarPlantillaPersonal(
        tipo: TipoPlantilla.material,
        nombre: 'Membrana asfáltica 4mm',
      );
      expect(
        vm.tareasGuardadas
            .any((p) => p.nombre == 'Impermeabilización de terraza'),
        isTrue,
      );
      expect(
        vm.materialesGuardados.any((p) => p.nombre == 'Membrana asfáltica 4mm'),
        isTrue,
      );

      // Verificar aislamiento individual: el capataz no ve las plantillas del ingeniero
      final plantillasCapataz =
          await obrasRepo.obtenerPlantillasUsuario('u_capataz');
      expect(plantillasCapataz, isEmpty);

      final syncPlantillas = await obrasRepo.sincronizarTodo(
        permitirSimulacionLocal: false,
      );
      expect(syncPlantillas.tuvoErrores, isFalse);
      expect(remoto.plantillasRemotas.length, greaterThanOrEqualTo(2));

      final creadaPlantilla = vm.materialesGuardados.firstWhere(
        (p) => p.nombre == 'Membrana asfáltica 4mm',
      );
      await vm.eliminarPlantillaPersonal(creadaPlantilla.id);
      expect(
        vm.materialesGuardados.any((p) => p.id == creadaPlantilla.id),
        isFalse,
      );

      // 2. Obra creada sin materiales iniciales + añadir material en curso
      final capataz = vm.responsablesDisponibles.firstWhere(
        (u) => u.id == 'u_capataz',
      );
      await vm.crearNuevaObra(
        nombre: 'Obra Sin Materiales',
        responsable: capataz,
        nombresTareas: const ['Tarea A', 'Tarea B', 'Tarea C'],
        materiales: const [],
        ubicacion: const UbicacionObra(
          latitud: -32.89,
          longitud: -68.84,
          direccion: 'Mendoza',
        ),
        estadoInicial: EstadoObra.aTiempo,
        observaciones: '',
      );

      var obra = vm.obrasFiltradas.firstWhere(
        (o) => o.nombre == 'Obra Sin Materiales',
      );
      expect(obra.materiales, isEmpty);
      expect(obra.tareaActual, 'Tarea A');

      await vm.agregarMaterialAObra(obra.id, 'Cal hidráulica');
      obra = vm.obtenerObraPorId(obra.id)!;
      expect(obra.materiales, ['Cal hidráulica']);

      // 3. Elegir tarea actual explícita y verificar auto-limpieza al completarla
      final tareaC = obra.tareas.firstWhere((t) => t.nombre == 'Tarea C');
      expect(vm.puedeElegirTareaActual(obra), isTrue);
      await vm.cambiarTareaActual(obra.id, tareaC.id);
      obra = vm.obtenerObraPorId(obra.id)!;
      expect(obra.tareaActualId, tareaC.id);
      expect(obra.tareaActual, 'Tarea C');

      // Al completar la tarea elegida, vuelve automáticamente a la primera pendiente
      await vm.alternarTareaCompletada(obra.id, tareaC.id);
      obra = vm.obtenerObraPorId(obra.id)!;
      expect(obra.tareaActualId, isNull);
      expect(obra.tareaActual, 'Tarea A');

      // 4. Política de autorización estricta para elegir tarea actual
      const politicas = Politicas();
      const otroIngeniero = Usuario(
        id: 'u_ing_2',
        username: 'ing2',
        nombre: 'Ing. Otra',
        contrasenia: '',
        rol: Rol.ingeniero,
      );
      const otroCapataz = Usuario(
        id: 'u_cap_2',
        username: 'cap2',
        nombre: 'Capataz Otro',
        contrasenia: '',
        rol: Rol.capataz,
      );
      const duenio = Usuario(
        id: 'u_duenio',
        username: 'duenio',
        nombre: 'Dueño',
        contrasenia: '',
        rol: Rol.duenio,
      );
      expect(politicas.puedeElegirTareaActual(capataz, obra), isTrue);
      expect(politicas.puedeElegirTareaActual(vm.usuarioActual, obra), isTrue);
      expect(politicas.puedeElegirTareaActual(otroIngeniero, obra), isFalse);
      expect(politicas.puedeElegirTareaActual(otroCapataz, obra), isFalse);
      expect(politicas.puedeElegirTareaActual(duenio, obra), isFalse);

      vm.dispose();
      await remoto.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  test(
    'Recordatorio diario por ingeniero: aislamiento entre ingenieros, horario más temprano en Capataz, SharedPreferences y Push/Pull',
    () async {
      final reloj = RelojFijo(DateTime.utc(2026, 11, 22, 19, 0));
      final db = BaseDatosLocalService(reloj: reloj);
      final prefs = PreferenciasRepository();
      final bus = BusDeEventos();
      final remoto = FakeFuenteDatosRemota();
      final motor = MotorSincronizacion(
        baseDatosLocal: db,
        fuenteRemota: remoto,
        reloj: reloj,
        busDeEventos: bus,
      );
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        preferenciasRepository: prefs,
        fuenteRemota: remoto,
        reloj: reloj,
        busDeEventos: bus,
      );
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        reloj: reloj,
        autenticacionRepository: authRepo,
        preferenciasRepository: prefs,
        motorSincronizacion: motor,
        busDeEventos: bus,
      );

      // Agregamos un segundo ingeniero para verificar aislamiento y horario más temprano
      await db.guardarUsuarioCrudo({
        'id': 'u_ing_2',
        'username': 'ingeniero2',
        'rol_id': 'rol_ingeniero',
        'nombre': 'Ing. Sofía Acero',
        'contrasenia': '1234',
        'telefono': '+54 9 261 555-0190',
        'updated_at': reloj.ahora().toIso8601String(),
        'sync_status': 'synced',
      });

      // Ing. 1 configura 18:30 y hace Push a remoto
      final cfgIng1 = await notifRepo.actualizarProgramacionRecordatorio(
        ingenieroId: 'u_ingeniero',
        activo: true,
        hora: 18,
        minuto: 30,
      );
      expect(cfgIng1.horarioFormateado, '18:30');
      expect(prefs.recordatorioLocal.activo, isTrue);
      expect(prefs.recordatorioLocal.hora, 18);
      expect(prefs.recordatorioLocal.minuto, 30);
      expect(
        notifFalsas.ultimaBaseDatosRecordatorio,
        BaseDatosLocalService.nombreArchivoDb,
      );

      // actualizarProgramacionRecordatorio ya disparó Push automático en segundo plano
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        remoto.configuracionesRecordatorioRemotas['u_ingeniero']?['hora'],
        18,
      );
      expect(
        remoto.configuracionesRecordatorioRemotas['u_ingeniero']?['minuto'],
        30,
      );

      // Pull descarga la configuración de Ing. 2 a las 17:15 sin pisar a Ing. 1
      remoto.cambiosParaPull = CambiosRemotos(
        configuracionesRecordatorio: [
          {
            'ingeniero_id': 'u_ing_2',
            'activo': 1,
            'hora': 17,
            'minuto': 15,
            'updated_at': reloj.ahora().toIso8601String(),
            'sync_status': 'synced',
          },
        ],
      );
      await motor.sincronizarTodo(permitirSimulacionLocal: false);

      final recIng1 = await notifRepo.obtenerProgramacionRecordatorio(
        ingenieroId: 'u_ingeniero',
      );
      final recIng2 = await notifRepo.obtenerProgramacionRecordatorio(
        ingenieroId: 'u_ing_2',
      );
      expect(recIng1.horarioFormateado, '18:30');
      expect(recIng2.horarioFormateado, '17:15');

      // Capataz con obras de ambos ingenieros -> debe elegir el horario más temprano (17:15)
      final usuarios = await authRepo.obtenerUsuarios(forzarRecarga: true);
      final capataz = usuarios.firstWhere((u) => u.id == 'u_capataz');
      final duenio = usuarios.firstWhere((u) => u.id == 'u_duenio');

      final obraDeIng1 = Obra(
        id: 'o_ing1',
        nombre: 'Obra Ing 1',
        estado: EstadoObra.aTiempo,
        fechaUltimoReporte: reloj.ahora(),
        responsableId: 'u_capataz',
        responsableNombre: capataz.nombre,
        ingenieroId: 'u_ingeniero',
        tareas: const [],
        materiales: const [],
        ubicacion: const UbicacionObra(
          latitud: -32.88,
          longitud: -68.84,
          direccion: 'Mendoza',
        ),
      );
      final obraDeIng2 = obraDeIng1.copyWith(
        nombre: 'Obra Ing 2',
        ingenieroId: 'u_ing_2',
      );

      final efectivoCapataz =
          await notifRepo.sincronizarRecordatorioLocalParaUsuario(
        usuario: capataz,
        obras: [obraDeIng1, obraDeIng2],
      );
      expect(efectivoCapataz?.horarioFormateado, '17:15');
      expect(notifFalsas.recordatoriosProgramados.last, (17, 15));
      expect(prefs.recordatorioLocal.activo, isTrue);
      expect(prefs.recordatorioLocal.hora, 17);
      expect(prefs.recordatorioLocal.minuto, 15);

      // Si el Dueño sincroniza, cancela la alarma local
      notifFalsas.recordatorioCancelado = false;
      final efectivoDuenio =
          await notifRepo.sincronizarRecordatorioLocalParaUsuario(
        usuario: duenio,
        obras: [obraDeIng1, obraDeIng2],
      );
      expect(efectivoDuenio, isNull);
      expect(notifFalsas.recordatorioCancelado, isTrue);
      expect(prefs.recordatorioLocal.activo, isFalse);

      await remoto.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  test(
    'AutenticacionRepository registra, rota y limpia fcm_token en login, refresh y logout',
    () async {
      final db = BaseDatosLocalService();
      final prefs = PreferenciasRepository();
      final remoto = FakeFuenteDatosRemota();
      final pushFake = FakeServicioPushFcm(tokenActual: 'fcm_token_inicial');
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        preferenciasRepository: prefs,
        fuenteRemota: remoto,
        servicioPushFcm: pushFake,
      );

      final user = await authRepo.iniciarSesion(
        identificador: 'capataz',
        contrasenia: '1234',
      );
      expect(user, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(remoto.fcmTokensRemotos['u_capataz'], 'fcm_token_inicial');

      pushFake.simularRotacionToken('fcm_token_rotado');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(remoto.fcmTokensRemotos['u_capataz'], 'fcm_token_rotado');

      await authRepo.cerrarSesion();
      expect(remoto.fcmTokensRemotos['u_capataz'], isNull);
      expect(pushFake.tokenEliminado, isTrue);

      await authRepo.dispose();
      await pushFake.dispose();
      await remoto.dispose();
    },
  );

  test(
    'Conflicto offline LWW: informe más viejo del Capataz no pisa el estado más reciente del Ingeniero y conserva ambos informes y tareas',
    () async {
      // Mapeadores envían client_updated_at para LWW en servidor PostgreSQL
      final obraPayload = mapearObraLocalARemoto({
        'id': 'o_lww',
        'nombre': 'Obra LWW',
        'estado_semaforo': 'demorada',
        'fecha_ultimo_reporte': '2026-11-23T10:00:00.000Z',
        'responsable_id': 'u_capataz',
        'ingeniero_id': 'u_ingeniero',
        'ubicacion_latitud': -32.88,
        'ubicacion_longitud': -68.84,
        'ubicacion_direccion': 'Mendoza',
        'observaciones': 'Falta cemento',
        'con_foto': 1,
        'finalizada': 0,
        'updated_at': '2026-11-23T10:00:00.000Z',
      });
      expect(obraPayload['client_updated_at'], '2026-11-23T10:00:00.000Z');

      final tareaPayload = mapearTareaLocalARemoto({
        'id': 't_a',
        'obra_id': 'o_lww',
        'nombre': 'Tarea A',
        'completada': 1,
        'orden': 0,
        'updated_at': '2026-11-23T10:00:00.000Z',
      });
      expect(tareaPayload['client_updated_at'], '2026-11-23T10:00:00.000Z');

      // Servidor remoto compartido con resolución LWW (espejo del trigger SQL)
      final remoto = FakeFuenteDatosRemota(resolverConflictosLww: true);
      final relojCapataz = RelojFijo(DateTime.utc(2026, 11, 23, 10, 0));
      final relojSyncCapataz = RelojFijo(DateTime.utc(2026, 11, 23, 10, 30));
      final relojIngeniero = RelojFijo(DateTime.utc(2026, 11, 23, 10, 15));

      final dbCapataz = BaseDatosLocalService(reloj: relojCapataz);
      final dbIngeniero = BaseDatosLocalService(reloj: relojIngeniero);
      final motorCapataz = MotorSincronizacion(
        baseDatosLocal: dbCapataz,
        fuenteRemota: remoto,
        reloj: relojSyncCapataz,
      );
      final motorIngeniero = MotorSincronizacion(
        baseDatosLocal: dbIngeniero,
        fuenteRemota: remoto,
        reloj: relojIngeniero,
      );
      final repoCapataz = ObrasRepository(
        baseDatosService: dbCapataz,
        motorSincronizacion: motorCapataz,
        reloj: relojCapataz,
      );
      final repoIngeniero = ObrasRepository(
        baseDatosService: dbIngeniero,
        motorSincronizacion: motorIngeniero,
        reloj: relojIngeniero,
      );

      final obraBase = (await repoCapataz.obtenerObras()).first;
      final tareaA = obraBase.tareas[0];
      final tareaB = obraBase.tareas[1];

      // 10:00 UTC: Capataz SIN internet guarda informe (completa Tarea A, Amarillo, con foto)
      await repoCapataz.registrarReporteDiario(
        ReporteDiario(
          id: 'rep_capataz_1000',
          obraId: obraBase.id,
          obraNombre: obraBase.nombre,
          autorId: 'u_capataz',
          autorNombre: 'Carlos Méndez',
          fechaCreacionLocal: relojCapataz.ahora(),
          tareaSeleccionada: tareaA.nombre,
          tareaCompletadaEnInforme: true,
          materialesUsados: const ['Cemento Portland'],
          observaciones: 'Falta cemento (10:00)',
          urlFotos: const [
            FotoComprimida(
              rutaLocal: 'assets/obra.jpg',
              origen: 'Cámara en obra',
              anchoPx: 800,
              altoPx: 600,
              calidadPct: 70,
              pesoKb: 120,
            ),
          ],
          estadoSemaforo: EstadoObra.demorada,
          syncStatus: EstadoSincronizacion.pending,
          updatedAt: relojCapataz.ahora(),
        ),
      );

      // 10:15 UTC: Ingeniero CON internet guarda informe sobre la misma obra
      // (completa Tarea B, Rojo, sin foto) y sincroniza inmediatamente.
      await repoIngeniero.registrarReporteDiario(
        ReporteDiario(
          id: 'rep_ingeniero_1015',
          obraId: obraBase.id,
          obraNombre: obraBase.nombre,
          autorId: 'u_ingeniero',
          autorNombre: 'Ing. Braulio Hormigón',
          fechaCreacionLocal: relojIngeniero.ahora(),
          tareaSeleccionada: tareaB.nombre,
          tareaCompletadaEnInforme: true,
          materialesUsados: const ['Arena gruesa'],
          observaciones: 'Falla en losa (10:15)',
          urlFotos: const [],
          estadoSemaforo: EstadoObra.problemas,
          syncStatus: EstadoSincronizacion.pending,
          updatedAt: relojIngeniero.ahora(),
        ),
      );
      await motorIngeniero.sincronizarTodo(permitirSimulacionLocal: false);

      // 10:30 UTC: Al Capataz le vuelve internet y sincroniza (Push -> Pull)
      final resCapataz =
          await motorCapataz.sincronizarTodo(permitirSimulacionLocal: false);
      expect(resCapataz.tuvoErrores, isFalse);

      // Ambos informes sobreviven sin perderse
      final reportesFinales =
          await repoCapataz.obtenerReportes(forzarRecarga: true);
      expect(
        reportesFinales.map((r) => r.id),
        containsAll(['rep_capataz_1000', 'rep_ingeniero_1015']),
      );

      // En la cabecera de la obra ganó el estado más reciente (Ingeniero 10:15: Rojo),
      // pero se preservó conFoto=true del informe offline y ambas tareas completas.
      final obraFinal = (await repoCapataz.obtenerObras(forzarRecarga: true))
          .firstWhere((o) => o.id == obraBase.id);
      expect(obraFinal.estado, EstadoObra.problemas);
      expect(obraFinal.observaciones, 'Falla en losa (10:15)');
      expect(obraFinal.conFoto, isTrue);
      expect(
        obraFinal.tareas.firstWhere((t) => t.id == tareaA.id).completada,
        isTrue,
      );
      expect(
        obraFinal.tareas.firstWhere((t) => t.id == tareaB.id).completada,
        isTrue,
      );

      await remoto.dispose();
    },
  );

  test(
    'formato_fecha formatea fechas 24hs, tiempos relativos y normaliza búsquedas sin tildes',
    () {
      final ahora = DateTime(2026, 11, 23, 18, 0);
      expect(
        formatearFechaHoraCorta(DateTime(2026, 11, 23, 9, 5)),
        '23/11/2026 09:05 hs',
      );
      expect(
        formatearTiempoRelativo(DateTime(2026, 11, 23, 14, 30), ahora: ahora),
        'Hoy 14:30',
      );
      expect(
        formatearTiempoRelativo(DateTime(2026, 11, 22, 16, 15), ahora: ahora),
        'Ayer 16:15',
      );
      expect(
        formatearTiempoRelativo(DateTime(2026, 11, 20, 10, 0), ahora: ahora),
        'Hace 3 días',
      );
      expect(
        formatearTiempoRelativo(DateTime(2026, 11, 1, 10, 0), ahora: ahora),
        '01/11/2026',
      );
      expect(normalizarTextoBusqueda('  Hormigón Ñandú Árbol  '),
          'hormigon nandu arbol');
    },
  );

  test(
    'ObrasViewModel soporta búsqueda ampliada sin tildes, ordenamiento y bloqueo solo lectura en finalizadas con reapertura',
    () async {
      final bus = BusDeEventos();
      final reloj = RelojFijo(DateTime.utc(2026, 11, 23, 12, 0));
      final db = BaseDatosLocalService(reloj: reloj);
      final authRepo = AutenticacionRepository(
        baseDatosService: db,
        busDeEventos: bus,
      );
      final obrasRepo = ObrasRepository(
        baseDatosService: db,
        reloj: reloj,
        busDeEventos: bus,
      );
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        autenticacionRepository: authRepo,
        busDeEventos: bus,
      );
      final vm = ObrasViewModel(
        obrasRepository: obrasRepo,
        autenticacionRepository: authRepo,
        notificacionesRepository: notifRepo,
        sincronizacionService: SincronizacionService(),
        multimediaService: MultimediaService(),
        vozATextoService: VozATextoService(),
        mapaService: MapaService(),
        politicas: const PoliticasFalsas(),
        busDeEventos: bus,
        reloj: reloj,
      );

      await authRepo.iniciarSesion(
        identificador: 'ingeniero',
        contrasenia: '1234',
      );
      await vm.cargar(forzarRecarga: true);

      // Orden por urgencia: Rojo (problemas) primero
      vm.cambiarOrdenObras(OrdenObras.urgenciaSemaforo);
      expect(vm.obrasFiltradas.first.estado, EstadoObra.problemas);

      // Orden alfabético A-Z
      vm.cambiarOrdenObras(OrdenObras.nombreAZ);
      final nombres =
          vm.obrasFiltradas.map((o) => o.nombre.toLowerCase()).toList();
      final ordenados = List<String>.from(nombres)..sort();
      expect(nombres, ordenados);

      // Búsqueda ampliada sin tildes por ubicación / responsable
      vm.actualizarBusqueda('lujan');
      expect(vm.obrasFiltradas, isNotEmpty);
      expect(vm.tieneFiltrosActivos, isTrue);

      vm.limpiarFiltrosYBusqueda();
      expect(vm.tieneFiltrosActivos, isFalse);

      // Finalizar obra -> pasa a modo solo lectura (bloquea semáforo, tareas e informes)
      final objetivo = vm.obrasFiltradas.first;
      final tareasAntes = objetivo.tareas.length;
      final reportesAntes = vm.reportes.length;
      final okFin =
          await vm.cambiarObraFinalizada(objetivo.id, finalizada: true);
      expect(okFin, isTrue);
      expect(vm.obtenerObraPorId(objetivo.id)!.finalizada, isTrue);

      final estadoFinalizado = vm.obtenerObraPorId(objetivo.id)!.estado;
      final nuevoEstadoIntentado = estadoFinalizado == EstadoObra.problemas
          ? EstadoObra.aTiempo
          : EstadoObra.problemas;
      await vm.cambiarEstadoSemaforo(objetivo.id, nuevoEstadoIntentado);
      expect(vm.obtenerObraPorId(objetivo.id)!.estado, estadoFinalizado);

      await vm.agregarTareaAObra(objetivo.id, 'Tarea bloqueada');
      expect(vm.obtenerObraPorId(objetivo.id)!.tareas.length, tareasAntes);

      await vm.guardarInformeDiario(
        obra: vm.obtenerObraPorId(objetivo.id)!,
        tareaSeleccionada: objetivo.tareaActual,
        marcarTareaComoCompletada: true,
        materialesGastados: const [],
        observaciones: 'No debería guardarse',
        estadoSemaforo: EstadoObra.aTiempo,
        fotosAdjuntas: const [],
      );
      expect(vm.reportes.length, reportesAntes);
      expect(vm.mensajeError, isNotNull);

      // Reabrir obra -> vuelve a estar activa y editable
      final okReabrir =
          await vm.cambiarObraFinalizada(objetivo.id, finalizada: false);
      expect(okReabrir, isTrue);
      expect(vm.obtenerObraPorId(objetivo.id)!.finalizada, isFalse);

      await vm.cambiarEstadoSemaforo(objetivo.id, nuevoEstadoIntentado);
      expect(vm.obtenerObraPorId(objetivo.id)!.estado, nuevoEstadoIntentado);

      vm.dispose();
      await notifFalsas.dispose();
      await bus.dispose();
    },
  );
}
