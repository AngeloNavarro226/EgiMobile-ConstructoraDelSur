import '../../../data/repositories/autenticacion_repository.dart';
import '../../../domain/models/usuario.dart';
import '../../core/view_model_base.dart';

/// ViewModel encargado del estado de inicio, restauración offline y cierre de
/// sesión, notificando explícitamente todas las transiciones relevantes.
class AutenticacionViewModel extends ViewModelBase {
  AutenticacionViewModel({required AutenticacionRepository repositorio})
      : _repositorio = repositorio;

  final AutenticacionRepository _repositorio;

  EstadoOperacion _estado = EstadoOperacion.inicial;
  bool _estaCargando = false;
  bool _credencialesInvalidas = false;
  String? _mensajeError;

  /// Estado actual de la operación de autenticación.
  EstadoOperacion get estado => _estado;

  /// Usuario autenticado actualmente, o `null` si no hay sesión iniciada.
  Usuario? get usuarioActual => _repositorio.usuarioActual;

  /// Indica si hay una sesión activa.
  bool get tieneSesionActiva => usuarioActual != null;

  /// Indica si se está verificando el inicio o restauración de sesión.
  bool get estaCargando => _estaCargando;

  /// Indica si el último intento de inicio de sesión falló por credenciales.
  bool get credencialesInvalidas => _credencialesInvalidas;

  /// Mensaje de error técnico distinto de credenciales inválidas.
  String? get mensajeError => _mensajeError;

  /// Limpia los avisos de error cuando el usuario modifica los campos de texto.
  void limpiarError() {
    if (!_credencialesInvalidas && _mensajeError == null) return;
    _credencialesInvalidas = false;
    _mensajeError = null;
    notificarSiActivo();
  }

  /// Restaura la sesión offline guardada en preferencias locales al iniciar.
  Future<bool> restaurarSesion() async {
    _estado = EstadoOperacion.cargando;
    _estaCargando = true;
    _mensajeError = null;
    notificarSiActivo();

    try {
      final usuario = await _repositorio.restaurarSesionGuardada();
      _estaCargando = false;
      _estado = EstadoOperacion.exito;
      notificarSiActivo();
      return usuario != null;
    } catch (e) {
      _estaCargando = false;
      _estado = EstadoOperacion.error;
      _mensajeError = 'No se pudo restaurar la sesión local: $e';
      notificarSiActivo();
      return false;
    }
  }

  /// Valida el usuario y contraseña ingresados.
  Future<bool> iniciarSesion({
    required String usuario,
    required String contrasenia,
  }) async {
    if (usuario.trim().isEmpty || contrasenia.trim().isEmpty) {
      _credencialesInvalidas = true;
      _mensajeError = null;
      _estado = EstadoOperacion.error;
      notificarSiActivo();
      return false;
    }

    _estado = EstadoOperacion.cargando;
    _estaCargando = true;
    _credencialesInvalidas = false;
    _mensajeError = null;
    notificarSiActivo();

    try {
      final autenticado = await _repositorio.iniciarSesion(
        identificador: usuario,
        contrasenia: contrasenia,
      );

      _estaCargando = false;
      if (autenticado == null) {
        _credencialesInvalidas = true;
        _estado = EstadoOperacion.error;
        notificarSiActivo();
        return false;
      }

      _estado = EstadoOperacion.exito;
      notificarSiActivo();
      return true;
    } catch (e) {
      _estaCargando = false;
      _credencialesInvalidas = false;
      _estado = EstadoOperacion.error;
      _mensajeError = 'Error al iniciar sesión: $e';
      notificarSiActivo();
      return false;
    }
  }

  /// Cierra la sesión actual, limpia la sesión offline y notifica a la app.
  Future<void> cerrarSesion() async {
    await _repositorio.cerrarSesion();
    _credencialesInvalidas = false;
    _mensajeError = null;
    _estado = EstadoOperacion.inicial;
    notificarSiActivo();
  }

  /// Refresca los listeners cuando el perfil del usuario actual fue editado.
  void notificarPerfilActualizado() {
    notificarSiActivo();
  }
}
