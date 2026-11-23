import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'base_datos_local_service.dart';
import 'configuracion_supabase.dart';
import 'motor_sincronizacion.dart';
import 'supabase_remote_service.dart';

/// Nombre de la tarea periódica de sincronización en Workmanager.
const tareaSincronizacionWorkmanager = 'sincronizar_reportes_pendientes_task';

/// Función pura que determina si la lista de resultados de `connectivity_plus`
/// incluye al menos una interfaz con red.
bool hayAlgunaRed(List<ConnectivityResult> resultados) {
  return resultados.any(
    (r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet,
  );
}

/// Lógica de la tarea de sincronización en segundo plano separada del
/// dispatcher de Workmanager para poder probarla directamente en tests
/// unitarios. Devuelve `false` ante errores transitorios para que Android
/// aplique *backoff* y reintente automáticamente.
Future<bool> ejecutarTareaSincronizacion(
  String nombreTarea,
  Map<String, dynamic>? datosEntrada, {
  Future<bool> Function()? ejecutor,
}) async {
  try {
    if (ejecutor != null) {
      return await ejecutor();
    }

    final config = ConfiguracionSupabase.desdeEntorno();
    if (!config.estaConfigurado) {
      return true;
    }

    SupabaseClient client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: config.url,
        publishableKey: config.publishableKey,
      );
      client = Supabase.instance.client;
    }

    if (client.auth.currentSession == null) {
      return true;
    }

    final db = BaseDatosLocalService(
      insertarSemillasDePrueba: false,
      nombreArchivo: BaseDatosLocalService.nombreArchivoSupabase,
      instanciaUnica: false,
    );
    try {
      final motor = MotorSincronizacion(
        baseDatosLocal: db,
        fuenteRemota: SupabaseRemoteService(client: client),
      );
      final resultado = await motor.sincronizarTodo(
        permitirSimulacionLocal: false,
      );
      return !resultado.tuvoErrores;
    } finally {
      await db.cerrar();
    }
  } catch (_) {
    return false;
  }
}

/// Punto de entrada de nivel superior requerido por `Workmanager`.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((nombreTarea, datosEntrada) async {
    DartPluginRegistrant.ensureInitialized();
    return ejecutarTareaSincronizacion(nombreTarea, datosEntrada);
  });
}

/// Servicio que escucha los cambios de conectividad (`connectivity_plus`) y
/// gestiona la sincronización en segundo plano (`workmanager`).
class SincronizacionService {
  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _controladorEventosConexion =
      StreamController<bool>.broadcast();

  StreamSubscription<bool>? _suscripcionRed;
  bool _inicializado = false;

  /// Stream que emite `true` cada vez que se detecta conexión activa (Wi-Fi o 4G).
  Stream<bool> get alDetectarConexion => _controladorEventosConexion.stream;

  /// Consulta puntual del estado actual de conectividad.
  Future<bool> verificarConectividadActual() async {
    try {
      final resultados = await _connectivity.checkConnectivity();
      return hayAlgunaRed(resultados);
    } catch (_) {
      return false;
    }
  }

  /// Inicializa el listener de red con `.map(hayAlgunaRed).distinct()`,
  /// registra el dispatcher y la tarea periódica con red en Workmanager.
  Future<void> inicializar() async {
    if (_inicializado) return;
    _inicializado = true;

    if (!kIsWeb) {
      try {
        await Workmanager().initialize(callbackDispatcher);
        await Workmanager().registerPeriodicTask(
          tareaSincronizacionWorkmanager,
          tareaSincronizacionWorkmanager,
          frequency: const Duration(minutes: 15),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
          constraints: Constraints(networkType: NetworkType.connected),
        );
      } catch (_) {
        // Ignorado en tests o plataformas de escritorio.
      }
    }

    try {
      _suscripcionRed = _connectivity.onConnectivityChanged
          .map(hayAlgunaRed)
          .distinct()
          .listen((conectado) {
        if (conectado && !_controladorEventosConexion.isClosed) {
          _controladorEventosConexion.add(true);
        }
      });
    } catch (_) {
      // Si el plugin de conectividad no responde en entorno de test,
      // se permite disparar manualmente la detección de internet.
    }
  }

  /// Dispara manualmente un evento de conectividad para probar el ciclo
  /// local de sincronización.
  Future<void> dispararDeteccionDeInternet() async {
    if (!_controladorEventosConexion.isClosed) {
      _controladorEventosConexion.add(true);
    }
  }

  /// Libera la suscripción a los cambios de red.
  void dispose() {
    _suscripcionRed?.cancel();
    _controladorEventosConexion.close();
  }
}
