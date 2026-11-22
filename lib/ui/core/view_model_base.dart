import 'package:flutter/foundation.dart';

/// Estado genérico de una operación asíncrona expuesta por un ViewModel.
enum EstadoOperacion { inicial, cargando, exito, error }

/// Clase base para los ViewModels de la aplicación.
///
/// Garantiza que nunca se invoque [notifyListeners] después de [dispose]
/// (por ejemplo, al completarse un `Future` o un `Timer` pendiente).
abstract class ViewModelBase extends ChangeNotifier {
  bool _descartado = false;

  /// Indica si el ViewModel ya fue liberado con [dispose].
  bool get estaDescartado => _descartado;

  /// Notifica a los listeners únicamente si el ViewModel sigue activo.
  @protected
  void notificarSiActivo() {
    if (!_descartado) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _descartado = true;
    super.dispose();
  }
}
