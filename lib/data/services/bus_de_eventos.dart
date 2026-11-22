import 'dart:async';

import '../../domain/models/evento_de_app.dart';

///
/// Utiliza `StreamController<EventoDeApp>.broadcast()` para que múltiples
/// ViewModels puedan suscribirse y reaccionar a eventos de dominio sin
/// acoplarse entre sí.
class BusDeEventos {
  final StreamController<EventoDeApp> _controlador =
      StreamController<EventoDeApp>.broadcast();

  /// Flujo de eventos emitido a todos los suscriptores activos.
  Stream<EventoDeApp> get stream => _controlador.stream;

  /// Publica un nuevo [evento] en el bus si no fue cerrado.
  void emitir(EventoDeApp evento) {
    if (!_controlador.isClosed) {
      _controlador.add(evento);
    }
  }

  /// Cierra el controlador al finalizar el ciclo de vida.
  Future<void> dispose() async {
    await _controlador.close();
  }
}
