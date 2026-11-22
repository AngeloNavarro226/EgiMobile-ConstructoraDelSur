import 'package:shared_preferences/shared_preferences.dart';

/// Servicio que encapsula `SharedPreferencesAsync`
///
/// Centraliza las claves como constantes privadas y expone métodos con nombres
/// del dominio (`obtenerTemaOscuro`, `guardarTemaOscuro`, `guardarBorradorInforme`,
/// `limpiarPreferencias`), respaldando en memoria si el canal nativo no está
/// montado durante pruebas unitarias.
class PreferenciasService {
  PreferenciasService([SharedPreferencesAsync? prefs])
      : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const _claveTemaOscuro = 'tema_oscuro';
  static const _claveRecibirAlertas = 'recibir_alertas_semaforo';
  static const _claveBorradorObservaciones = 'borrador_observaciones_informe';

  bool _temaOscuroMemoria = false;
  bool _recibirAlertasMemoria = true;
  String _borradorMemoria = '';

  /// Lee si el modo oscuro fue activado por el usuario.
  Future<bool> obtenerTemaOscuro() async {
    try {
      final valor = await _prefs.getBool(_claveTemaOscuro);
      if (valor != null) {
        _temaOscuroMemoria = valor;
      }
    } catch (_) {}
    return _temaOscuroMemoria;
  }

  /// Persiste la elección del modo oscuro en `SharedPreferencesAsync`.
  Future<void> guardarTemaOscuro({required bool oscuro}) async {
    _temaOscuroMemoria = oscuro;
    try {
      await _prefs.setBool(_claveTemaOscuro, oscuro);
    } catch (_) {}
  }

  /// Lee si las alertas proactivas de semáforo están habilitadas.
  Future<bool> obtenerRecibirAlertas() async {
    try {
      final valor = await _prefs.getBool(_claveRecibirAlertas);
      if (valor != null) {
        _recibirAlertasMemoria = valor;
      }
    } catch (_) {}
    return _recibirAlertasMemoria;
  }

  /// Persiste la preferencia de recibir alertas de semáforo.
  Future<void> guardarRecibirAlertas({required bool activo}) async {
    _recibirAlertasMemoria = activo;
    try {
      await _prefs.setBool(_claveRecibirAlertas, activo);
    } catch (_) {}
  }

  /// Guarda el borrador del informe cuando la app pasa a segundo plano (`onHide`).
  Future<void> guardarBorradorInforme(String texto) async {
    _borradorMemoria = texto;
    try {
      await _prefs.setString(_claveBorradorObservaciones, texto);
    } catch (_) {}
  }

  /// Recupera el borrador de observaciones guardado previamente.
  Future<String> obtenerBorradorInforme() async {
    try {
      final valor = await _prefs.getString(_claveBorradorObservaciones);
      if (valor != null) {
        _borradorMemoria = valor;
      }
    } catch (_) {}
    return _borradorMemoria;
  }

  /// Limpia únicamente las claves propias usando `allowList`
  Future<void> limpiarPreferenciasDeSesion() async {
    _borradorMemoria = '';
    try {
      await _prefs.clear(
        allowList: {_claveBorradorObservaciones},
      );
    } catch (_) {}
  }
}
