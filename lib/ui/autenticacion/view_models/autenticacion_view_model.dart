import 'package:flutter/foundation.dart';

import '../../../data/repositories/autenticacion_repository.dart';
import '../../../domain/models/usuario.dart';

/// ViewModel encargado del estado de inicio y cierre de sesión, así como
/// de la validación de credenciales contra los 3 usuarios de prueba en SQLite.
class AutenticacionViewModel extends ChangeNotifier {
  AutenticacionViewModel({required AutenticacionRepository repositorio})
      : _repositorio = repositorio;

  final AutenticacionRepository _repositorio;

  bool _estaCargando = false;
  bool _credencialesInvalidas = false;

  /// Usuario autenticado actualmente, o `null` si no hay sesión iniciada.
  Usuario? get usuarioActual => _repositorio.usuarioActual;

  /// Indica si hay una sesión activa.
  bool get tieneSesionActiva => usuarioActual != null;

  /// Indica si se está verificando el inicio de sesión.
  bool get estaCargando => _estaCargando;

  /// Indica si el último intento de inicio de sesión falló por usuario o
  /// contraseña inválidos.
  bool get credencialesInvalidas => _credencialesInvalidas;

  /// Limpia el aviso de error cuando el usuario modifica los campos de texto.
  void limpiarError() {
    if (!_credencialesInvalidas) return;
    _credencialesInvalidas = false;
    notifyListeners();
  }

  /// Valida el usuario y contraseña ingresados.
  Future<bool> iniciarSesion({
    required String usuario,
    required String contrasenia,
  }) async {
    if (usuario.trim().isEmpty || contrasenia.trim().isEmpty) {
      _credencialesInvalidas = true;
      notifyListeners();
      return false;
    }

    _estaCargando = true;
    _credencialesInvalidas = false;
    notifyListeners();

    final autenticado = await _repositorio.iniciarSesion(
      identificador: usuario,
      contrasenia: contrasenia,
    );

    _estaCargando = false;
    if (autenticado == null) {
      _credencialesInvalidas = true;
      notifyListeners();
      return false;
    }

    notifyListeners();
    return true;
  }

  /// Cierra la sesión actual y redirige a la pantalla de Login.
  void cerrarSesion() {
    _repositorio.cerrarSesion();
    _credencialesInvalidas = false;
    notifyListeners();
  }

  /// Refresca los listeners cuando el perfil del usuario actual fue editado.
  void notificarPerfilActualizado() {
    notifyListeners();
  }
}
