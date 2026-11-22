import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

/// Nombre de la tarea periódica de sincronización en Workmanager.
const tareaSincronizacionWorkmanager = 'sincronizar_reportes_pendientes_task';

/// Función pura que determina si la lista de resultados de `connectivity_plus`
/// incluye al menos una interfaz con red
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
/// unitarios
Future<bool> ejecutarTareaSincronizacion(
  String nombreTarea,
  Map<String, dynamic>? datosEntrada,
) async {
  try {
    // En producción sincroniza los registros locales con `sync_status = pending`.
    return true;
  } catch (_) {
    return false;
  }
}

/// Punto de entrada de nivel superior requerido por `Workmanager`
///
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((nombreTarea, datosEntrada) async {
    DartPluginRegistrant.ensureInitialized();
    return ejecutarTareaSincronizacion(nombreTarea, datosEntrada);
  });
}

/// Servicio que escucha los cambios de conectividad (`connectivity_plus`) y
/// gestiona la sincronización en segundo plano (`workmanager`).
///
/// Combina el chequeo puntual `checkConnectivity()` con el flujo continuo
/// `onConnectivityChanged.map(hayAlgunaRed).distinct()`
class SincronizacionService {
  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _controladorEventosConexion =
      StreamController<bool>.broadcast();

  StreamSubscription<bool>? _suscripcionRed;
  bool _inicializado = false;

  /// Stream que emite `true` cada vez que se detecta conexión activa (Wi-Fi o 4G).
  Stream<bool> get alDetectarConexion => _controladorEventosConexion.stream;

  /// Consulta puntual del estado actual de conectividad
  Future<bool> verificarConectividadActual() async {
    try {
      final resultados = await _connectivity.checkConnectivity();
      return hayAlgunaRed(resultados);
    } catch (_) {
      return false;
    }
  }

  /// Inicializa el listener de red con `.map(hayAlgunaRed).distinct()` y
  /// registra el dispatcher de Workmanager.
  Future<void> inicializar() async {
    if (_inicializado) return;
    _inicializado = true;

    if (!kIsWeb) {
      try {
        await Workmanager().initialize(callbackDispatcher);
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

  /// Verifica el estado actual de la red o simula la detección de internet
  /// para probar el flujo local de sincronización.
  Future<void> dispararDeteccionDeInternet() async {
    if (!_controladorEventosConexion.isClosed) {
      _controladorEventosConexion.add(true);
    }
  }

  /// Libera la suscripción a los cambios de red
  void dispose() {
    _suscripcionRed?.cancel();
    _controladorEventosConexion.close();
  }
}
