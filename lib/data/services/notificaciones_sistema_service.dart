import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/aviso.dart';

/// Interfaz del servicio de notificaciones
///
/// Permite que los repositorios y ViewModels trabajen contra una abstracción
/// testeable con un Fake (`NotificacionesFalsas`) sin invocar canales nativos
/// durante los tests ni pedir permisos en el arranque de `main()`.
abstract class ServicioDeNotificaciones {
  /// Solicita permiso al usuario en contexto (por ejemplo, al activar alertas
  /// o enviar una notificación, nunca al iniciar `main()`).
  ///
  /// Devuelve `true` solo si el usuario realmente lo concedió.
  Future<bool> pedirPermiso();

  /// Muestra un [aviso] inmediato en la barra superior de estado del teléfono.
  Future<void> mostrar(Aviso aviso);

  /// Cancela un aviso activo por su [id].
  Future<void> cancelar(int id);

  /// Programa un aviso que se repite todos los días a [hora]:[minuto]
  /// (lo agenda el sistema operativo con `AlarmManager`, funciona con la app
  /// cerrada).
  Future<void> programarRecordatorioDiario({
    required int hora,
    required int minuto,
    required String titulo,
    required String mensaje,
  });

  /// Cancela el recordatorio diario programado.
  Future<void> cancelarRecordatorioDiario();

  /// Flujo que emite el identificador `alTocar` cuando el usuario toca un aviso.
  Stream<String> get toques;
}

/// Implementación real que se comunica con la barra de estado nativa de Android
/// a través del `MethodChannel` propio configurado en `MainActivity.kt`.
class NotificacionesSistemaService implements ServicioDeNotificaciones {
  static const MethodChannel _canal = MethodChannel(
    'constructora_del_sur/notificaciones_nativas',
  );

  final StreamController<String> _controladorToques =
      StreamController<String>.broadcast();

  @override
  Stream<String> get toques => _controladorToques.stream;

  @override
  Future<bool> pedirPermiso() async {
    if (kIsWeb) return true;
    try {
      // El lado nativo espera la respuesta del diálogo del sistema y devuelve
      // true/false según lo que el usuario eligió realmente.
      final concedido = await _canal.invokeMethod<bool>('pedirPermiso');
      return concedido ?? false;
    } catch (e) {
      debugPrint('[Notificaciones] pedirPermiso falló: $e');
      return false;
    }
  }

  @override
  Future<void> mostrar(Aviso aviso) async {
    if (kIsWeb) return;
    try {
      // Siempre se consulta/pide el permiso ANTES de publicar: si se publica
      // sin permiso, Android descarta el aviso en silencio.
      final permitido = await pedirPermiso();
      if (!permitido) {
        debugPrint(
            '[Notificaciones] Sin permiso: aviso "${aviso.titulo}" omitido');
        return;
      }
      await _canal.invokeMethod<bool>('mostrarNotificacion', {
        'id': aviso.id,
        'titulo': aviso.titulo,
        'mensaje': aviso.cuerpo,
      });
    } catch (e) {
      debugPrint('[Notificaciones] mostrar falló: $e');
    }
  }

  @override
  Future<void> cancelar(int id) async {
    if (kIsWeb) return;
    try {
      await _canal.invokeMethod<bool>('cancelarNotificacion', {'id': id});
    } catch (e) {
      debugPrint('[Notificaciones] cancelar falló: $e');
    }
  }

  @override
  Future<void> programarRecordatorioDiario({
    required int hora,
    required int minuto,
    required String titulo,
    required String mensaje,
  }) async {
    if (kIsWeb) return;
    try {
      await _canal.invokeMethod<bool>('programarRecordatorio', {
        'hora': hora,
        'minuto': minuto,
        'titulo': titulo,
        'mensaje': mensaje,
      });
    } catch (e) {
      debugPrint('[Notificaciones] programarRecordatorio falló: $e');
    }
  }

  @override
  Future<void> cancelarRecordatorioDiario() async {
    if (kIsWeb) return;
    try {
      await _canal.invokeMethod<bool>('cancelarRecordatorio');
    } catch (e) {
      debugPrint('[Notificaciones] cancelarRecordatorio falló: $e');
    }
  }

  /// Método de conveniencia para disparar un aviso en la barra superior.
  Future<void> mostrarEnBarraSuperior({
    required String titulo,
    required String mensaje,
    String? alTocar,
  }) async {
    final idUnico = DateTime.now().millisecondsSinceEpoch % 100000;
    await mostrar(
      Aviso(
        id: idUnico,
        titulo: titulo,
        cuerpo: mensaje,
        alTocar: alTocar,
      ),
    );
  }

  void dispose() {
    _controladorToques.close();
  }
}
