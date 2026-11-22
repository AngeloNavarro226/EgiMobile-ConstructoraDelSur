import 'dart:async';

import '../services/preferencias_service.dart';

/// Repositorio que mantiene y persiste las preferencias visuales, sesión
/// offline, borradores y copia local del recordatorio mediante [PreferenciasService].
class PreferenciasRepository {
  PreferenciasRepository({PreferenciasService? preferenciasService})
      : _preferenciasService = preferenciasService ?? PreferenciasService();

  final PreferenciasService _preferenciasService;

  bool _modoOscuro = false;
  bool _recibirAlertasSemaforo = true;
  String _borradorObservaciones = '';
  String? _usuarioSesionId;
  RecordatorioLocalPreferencias _recordatorioLocal =
      const RecordatorioLocalPreferencias(activo: false, hora: 18, minuto: 0);

  /// Indica si el tema oscuro está activo.
  bool get modoOscuro => _modoOscuro;

  /// Indica si el usuario tiene activadas las alertas cuando una obra pasa a
  /// amarillo o rojo.
  bool get recibirAlertasSemaforo => _recibirAlertasSemaforo;

  /// Último borrador de observaciones guardado automáticamente.
  String get borradorObservaciones => _borradorObservaciones;

  /// Identificador del usuario con sesión offline guardada.
  String? get usuarioSesionId => _usuarioSesionId;

  /// Última configuración efectiva del recordatorio diario en este dispositivo.
  RecordatorioLocalPreferencias get recordatorioLocal => _recordatorioLocal;

  /// Carga los valores persistidos en `SharedPreferencesAsync`.
  Future<void> inicializar() async {
    _modoOscuro = await _preferenciasService.obtenerTemaOscuro();
    _recibirAlertasSemaforo =
        await _preferenciasService.obtenerRecibirAlertas();
    _borradorObservaciones =
        await _preferenciasService.obtenerBorradorInforme();
    _usuarioSesionId = await _preferenciasService.obtenerUsuarioSesionId();
    _recordatorioLocal = await _preferenciasService.obtenerRecordatorioLocal();
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

  /// Limpia únicamente el borrador tras guardar un informe diario.
  Future<void> limpiarBorradorObservaciones() async {
    _borradorObservaciones = '';
    await _preferenciasService.guardarBorradorInforme('');
  }

  /// Persiste la sesión del usuario para reabrir offline sin perder el acceso.
  Future<void> guardarUsuarioSesionId(String? usuarioId) async {
    _usuarioSesionId = usuarioId;
    await _preferenciasService.guardarUsuarioSesionId(usuarioId);
  }

  /// Recupera el identificador de sesión persistido.
  Future<String?> obtenerUsuarioSesionId() async {
    _usuarioSesionId = await _preferenciasService.obtenerUsuarioSesionId();
    return _usuarioSesionId;
  }

  /// Persiste en `SharedPreferencesAsync` la copia del recordatorio diario
  /// efectivo programado en el dispositivo.
  Future<void> guardarRecordatorioLocal({
    required bool activo,
    required int hora,
    required int minuto,
    String? nombreBaseDatos,
  }) async {
    _recordatorioLocal = RecordatorioLocalPreferencias(
      activo: activo,
      hora: hora,
      minuto: minuto,
      nombreBaseDatos: nombreBaseDatos,
    );
    await _preferenciasService.guardarRecordatorioLocal(
      activo: activo,
      hora: hora,
      minuto: minuto,
      nombreBaseDatos: nombreBaseDatos,
    );
  }

  /// Marca como desactivado el recordatorio local en `SharedPreferencesAsync`.
  Future<void> desactivarRecordatorioLocal() async {
    await guardarRecordatorioLocal(
      activo: false,
      hora: _recordatorioLocal.hora,
      minuto: _recordatorioLocal.minuto,
      nombreBaseDatos: _recordatorioLocal.nombreBaseDatos,
    );
  }

  /// Limpia borrador, sesión y copia del recordatorio al cerrar sesión.
  Future<void> limpiarSesion() async {
    _borradorObservaciones = '';
    _usuarioSesionId = null;
    _recordatorioLocal = const RecordatorioLocalPreferencias(
      activo: false,
      hora: 18,
      minuto: 0,
    );
    await _preferenciasService.limpiarPreferenciasDeSesion();
  }
}
