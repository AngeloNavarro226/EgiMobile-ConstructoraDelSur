import 'dart:async';
import 'dart:typed_data';

import 'package:constructora_del_sur/data/services/base_datos_local_service.dart';
import 'package:constructora_del_sur/data/services/fuente_datos_remota.dart';
import 'package:constructora_del_sur/data/services/generador_ids.dart';
import 'package:constructora_del_sur/data/services/notificaciones_sistema_service.dart';
import 'package:constructora_del_sur/data/services/reloj.dart';
import 'package:constructora_del_sur/domain/models/aviso.dart';
import 'package:constructora_del_sur/plataforma/capacidades.dart';
import 'package:constructora_del_sur/plataforma/politicas.dart';

/// Reloj determinístico para pruebas unitarias.
class RelojFijo implements Reloj {
  RelojFijo(this.instante);

  final DateTime instante;

  @override
  DateTime ahora() => instante;
}

/// Generador determinístico de identificadores para pruebas unitarias.
class GeneradorIdsSecuencial implements GeneradorIds {
  GeneradorIdsSecuencial({this.prefijo = 'id_test'});

  final String prefijo;
  int _contador = 0;

  @override
  String generar() {
    _contador++;
    return '${prefijo}_$_contador';
  }
}

/// Implementación Fake de [FuenteDatosRemota] para probar Push -> Pull,
/// subida de fotos a Storage, caídas de red y resolución de conflictos sin
/// conexión real a Supabase.
class FakeFuenteDatosRemota implements FuenteDatosRemota {
  FakeFuenteDatosRemota({
    this.estaDisponible = true,
    this.simularErrorRed = false,
    this.cambiosParaPull = const CambiosRemotos(),
  });

  @override
  bool estaDisponible;

  bool simularErrorRed;
  CambiosRemotos cambiosParaPull;

  final List<String> fotosSubidas = [];
  final Map<String, Map<String, dynamic>> usuariosRemotos = {};
  final Map<String, Map<String, dynamic>> obrasRemotas = {};
  final Map<String, Map<String, dynamic>> tareasRemotas = {};
  final Map<String, Map<String, dynamic>> reportesRemotos = {};
  final Map<String, Map<String, dynamic>> notificacionesRemotas = {};

  void _verificarRed() {
    if (simularErrorRed) {
      throw StateError('Sin conexión con el servidor remoto (simulado)');
    }
  }

  @override
  Future<String> subirFoto({
    required String rutaLocal,
    required String destinoStorage,
    Uint8List? bytes,
  }) async {
    _verificarRed();
    fotosSubidas.add(destinoStorage);
    return 'https://storage.fake.local/$destinoStorage';
  }

  @override
  Future<void> upsertUsuario(Map<String, dynamic> usuario) async {
    _verificarRed();
    usuariosRemotos[usuario['id'] as String] = Map<String, dynamic>.from(
      usuario,
    );
  }

  @override
  Future<void> upsertObra({
    required Map<String, dynamic> obra,
    required List<String> materiales,
  }) async {
    _verificarRed();
    obrasRemotas[obra['id'] as String] = {
      ...obra,
      'materiales': List<String>.from(materiales),
    };
  }

  @override
  Future<void> upsertTarea(Map<String, dynamic> tarea) async {
    _verificarRed();
    tareasRemotas[tarea['id'] as String] = Map<String, dynamic>.from(tarea);
  }

  @override
  Future<void> upsertReporte({
    required Map<String, dynamic> reporte,
    required List<String> materiales,
    required List<Map<String, dynamic>> fotos,
  }) async {
    _verificarRed();
    reportesRemotos[reporte['id'] as String] = {
      ...reporte,
      'materiales': List<String>.from(materiales),
      'fotos': fotos.map(Map<String, dynamic>.from).toList(),
    };
  }

  @override
  Future<void> upsertNotificacion(Map<String, dynamic> notificacion) async {
    _verificarRed();
    notificacionesRemotas[notificacion['id'] as String] =
        Map<String, dynamic>.from(notificacion);
  }

