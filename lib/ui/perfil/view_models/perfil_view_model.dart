import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/autenticacion_repository.dart';
import '../../../data/repositories/notificaciones_repository.dart';
import '../../../data/repositories/preferencias_repository.dart';
import '../../../data/services/sincronizacion_service.dart';
import '../../../domain/models/usuario.dart';

/// ViewModel de la pantalla de Perfil (compartida por Ingeniero, Capataz y Dueño).
///
/// Gestiona la edición de los datos del usuario en SQLite, el cambio de tema
/// oscuro, la preferencia de alertas y la prueba de detección de internet.
class PerfilViewModel extends ChangeNotifier {
  PerfilViewModel({
    required AutenticacionRepository autenticacionRepository,
    required PreferenciasRepository preferenciasRepository,
    required SincronizacionService sincronizacionService,
    NotificacionesRepository? notificacionesRepository,
  })  : _autenticacionRepository = autenticacionRepository,
        _preferenciasRepository = preferenciasRepository,
        _sincronizacionService = sincronizacionService,
        _notificacionesRepository = notificacionesRepository;

  final AutenticacionRepository _autenticacionRepository;
  final PreferenciasRepository _preferenciasRepository;
  final SincronizacionService _sincronizacionService;
  final NotificacionesRepository? _notificacionesRepository;

  /// Usuario autenticado actualmente.
  Usuario? get usuarioActual => _autenticacionRepository.usuarioActual;

  /// Indica si el modo oscuro está activo.
  bool get modoOscuro => _preferenciasRepository.modoOscuro;

  /// Indica si las alertas de cambio de semáforo están habilitadas.
  bool get notificacionesActivas =>
      _preferenciasRepository.recibirAlertasSemaforo;

  /// Alterna entre el modo claro y oscuro.
  void alternarModoOscuro() {
    _preferenciasRepository.alternarModoOscuro();
    notifyListeners();
  }

  /// Activa o desactiva la recepción de alertas proactivas, pidiendo permiso
  /// al sistema operativo en contexto si se habilitan
  void cambiarNotificaciones(bool valor) {
    _preferenciasRepository.cambiarRecibirAlertas(valor);
    if (valor) {
      unawaited(
        _notificacionesRepository?.solicitarPermisoEnContexto() ??
            Future<bool>.value(true),
      );
    }
    notifyListeners();
  }

  /// Actualiza el nombre, teléfono y contraseña del perfil en SQLite.
  Future<void> actualizarDatosPerfil({
    required String nombre,
    required String telefono,
    required String contrasenia,
  }) async {
    await _autenticacionRepository.actualizarPerfil(
      nombre: nombre,
      telefono: telefono,
      contrasenia: contrasenia,
    );
    notifyListeners();
  }

  /// Simula la detección de conexión a internet para verificar la alerta de
  /// 2 segundos `"Comenzando sincronización"` en todas las vistas.
  Future<void> simularConexionInternet() async {
    await _sincronizacionService.dispararDeteccionDeInternet();
  }
}
