import 'package:shared_preferences/shared_preferences.dart';

/// Copia liviana en `SharedPreferencesAsync` del recordatorio diario efectivo
/// programado en el dispositivo actual (para evitar reprogramaciones redundantes
/// y disponer del último horario local incluso antes de leer SQLite).
class RecordatorioLocalPreferencias {
  const RecordatorioLocalPreferencias({
    required this.activo,
    required this.hora,
    required this.minuto,
    this.nombreBaseDatos,
  });

  final bool activo;
  final int hora;
  final int minuto;
  final String? nombreBaseDatos;
}

/// Servicio que encapsula `SharedPreferencesAsync`.
///
/// Centraliza las claves como constantes privadas y expone métodos con nombres
/// del dominio (`obtenerTemaOscuro`, `guardarTemaOscuro`, `guardarBorradorInforme`,
/// `obtenerUsuarioSesionId`, `guardarRecordatorioLocal`,
/// `limpiarPreferenciasDeSesion`), respaldando en memoria si el canal nativo
/// no está montado durante pruebas unitarias.
class PreferenciasService {
  PreferenciasService([SharedPreferencesAsync? prefs]) : _prefs = prefs;

  SharedPreferencesAsync? _prefs;

  static const _claveTemaOscuro = 'tema_oscuro';
  static const _claveRecibirAlertas = 'recibir_alertas_semaforo';
  static const _claveBorradorObservaciones = 'borrador_observaciones_informe';
  static const _claveUsuarioSesionId = 'usuario_sesion_id';
  static const _claveRecordatorioActivo = 'recordatorio_sync_activo';
  static const _claveRecordatorioHora = 'recordatorio_sync_hora';
  static const _claveRecordatorioMinuto = 'recordatorio_sync_minuto';
  static const _claveRecordatorioDb = 'recordatorio_sync_db';

  bool _temaOscuroMemoria = false;
  bool _recibirAlertasMemoria = true;
  String _borradorMemoria = '';
  String? _usuarioSesionIdMemoria;
  RecordatorioLocalPreferencias _recordatorioLocalMemoria =
      const RecordatorioLocalPreferencias(activo: false, hora: 18, minuto: 0);

  SharedPreferencesAsync? _obtenerPrefs() {
    if (_prefs != null) return _prefs;
    try {
      _prefs = SharedPreferencesAsync();
      return _prefs;
    } catch (_) {
      return null;
    }
  }

  /// Lee si el modo oscuro fue activado por el usuario.
  Future<bool> obtenerTemaOscuro() async {
    try {
      final valor = await _obtenerPrefs()?.getBool(_claveTemaOscuro);
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
      await _obtenerPrefs()?.setBool(_claveTemaOscuro, oscuro);
    } catch (_) {}
  }

  /// Lee si las alertas proactivas de semáforo están habilitadas.
  Future<bool> obtenerRecibirAlertas() async {
    try {
      final valor = await _obtenerPrefs()?.getBool(_claveRecibirAlertas);
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
      await _obtenerPrefs()?.setBool(_claveRecibirAlertas, activo);
    } catch (_) {}
  }

  /// Guarda el borrador del informe cuando la app pasa a segundo plano (`onHide`).
  Future<void> guardarBorradorInforme(String texto) async {
    _borradorMemoria = texto;
    try {
      await _obtenerPrefs()?.setString(_claveBorradorObservaciones, texto);
    } catch (_) {}
  }

  /// Recupera el borrador de observaciones guardado previamente.
  Future<String> obtenerBorradorInforme() async {
    try {
      final valor = await _obtenerPrefs()?.getString(
        _claveBorradorObservaciones,
      );
      if (valor != null) {
        _borradorMemoria = valor;
      }
    } catch (_) {}
    return _borradorMemoria;
  }

  /// Persiste el identificador de sesión local para arrancar offline sin login.
  Future<void> guardarUsuarioSesionId(String? usuarioId) async {
    _usuarioSesionIdMemoria = usuarioId;
    try {
      final prefs = _obtenerPrefs();
      if (prefs == null) return;
      if (usuarioId == null || usuarioId.isEmpty) {
        await prefs.remove(_claveUsuarioSesionId);
      } else {
        await prefs.setString(_claveUsuarioSesionId, usuarioId);
      }
    } catch (_) {}
  }

  /// Recupera el identificador del usuario con sesión offline persistida.
  Future<String?> obtenerUsuarioSesionId() async {
    try {
      final valor = await _obtenerPrefs()?.getString(_claveUsuarioSesionId);
      if (valor != null && valor.isNotEmpty) {
        _usuarioSesionIdMemoria = valor;
      }
    } catch (_) {}
    return _usuarioSesionIdMemoria;
  }

  /// Persiste la copia local del recordatorio diario efectivo programado en
  /// este dispositivo (`activo`, `hora`, `minuto` y nombre de BD activa).
  Future<void> guardarRecordatorioLocal({
    required bool activo,
    required int hora,
    required int minuto,
    String? nombreBaseDatos,
  }) async {
    _recordatorioLocalMemoria = RecordatorioLocalPreferencias(
      activo: activo,
      hora: hora,
      minuto: minuto,
      nombreBaseDatos: nombreBaseDatos,
    );
    try {
      final prefs = _obtenerPrefs();
      if (prefs == null) return;
      await prefs.setBool(_claveRecordatorioActivo, activo);
      await prefs.setInt(_claveRecordatorioHora, hora);
      await prefs.setInt(_claveRecordatorioMinuto, minuto);
      if (nombreBaseDatos != null && nombreBaseDatos.isNotEmpty) {
        await prefs.setString(_claveRecordatorioDb, nombreBaseDatos);
      } else {
        await prefs.remove(_claveRecordatorioDb);
      }
    } catch (_) {}
  }

  /// Lee la última copia del recordatorio diario persistida en `SharedPreferencesAsync`.
  Future<RecordatorioLocalPreferencias> obtenerRecordatorioLocal() async {
    try {
      final prefs = _obtenerPrefs();
      if (prefs != null) {
        final activo = await prefs.getBool(_claveRecordatorioActivo);
        final hora = await prefs.getInt(_claveRecordatorioHora);
        final minuto = await prefs.getInt(_claveRecordatorioMinuto);
        final db = await prefs.getString(_claveRecordatorioDb);
        if (activo != null || hora != null || minuto != null || db != null) {
          _recordatorioLocalMemoria = RecordatorioLocalPreferencias(
            activo: activo ?? _recordatorioLocalMemoria.activo,
            hora: hora ?? _recordatorioLocalMemoria.hora,
            minuto: minuto ?? _recordatorioLocalMemoria.minuto,
            nombreBaseDatos: db ?? _recordatorioLocalMemoria.nombreBaseDatos,
          );
        }
      }
    } catch (_) {}
    return _recordatorioLocalMemoria;
  }

  /// Limpia únicamente las claves propias de sesión usando `allowList`.
  Future<void> limpiarPreferenciasDeSesion() async {
    _borradorMemoria = '';
    _usuarioSesionIdMemoria = null;
    _recordatorioLocalMemoria = const RecordatorioLocalPreferencias(
      activo: false,
      hora: 18,
      minuto: 0,
    );
    try {
      await _obtenerPrefs()?.clear(
        allowList: {
          _claveBorradorObservaciones,
          _claveUsuarioSesionId,
          _claveRecordatorioActivo,
          _claveRecordatorioHora,
          _claveRecordatorioMinuto,
          _claveRecordatorioDb,
        },
      );
    } catch (_) {}
  }
}
