import 'dart:async';
import 'dart:typed_data';

import 'package:constructora_del_sur/data/services/base_datos_local_service.dart';
import 'package:constructora_del_sur/data/services/firebase_notificaciones_service.dart';
import 'package:constructora_del_sur/data/services/fuente_datos_remota.dart';
import 'package:constructora_del_sur/data/services/generador_ids.dart';
import 'package:constructora_del_sur/data/services/notificaciones_sistema_service.dart';
import 'package:constructora_del_sur/data/services/reloj.dart';
import 'package:constructora_del_sur/data/services/servicio_autenticacion_remota.dart';
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
    this.resolverConflictosLww = false,
  });

  @override
  bool estaDisponible;

  bool simularErrorRed;
  CambiosRemotos cambiosParaPull;
  bool resolverConflictosLww;

  final List<String> fotosSubidas = [];
  final Map<String, Map<String, dynamic>> usuariosRemotos = {};
  final Map<String, Map<String, dynamic>> obrasRemotas = {};
  final Map<String, Map<String, dynamic>> tareasRemotas = {};
  final Map<String, Map<String, dynamic>> reportesRemotos = {};
  final Map<String, Map<String, dynamic>> notificacionesRemotas = {};
  final Map<String, Map<String, dynamic>> plantillasRemotas = {};
  final Map<String, Map<String, dynamic>> configuracionesRecordatorioRemotas =
      {};
  final Map<String, String?> fcmTokensRemotos = {};
  final StreamController<String> _cambiosRealtime =
      StreamController<String>.broadcast();

  void simularCambioRemoto(String tabla) {
    if (!_cambiosRealtime.isClosed) {
      _cambiosRealtime.add(tabla);
    }
  }

  Future<void> dispose() async {
    await _cambiosRealtime.close();
  }

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
  Future<void> actualizarFcmToken({
    required String usuarioId,
    required String? fcmToken,
  }) async {
    _verificarRed();
    fcmTokensRemotos[usuarioId] = fcmToken;
  }

  static DateTime _parsearFechaUtc(Object? valor) {
    if (valor is String && valor.isNotEmpty) {
      return DateTime.tryParse(valor)?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static bool _esVerdadero(Object? valor) =>
      valor is bool ? valor : (valor as int? ?? 0) == 1;

  @override
  Future<void> upsertObra({
    required Map<String, dynamic> obra,
    required List<String> materiales,
  }) async {
    _verificarRed();
    final id = obra['id'] as String;
    final existente = obrasRemotas[id];
    if (!resolverConflictosLww || existente == null) {
      obrasRemotas[id] = {
        ...obra,
        'materiales': List<String>.from(materiales),
      };
      return;
    }

    final tsExistente = _parsearFechaUtc(
      existente['client_updated_at'] ?? existente['updated_at'],
    );
    final tsEntrante = _parsearFechaUtc(
      obra['client_updated_at'] ?? obra['updated_at'],
    );
    final finalizadaMonotonica = _esVerdadero(existente['finalizada']) ||
        _esVerdadero(obra['finalizada']);
    final finalizadaNueva = _esVerdadero(obra['finalizada']);
    final conFoto =
        _esVerdadero(existente['con_foto']) || _esVerdadero(obra['con_foto']);
    final fechaRepExistente =
        _parsearFechaUtc(existente['fecha_ultimo_reporte']);
    final fechaRepEntrante = _parsearFechaUtc(obra['fecha_ultimo_reporte']);
    final fechaUltimoReporte = fechaRepEntrante.isAfter(fechaRepExistente)
        ? fechaRepEntrante.toIso8601String()
        : fechaRepExistente.toIso8601String();

    if (tsEntrante.isBefore(tsExistente)) {
      obrasRemotas[id] = {
        ...existente,
        'finalizada': finalizadaMonotonica ? 1 : 0,
        'con_foto': conFoto ? 1 : 0,
        'fecha_ultimo_reporte': fechaUltimoReporte,
        'tarea_actual_id':
            finalizadaMonotonica ? null : existente['tarea_actual_id'],
      };
    } else {
      obrasRemotas[id] = {
        ...obra,
        'materiales': List<String>.from(materiales),
        'finalizada': finalizadaNueva ? 1 : 0,
        'con_foto': conFoto ? 1 : 0,
        'fecha_ultimo_reporte': fechaUltimoReporte,
        'tarea_actual_id': finalizadaNueva ? null : obra['tarea_actual_id'],
      };
    }
  }

  @override
  Future<void> upsertTarea(Map<String, dynamic> tarea) async {
    _verificarRed();
    final id = tarea['id'] as String;
    final existente = tareasRemotas[id];
    if (!resolverConflictosLww || existente == null) {
      tareasRemotas[id] = Map<String, dynamic>.from(tarea);
      return;
    }

    final tsExistente = _parsearFechaUtc(
      existente['client_updated_at'] ?? existente['updated_at'],
    );
    final tsEntrante = _parsearFechaUtc(
      tarea['client_updated_at'] ?? tarea['updated_at'],
    );
    if (!tsEntrante.isBefore(tsExistente)) {
      tareasRemotas[id] = Map<String, dynamic>.from(tarea);
    }
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
  Future<void> upsertPlantilla(Map<String, dynamic> plantilla) async {
    _verificarRed();
    plantillasRemotas[plantilla['id'] as String] =
        Map<String, dynamic>.from(plantilla);
  }

  @override
  Future<void> upsertConfiguracionRecordatorio(
    Map<String, dynamic> config,
  ) async {
    _verificarRed();
    configuracionesRecordatorioRemotas[config['ingeniero_id'] as String] =
        Map<String, dynamic>.from(config);
  }

  @override
  Future<CambiosRemotos> obtenerCambiosDesde(DateTime? ultimaSyncUtc) async {
    _verificarRed();
    if (!resolverConflictosLww) {
      return cambiosParaPull;
    }
    return CambiosRemotos(
      obras: obrasRemotas.values.map((o) {
        final obraId = o['id'] as String;
        final tareasDeObra = tareasRemotas.values
            .where((t) => t['obra_id'] == obraId)
            .map(Map<String, dynamic>.from)
            .toList();
        return {
          ...o,
          'tareas': tareasDeObra,
        };
      }).toList(),
      tareas: tareasRemotas.values.map(Map<String, dynamic>.from).toList(),
      reportes: reportesRemotos.values.map(Map<String, dynamic>.from).toList(),
    );
  }

  @override
  Stream<String> escucharCambiosRemotos() => _cambiosRealtime.stream;
}

/// Implementación Fake de [ServicioAutenticacionRemota] para probar el flujo
/// de Supabase Auth + respaldo offline sin red real.
class FakeServicioAutenticacionRemota implements ServicioAutenticacionRemota {
  FakeServicioAutenticacionRemota({
    this.perfilesPorEmail = const {},
    this.claveValida = 'Password123!',
    this.simularOfflineEnRefresh = false,
  });

  final Map<String, Map<String, dynamic>> perfilesPorEmail;
  final String claveValida;
  bool simularOfflineEnRefresh;

  String? _authUserIdActual;
  String? ultimoEmailRecibido;
  bool cerroSesionRemota = false;

  @override
  bool get estaDisponible => true;

  @override
  String? get usuarioAuthIdActual => _authUserIdActual;

  @override
  Future<Map<String, dynamic>?> iniciarSesion({
    required String email,
    required String password,
  }) async {
    ultimoEmailRecibido = email;
    if (password != claveValida) return null;
    final perfil = perfilesPorEmail[email];
    if (perfil == null) return null;
    _authUserIdActual = perfil['id'] as String;
    return Map<String, dynamic>.from(perfil);
  }

  @override
  Future<Map<String, dynamic>?> obtenerPerfilActual() async {
    if (simularOfflineEnRefresh || _authUserIdActual == null) return null;
    for (final perfil in perfilesPorEmail.values) {
      if (perfil['id'] == _authUserIdActual) {
        return Map<String, dynamic>.from(perfil);
      }
    }
    return null;
  }

  @override
  Future<void> actualizarContrasenia(String nuevaContrasenia) async {}

  @override
  Future<void> cerrarSesion() async {
    cerroSesionRemota = true;
    _authUserIdActual = null;
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
  String? ultimaBaseDatosRecordatorio;
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
    String? nombreBaseDatos,
  }) async {
    recordatoriosProgramados.add((hora, minuto));
    ultimaBaseDatosRecordatorio = nombreBaseDatos;
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

/// Implementación Fake de [ServicioPushFcm] para probar el registro, rotación
/// y limpieza de tokens FCM sin tocar Firebase real.
class FakeServicioPushFcm implements ServicioPushFcm {
  FakeServicioPushFcm({
    this.tokenActual = 'token_fcm_fake_1',
    this.estaDisponible = true,
  });

  String? tokenActual;

  @override
  bool estaDisponible;

  bool tokenEliminado = false;
  final StreamController<String> _cambiosToken =
      StreamController<String>.broadcast();

  @override
  Future<void> inicializarPush() async {}

  @override
  Future<String?> obtenerToken() async => tokenActual;

  @override
  Stream<String> get cambiosDeToken => _cambiosToken.stream;

  @override
  Future<void> eliminarToken() async {
    tokenEliminado = true;
    tokenActual = null;
  }

  void simularRotacionToken(String nuevoToken) {
    tokenActual = nuevoToken;
    if (!_cambiosToken.isClosed) {
      _cambiosToken.add(nuevoToken);
    }
  }

  Future<void> dispose() async {
    await _cambiosToken.close();
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
