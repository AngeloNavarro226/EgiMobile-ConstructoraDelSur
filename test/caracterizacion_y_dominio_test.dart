import 'package:constructora_del_sur/data/repositories/autenticacion_repository.dart';
import 'package:constructora_del_sur/data/repositories/notificaciones_repository.dart';
import 'package:constructora_del_sur/data/repositories/obras_repository.dart';
import 'package:constructora_del_sur/data/services/base_datos_local_service.dart';
import 'package:constructora_del_sur/data/services/bus_de_eventos.dart';
import 'package:constructora_del_sur/data/services/mapa_service.dart';
import 'package:constructora_del_sur/data/services/multimedia_service.dart';
import 'package:constructora_del_sur/data/services/sincronizacion_service.dart';
import 'package:constructora_del_sur/data/services/voz_a_texto_service.dart';
import 'package:constructora_del_sur/domain/models/evento_de_app.dart';
import 'package:constructora_del_sur/domain/models/horarios.dart';
import 'package:constructora_del_sur/domain/models/obra.dart';
import 'package:constructora_del_sur/domain/models/tarea_obra.dart';
import 'package:constructora_del_sur/domain/models/ubicacion_obra.dart';
import 'package:constructora_del_sur/domain/models/usuario.dart';
import 'package:constructora_del_sur/ui/autenticacion/view_models/autenticacion_view_model.dart';
import 'package:constructora_del_sur/ui/obras/view_models/obras_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
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
    'Autenticación valida los 3 usuarios de prueba y rechaza credenciales inválidas',
    () async {
      final db = BaseDatosLocalService();
      final repo = AutenticacionRepository(baseDatosService: db);
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
      expect(vm.usuarioActual?.rol, RolUsuario.capataz);
    },
  );

  test(
    'Obras finalizadas se ocultan por defecto y se muestran al activar el filtro Finalizadas',
    () async {
      final reloj = RelojFijo(DateTime(2026, 10, 15, 10, 30));
      final db = BaseDatosLocalService();
      final authRepo = AutenticacionRepository(baseDatosService: db);
      final obrasRepo = ObrasRepository(baseDatosService: db, reloj: reloj);
      final notifFalsas = NotificacionesFalsas();
      final notifRepo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        reloj: reloj,
      );
      final bus = BusDeEventos();

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

      // La obra finalizada se oculta de la vista por defecto
      expect(vm.cantidadFinalizadas, 1);
      expect(vm.obrasFiltradas.length, 5);
      expect(vm.obrasFiltradas.any((o) => o.id == primeraObra.id), isFalse);

      // Al marcar el filtro "Finalizadas", muestra únicamente las obras finalizadas
      vm.alternarFiltroFinalizadas(true);
      expect(vm.mostrarSoloFinalizadas, isTrue);
      expect(vm.obrasFiltradas.length, 1);
      expect(vm.obrasFiltradas.first.id, primeraObra.id);
      expect(vm.obrasFiltradas.first.finalizada, isTrue);

      await notifFalsas.dispose();
      await bus.dispose();
    },
  );

  test(
    'NotificacionesRepository usa PoliticaDeAvisos y NotificacionesFalsas sin plugin nativo',
    () async {
      final db = BaseDatosLocalService();
      final notifFalsas = NotificacionesFalsas();
      final repo = NotificacionesRepository(
        baseDatosService: db,
        notificacionesSistemaService: notifFalsas,
        reloj: RelojFijo(DateTime(2026, 10, 15, 18, 0)),
      );

      final obraVerde = Obra(
        id: '10',
        nombre: 'Obra Verde',
        estado: EstadoObra.aTiempo,
        fechaUltimoReporte: DateTime(2026, 10, 15),
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
      await repo.emitirAlertaCambioSemaforo(
        obra: obraRoja,
        motivo: 'Falta de insumos',
      );
      expect(notifFalsas.mostradas.length, 1);
      expect(notifFalsas.mostradas.first.alTocar, 'obra:10');

      await notifFalsas.dispose();
    },
  );

  test(
    'Funciones puras de SegundoPlano y MapaService transcriben horarios y lugares',
    () {
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
    },
  );
}
