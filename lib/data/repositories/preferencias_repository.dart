import 'dart:async';

import '../services/preferencias_service.dart';

/// Repositorio que mantiene y persiste las preferencias visuales y borradores
/// de la sesión mediante [PreferenciasService]
class PreferenciasRepository {
  PreferenciasRepository({PreferenciasService? preferenciasService})
      : _preferenciasService = preferenciasService ?? PreferenciasService();

  final PreferenciasService _preferenciasService;

  bool _modoOscuro = false;
  bool _recibirAlertasSemaforo = true;
  String _borradorObservaciones = '';

  /// Indica si el tema oscuro está activo.
  bool get modoOscuro => _modoOscuro;

  /// Indica si el usuario tiene activadas las alertas cuando una obra pasa a
  /// amarillo o rojo.
  bool get recibirAlertasSemaforo => _recibirAlertasSemaforo;

  /// Último borrador de observaciones guardado automáticamente.
  String get borradorObservaciones => _borradorObservaciones;

  /// Carga los valores persistidos en `SharedPreferencesAsync`.
  Future<void> inicializar() async {
    _modoOscuro = await _preferenciasService.obtenerTemaOscuro();
    _recibirAlertasSemaforo =
        await _preferenciasService.obtenerRecibirAlertas();
    _borradorObservaciones =
        await _preferenciasService.obtenerBorradorInforme();
  }

  /// Alterna entre el tema claro y oscuro y lo persiste en disco.
  bool alternarModoOscuro() {
    _modoOscuro = !_modoOscuro;
    unawaited(_preferenciasService.guardarTemaOscuro(oscuro: _modoOscuro));
    return _modoOscuro;
  }

  /// Cambia la preferencia de notificaciones proactivas de semáforo y la persiste.
  void cambiarRecibirAlertas(bool activo) {
    _recibirAlertasSemaforo = activo;
    unawaited(_preferenciasService.guardarRecibirAlertas(activo: activo));
  }

  /// Guarda el borrador del informe cuando la app se oculta (`onHide`).
  Future<void> guardarBorradorObservaciones(String texto) async {
    _borradorObservaciones = texto;
    await _preferenciasService.guardarBorradorInforme(texto);
  }

  /// Limpia el borrador tras guardar un informe diario.
  Future<void> limpiarBorradorObservaciones() async {
    _borradorObservaciones = '';
    await _preferenciasService.limpiarPreferenciasDeSesion();
  }
}
