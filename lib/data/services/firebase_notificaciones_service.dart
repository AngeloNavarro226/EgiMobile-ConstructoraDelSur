import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/aviso.dart';
import 'notificaciones_sistema_service.dart';

/// Handler top-level obligatorio para mensajes FCM recibidos con la app en
/// segundo plano o cerrada (`terminated`).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    debugPrint('[FCM Background] Mensaje recibido: ${message.messageId}');
  } catch (e) {
    debugPrint('[FCM Background] Error al inicializar Firebase: $e');
  }
}

/// Contrato desacoplado para la gestión de tokens y escuchas push FCM,
/// permitiendo inyectar un stub/fake en pruebas unitarias sin tocar Firebase.
abstract interface class ServicioPushFcm {
  /// Indica si Firebase está inicializado y disponible en este entorno.
  bool get estaDisponible;

  /// Inicializa las escuchas de mensajes en primer plano y apertura por toque.
  Future<void> inicializarPush();

  /// Obtiene el token FCM actual del dispositivo, o `null` si no está disponible.
  Future<String?> obtenerToken();

  /// Emite cada nuevo token cuando FCM lo rota automáticamente.
  Stream<String> get cambiosDeToken;

  /// Invalida el token FCM local (útil al cerrar sesión para no recibir alertas
  /// del usuario anterior).
  Future<void> eliminarToken();
}

/// Implementación no-op por defecto para tests o entornos sin Firebase.
class ServicioPushFcmOffline implements ServicioPushFcm {
  const ServicioPushFcmOffline();

  @override
  bool get estaDisponible => false;

  @override
  Future<void> inicializarPush() async {}

  @override
  Future<String?> obtenerToken() async => null;

  @override
  Stream<String> get cambiosDeToken => const Stream<String>.empty();

  @override
  Future<void> eliminarToken() async {}
}

/// Implementación real de [ServicioDeNotificaciones] y [ServicioPushFcm] con
/// Firebase Cloud Messaging (FCM) + canal local nativo de Android para:
/// - Mostrar push entrantes cuando la app está en primer plano (`onMessage`).
/// - Programar/cancelar el recordatorio diario local (`AlarmManager`).
class FirebaseNotificacionesService
    implements ServicioDeNotificaciones, ServicioPushFcm {
  FirebaseNotificacionesService({
    NotificacionesSistemaService? servicioLocal,
    bool Function()? debeMostrarPushEnPrimerPlano,
  })  : _local = servicioLocal ?? NotificacionesSistemaService(),
        _debeMostrarPushEnPrimerPlano = debeMostrarPushEnPrimerPlano;

  final NotificacionesSistemaService _local;
  final bool Function()? _debeMostrarPushEnPrimerPlano;

  final StreamController<String> _controladorToques =
      StreamController<String>.broadcast();
  final StreamController<String> _controladorTokens =
      StreamController<String>.broadcast();

  StreamSubscription<RemoteMessage>? _subOnMessage;
  StreamSubscription<RemoteMessage>? _subOnMessageOpened;
  StreamSubscription<String>? _subTokenRefresh;
  StreamSubscription<String>? _subToquesLocales;
  bool _escuchasInicializadas = false;

  @override
  bool get estaDisponible {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<String> get toques => _controladorToques.stream;

  @override
  Stream<String> get cambiosDeToken => _controladorTokens.stream;

  @override
  Future<void> inicializarPush() async {
    if (_escuchasInicializadas) return;
    _escuchasInicializadas = true;

    _subToquesLocales = _local.toques.listen((destino) {
      if (!_controladorToques.isClosed) {
        _controladorToques.add(destino);
      }
    });

    if (!estaDisponible) return;

    try {
      final messaging = FirebaseMessaging.instance;

      _subOnMessage = FirebaseMessaging.onMessage.listen((message) {
        final habilitadas = _debeMostrarPushEnPrimerPlano?.call() ?? true;
        if (!habilitadas) return;

        final titulo = message.notification?.title ??
            (message.data['titulo'] as String?) ??
            'Constructora Del Sur';
        final cuerpo = message.notification?.body ??
            (message.data['mensaje'] as String?) ??
            '';
        if (cuerpo.isEmpty && message.notification == null) return;

        final alTocar = _extraerDestinoToque(message);
        final id = (message.messageId?.hashCode.abs() ??
                DateTime.now().millisecondsSinceEpoch) %
            100000;
        unawaited(
          _local.mostrar(
            Aviso(
              id: id,
              titulo: titulo,
              cuerpo: cuerpo,
              alTocar: alTocar,
            ),
          ),
        );
      });

      _subOnMessageOpened =
          FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final destino = _extraerDestinoToque(message);
        if (destino != null && !_controladorToques.isClosed) {
          _controladorToques.add(destino);
        }
      });

      // Usamos token de registro FCM clásico compatible con FCM HTTP v1 (`message.token`)
      // y nuestra Edge Function `enviar-push-fcm`.
      // ignore: deprecated_member_use
      _subTokenRefresh = messaging.onTokenRefresh.listen((nuevoToken) {
        if (nuevoToken.isNotEmpty && !_controladorTokens.isClosed) {
          _controladorTokens.add(nuevoToken);
        }
      });

      final inicial = await messaging.getInitialMessage();
      if (inicial != null) {
        final destino = _extraerDestinoToque(inicial);
        if (destino != null && !_controladorToques.isClosed) {
          _controladorToques.add(destino);
        }
      }
    } catch (e) {
      debugPrint('[FCM] inicializarPush falló: $e');
    }
  }

  @override
  Future<bool> pedirPermiso() async {
    if (kIsWeb) return true;
    if (estaDisponible) {
      try {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        final concedido =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
                settings.authorizationStatus == AuthorizationStatus.provisional;
        if (concedido) return true;
      } catch (e) {
        debugPrint('[FCM] requestPermission falló, usando canal local: $e');
      }
    }
    return _local.pedirPermiso();
  }

  @override
  Future<String?> obtenerToken() async {
    if (!estaDisponible) return null;
    try {
      // ignore: deprecated_member_use
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('[FCM] obtenerToken falló: $e');
      return null;
    }
  }

  @override
  Future<void> eliminarToken() async {
    if (!estaDisponible) return;
    try {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('[FCM] eliminarToken falló: $e');
    }
  }

  @override
  Future<void> mostrar(Aviso aviso) => _local.mostrar(aviso);

  @override
  Future<void> cancelar(int id) => _local.cancelar(id);

  @override
  Future<void> programarRecordatorioDiario({
    required int hora,
    required int minuto,
    required String titulo,
    required String mensaje,
    String? nombreBaseDatos,
  }) {
    return _local.programarRecordatorioDiario(
      hora: hora,
      minuto: minuto,
      titulo: titulo,
      mensaje: mensaje,
      nombreBaseDatos: nombreBaseDatos,
    );
  }

  @override
  Future<void> cancelarRecordatorioDiario() =>
      _local.cancelarRecordatorioDiario();

  String? _extraerDestinoToque(RemoteMessage message) {
    final alTocar = message.data['al_tocar'] as String?;
    if (alTocar != null && alTocar.isNotEmpty) return alTocar;
    final obraId = message.data['obra_id'] as String?;
    if (obraId != null && obraId.isNotEmpty) return 'obra:$obraId';
    return null;
  }

  Future<void> dispose() async {
    await _subOnMessage?.cancel();
    await _subOnMessageOpened?.cancel();
    await _subTokenRefresh?.cancel();
    await _subToquesLocales?.cancel();
    await _controladorToques.close();
    await _controladorTokens.close();
    _local.dispose();
  }
}
