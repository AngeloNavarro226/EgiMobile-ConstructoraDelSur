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
import 'package:constructora_del_sur/domain/models/horarios.dart';
import 'package:constructora_del_sur/domain/models/obra.dart';
import 'package:constructora_del_sur/domain/models/reporte_diario.dart';
import 'package:constructora_del_sur/domain/models/rol.dart';
import 'package:constructora_del_sur/domain/models/tarea_obra.dart';
import 'package:constructora_del_sur/domain/models/ubicacion_obra.dart';
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
    'NotificacionesRepository usa PoliticaDeAvisos, destinatarios dinámicos y NotificacionesFalsas',
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

      final obraVerde = Obra(
        id: '10',
        nombre: 'Obra Verde',
        estado: EstadoObra.aTiempo,
        fechaUltimoReporte: DateTime.utc(2026, 10, 15),
        responsableId: 'u_capataz',
        responsableNombre: 'Capataz',
        tareas: const [],
        materiales: const [],
        ubicacion: const UbicacionObra(
          latitud: -32.88,
          longitud: -68.84,
          direccion: 'Mendoza',
        ),
      );
      await repo.emitirAlertaCambioSemaforo(
        obra: obraVerde,
        motivo: 'En término',
      );
      expect(notifFalsas.mostradas, isEmpty);

      final obraRoja = obraVerde.copyWith(estado: EstadoObra.problemas);
      final alerta = await repo.emitirAlertaCambioSemaforo(
        obra: obraRoja,
        motivo: 'Falta de insumos',
      );
      expect(notifFalsas.mostradas.length, 1);
      expect(notifFalsas.mostradas.first.alTocar, 'obra:10');
      expect(alerta?.destinatario, contains('Ing. Braulio Hormigón'));
      expect(alerta?.destinatario, contains('Roberto Del Sur'));

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
}