  @override
  Future<CambiosRemotos> obtenerCambiosDesde(DateTime? ultimaSyncUtc) async {
    _verificarRed();
    return cambiosParaPull;
  }
}

/// Subclase Fake de [BaseDatosLocalService] que fuerza errores controlados
/// para verificar transiciones de estado y `notifyListeners()` ante fallos.
class BaseDatosLocalConError extends BaseDatosLocalService {
  BaseDatosLocalConError({this.mensaje = 'Error simulado de SQLite'});

  final String mensaje;

  @override
  Future<List<Map<String, dynamic>>> obtenerUsuariosCrudos() async =>
      throw StateError(mensaje);

  @override
  Future<List<Map<String, dynamic>>> obtenerObrasCrudas({
    int? limite,
    int? desplazamiento,
    String? responsableId,
  }) async =>
      throw StateError(mensaje);

  @override
  Future<List<Map<String, dynamic>>> obtenerReportesCrudos({
    String? obraId,
    int? limite,
    int? desplazamiento,
  }) async =>
      throw StateError(mensaje);

  @override
  Future<List<Map<String, dynamic>>> obtenerNotificacionesCrudas() async =>
      throw StateError(mensaje);
}

/// Implementación Fake de [ServicioDeNotificaciones] para pruebas sin canales
/// nativos.
class NotificacionesFalsas implements ServicioDeNotificaciones {
  final List<Aviso> mostradas = [];
  final List<int> canceladas = [];
  final StreamController<String> _toques = StreamController<String>.broadcast();
  final List<(int, int)> recordatoriosProgramados = [];
  bool recordatorioCancelado = false;
  bool permisoConcedido = true;

  @override
  Future<bool> pedirPermiso() async => permisoConcedido;

  @override
  Future<void> mostrar(Aviso aviso) async {
    mostradas.add(aviso);
  }

  @override
  Future<void> cancelar(int id) async {
    canceladas.add(id);
  }

  @override
  Future<void> programarRecordatorioDiario({
    required int hora,
    required int minuto,
    required String titulo,
    required String mensaje,
  }) async {
    recordatoriosProgramados.add((hora, minuto));
  }

  @override
  Future<void> cancelarRecordatorioDiario() async {
    recordatorioCancelado = true;
  }

  @override
  Stream<String> get toques => _toques.stream;

  void simularToque(String destino) => _toques.add(destino);

  Future<void> dispose() async {
    await _toques.close();
  }
}

/// Cumple el mismo contrato que [Capacidades], pero cada respuesta la decide
/// la prueba sin depender del hardware real del dispositivo.
class CapacidadesFalsas implements Capacidades {
  const CapacidadesFalsas({
    this.tieneCamara = true,
    this.tieneMicrofono = true,
    this.tieneGps = true,
    this.requiereDialogoDePermiso = false,
    this.soportaTrabajoEnSegundoPlano = true,
  });

  @override
  final bool tieneCamara;

  @override
  final bool tieneMicrofono;

  @override
  final bool tieneGps;

  @override
  final bool requiereDialogoDePermiso;

  @override
  final bool soportaTrabajoEnSegundoPlano;
}

/// Cumple el mismo contrato que [Politicas] para pruebas unitarias y de widgets.
class PoliticasFalsas extends Politicas {
  const PoliticasFalsas({
    this.pesoMaximoFotoKb = 200,
    this.resolucionAnchoFoto = 800,
    this.resolucionAltoFoto = 600,
    this.calidadCompresionFoto = 70,
    this.nombreDeLaTienda = 'la tienda de prueba',
    this.permiteEnlacesExternosEnNavegador = true,
  });

  @override
  final int pesoMaximoFotoKb;

  @override
  final int resolucionAnchoFoto;

  @override
  final int resolucionAltoFoto;

  @override
  final int calidadCompresionFoto;

  @override
  final String nombreDeLaTienda;

  @override
  final bool permiteEnlacesExternosEnNavegador;
}
