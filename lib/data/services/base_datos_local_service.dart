import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Servicio de base de datos local SQLite (Offline-First) siguiendo
///
/// Recibe un [DatabaseFactory] opcional por constructor para permitir pruebas
/// en memoria y utiliza siempre consultas parametrizadas (`where: '... = ?'` y
/// `whereArgs: [...]`) para evitar inyección SQL.
class BaseDatosLocalService {
  BaseDatosLocalService({DatabaseFactory? fabricaBaseDatos})
      : _fabricaBaseDatos = fabricaBaseDatos;

  final DatabaseFactory? _fabricaBaseDatos;
  Database? _db;
  bool _inicializado = false;
  bool _usarMemoriaFallback = kIsWeb;

  final List<Map<String, dynamic>> _usuariosMemoria = [];
  final List<Map<String, dynamic>> _obrasMemoria = [];
  final List<Map<String, dynamic>> _reportesMemoria = [];
  final List<Map<String, dynamic>> _notificacionesMemoria = [];
  Map<String, dynamic> _configRecordatorioMemoria = {
    'activo': 1,
    'hora': 18,
    'minuto': 0,
  };

  /// Inicializa la base de datos SQLite y asegura las semillas de prueba.
  Future<void> inicializar() async {
    if (_inicializado) return;
    if (!_usarMemoriaFallback) {
      try {
        final fabrica = _fabricaBaseDatos ?? databaseFactory;
        final rutaBases = await fabrica.getDatabasesPath();
        final rutaArchivo = p.join(rutaBases, 'constructora_del_sur_v3.db');
        _db = await fabrica.openDatabase(
          rutaArchivo,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, version) async {
              await _crearTablasSql(db);
              await _insertarSemillasSql(db);
            },
          ),
        );
      } catch (_) {
        // Si el entorno de ejecución es Desktop/Test sin sqflite_common_ffi
        // configurado, opera de forma transparente sobre las tablas en memoria.
        _usarMemoriaFallback = true;
      }
    }

    if (_usarMemoriaFallback && _usuariosMemoria.isEmpty) {
      _cargarSemillasEnMemoria();
    }
    _inicializado = true;
  }

  Future<void> _crearTablasSql(Database db) async {
    await db.execute('''
      CREATE TABLE usuarios (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        rol TEXT NOT NULL,
        nombre TEXT NOT NULL,
        contrasenia TEXT NOT NULL,
        telefono TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE obras (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        estado_semaforo TEXT NOT NULL,
        fecha_ultimo_reporte TEXT NOT NULL,
        responsable_id TEXT NOT NULL,
        responsable_nombre TEXT NOT NULL,
        tareas TEXT NOT NULL,
        materiales TEXT NOT NULL,
        ubicacion TEXT NOT NULL,
        observaciones TEXT NOT NULL,
        con_foto INTEGER NOT NULL DEFAULT 0,
        imagen TEXT,
        finalizada INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE reportes_diarios (
        id TEXT PRIMARY KEY,
        obra_id TEXT NOT NULL,
        obra_nombre TEXT NOT NULL,
        fecha_creacion_local TEXT NOT NULL,
        fecha_sincronizacion TEXT,
        tareas TEXT NOT NULL,
        tarea_completada INTEGER NOT NULL DEFAULT 0,
        materiales TEXT NOT NULL,
        observaciones TEXT NOT NULL,
        url_fotos TEXT NOT NULL,
        estado_semaforo TEXT NOT NULL,
        autor_nombre TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        obra_finalizada INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE notificaciones (
        id TEXT PRIMARY KEY,
        titulo TEXT NOT NULL,
        mensaje TEXT NOT NULL,
        destinatario TEXT NOT NULL,
        fecha_hora TEXT NOT NULL,
        es_alerta_semaforo INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE configuracion_recordatorio (
        id INTEGER PRIMARY KEY,
        activo INTEGER NOT NULL,
        hora INTEGER NOT NULL,
        minuto INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _insertarSemillasSql(Database db) async {
    for (final usuario in _semillasUsuarios()) {
      await db.insert('usuarios', usuario);
    }
    for (final obra in _semillasObras()) {
      await db.insert('obras', obra);
    }
    for (final reporte in _semillasReportes()) {
      await db.insert('reportes_diarios', reporte);
    }
    for (final notificacion in _semillasNotificaciones()) {
      await db.insert('notificaciones', notificacion);
    }
    await db.insert('configuracion_recordatorio', {
      'id': 1,
      'activo': 1,
      'hora': 18,
      'minuto': 0,
    });
  }

  void _cargarSemillasEnMemoria() {
    _usuariosMemoria
      ..clear()
      ..addAll(_semillasUsuarios());
    _obrasMemoria
      ..clear()
      ..addAll(_semillasObras());
    _reportesMemoria
      ..clear()
      ..addAll(_semillasReportes());
    _notificacionesMemoria
      ..clear()
      ..addAll(_semillasNotificaciones());
  }

  /// Obtiene todos los registros crudos de la tabla `usuarios`.
  Future<List<Map<String, dynamic>>> obtenerUsuariosCrudos() async {
    await inicializar();
    if (_usarMemoriaFallback) {
      return List<Map<String, dynamic>>.from(_usuariosMemoria);
    }
    return _db!.query('usuarios');
  }

  /// Actualiza los datos de un usuario en la tabla `usuarios` usando `whereArgs`.
  Future<void> actualizarUsuarioCrudo(Map<String, dynamic> datos) async {
    await inicializar();
    final id = datos['id'] as String;
    if (_usarMemoriaFallback) {
      final indice = _usuariosMemoria.indexWhere((u) => u['id'] == id);
      if (indice != -1) {
        _usuariosMemoria[indice] = Map<String, dynamic>.from(datos);
      }
      return;
    }
    await _db!.update('usuarios', datos, where: 'id = ?', whereArgs: [id]);
  }

  /// Obtiene todos los registros crudos de la tabla `obras`.
  Future<List<Map<String, dynamic>>> obtenerObrasCrudas() async {
    await inicializar();
    if (_usarMemoriaFallback) {
      return List<Map<String, dynamic>>.from(_obrasMemoria);
    }
    return _db!.query('obras');
  }

  /// Inserta o reemplaza una obra en la tabla `obras`.
  Future<void> guardarObraCruda(Map<String, dynamic> obraMap) async {
    await inicializar();
    final id = obraMap['id'] as String;
    if (_usarMemoriaFallback) {
      final indice = _obrasMemoria.indexWhere((o) => o['id'] == id);
      if (indice == -1) {
        _obrasMemoria.add(Map<String, dynamic>.from(obraMap));
      } else {
        _obrasMemoria[indice] = Map<String, dynamic>.from(obraMap);
      }
      return;
    }
    await _db!.insert(
      'obras',
      obraMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Obtiene todos los registros de la tabla `reportes_diarios` ordenados del
  /// más reciente al más antiguo.
  Future<List<Map<String, dynamic>>> obtenerReportesCrudos() async {
    await inicializar();
    if (_usarMemoriaFallback) {
      final copia = List<Map<String, dynamic>>.from(_reportesMemoria);
      copia.sort(
        (a, b) => (b['fecha_creacion_local'] as String)
            .compareTo(a['fecha_creacion_local'] as String),
      );
      return copia;
    }
    return _db!.query(
      'reportes_diarios',
      orderBy: 'fecha_creacion_local DESC',
    );
  }

  /// Inserta o actualiza un reporte diario en `reportes_diarios`.
  Future<void> guardarReporteCrudo(Map<String, dynamic> reporteMap) async {
    await inicializar();
    final id = reporteMap['id'] as String;
    if (_usarMemoriaFallback) {
      final indice = _reportesMemoria.indexWhere((r) => r['id'] == id);
      if (indice == -1) {
        _reportesMemoria.insert(0, Map<String, dynamic>.from(reporteMap));
      } else {
        _reportesMemoria[indice] = Map<String, dynamic>.from(reporteMap);
      }
      return;
    }
    await _db!.insert(
      'reportes_diarios',
      reporteMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Marca todos los reportes con `sync_status = 'pending'` como `'synced'`.
  Future<int> marcarReportesComoSincronizados(DateTime fechaSync) async {
    await inicializar();
    final isoFecha = fechaSync.toIso8601String();
    if (_usarMemoriaFallback) {
      var actualizados = 0;
      for (var i = 0; i < _reportesMemoria.length; i++) {
        if (_reportesMemoria[i]['sync_status'] == 'pending') {
          _reportesMemoria[i] = {
            ..._reportesMemoria[i],
            'sync_status': 'synced',
            'fecha_sincronizacion': isoFecha,
          };
          actualizados++;
        }
      }
      return actualizados;
    }
    return _db!.update(
      'reportes_diarios',
      {
        'sync_status': 'synced',
        'fecha_sincronizacion': isoFecha,
      },
      where: 'sync_status = ?',
      whereArgs: ['pending'],
    );
  }

  /// Obtiene el historial de notificaciones emitidas.
  Future<List<Map<String, dynamic>>> obtenerNotificacionesCrudas() async {
    await inicializar();
    if (_usarMemoriaFallback) {
      final copia = List<Map<String, dynamic>>.from(_notificacionesMemoria);
      copia.sort(
        (a, b) =>
            (b['fecha_hora'] as String).compareTo(a['fecha_hora'] as String),
      );
      return copia;
    }
    return _db!.query('notificaciones', orderBy: 'fecha_hora DESC');
  }

  /// Registra una nueva notificación en la base local.
  Future<void> guardarNotificacionCruda(Map<String, dynamic> notifMap) async {
    await inicializar();
    if (_usarMemoriaFallback) {
      _notificacionesMemoria.insert(0, Map<String, dynamic>.from(notifMap));
      return;
    }
    await _db!.insert(
      'notificaciones',
      notifMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Obtiene la configuración del recordatorio diario de sincronización.
  Future<Map<String, dynamic>> obtenerConfiguracionRecordatorio() async {
    await inicializar();
    if (_usarMemoriaFallback) {
      return Map<String, dynamic>.from(_configRecordatorioMemoria);
    }
    final filas = await _db!.query('configuracion_recordatorio', limit: 1);
    if (filas.isEmpty) {
      return {'activo': 1, 'hora': 18, 'minuto': 0};
    }
    return filas.first;
  }

  /// Actualiza el horario del recordatorio diario de sincronización.
  Future<void> guardarConfiguracionRecordatorio({
    required bool activo,
    required int hora,
    required int minuto,
  }) async {
    await inicializar();
    final valores = {
      'id': 1,
      'activo': activo ? 1 : 0,
      'hora': hora,
      'minuto': minuto,
    };
    if (_usarMemoriaFallback) {
      _configRecordatorioMemoria = valores;
      return;
    }
    await _db!.insert(
      'configuracion_recordatorio',
      valores,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Cierra la conexión SQLite cuando ya no se utiliza
  Future<void> cerrar() async {
    await _db?.close();
    _db = null;
    _inicializado = false;
  }

  /// 3 usuarios de prueba en la base de datos local con cada rol requerido.
  List<Map<String, dynamic>> _semillasUsuarios() => [
        {
          'id': 'u_ingeniero',
          'username': 'ingeniero',
          'rol': 'ingeniero',
          'nombre': 'Ing. Braulio Hormigón',
          'contrasenia': '1234',
          'telefono': '+54 9 261 555-0101',
        },
        {
          'id': 'u_capataz',
          'username': 'capataz',
          'rol': 'capataz',
          'nombre': 'Carlos Méndez (Capataz)',
          'contrasenia': '1234',
          'telefono': '+54 9 261 555-0102',
        },
        {
          'id': 'u_duenio',
          'username': 'dueno',
          'rol': 'duenio',
          'nombre': 'Roberto Del Sur (Dueño)',
          'contrasenia': '1234',
          'telefono': '+54 9 261 555-0100',
        },
      ];

  /// Las 6 obras activas iniciales con tareas, materiales, responsable y ubicación.
  List<Map<String, dynamic>> _semillasObras() => [
        {
          'id': '1',
          'nombre': 'Torre Residencial Las Heras',
          'estado_semaforo': 'problemas',
          'fecha_ultimo_reporte':
              DateTime(2026, 9, 18, 16, 30).toIso8601String(),
          'responsable_id': 'u_capataz',
          'responsable_nombre': 'Carlos Méndez (Capataz)',
          'tareas': jsonEncode([
            {
              'id': 't1_1',
              'nombre': 'Replanteo y excavación de bases',
              'completada': true,
            },
            {
              'id': 't1_2',
              'nombre': 'Losa de planta alta',
              'completada': false,
            },
            {
              'id': 't1_3',
              'nombre': 'Columnas de hormigón piso 2',
              'completada': false,
            },
          ]),
          'materiales': jsonEncode([
            'Hormigón H-21',
            'Hierro nervado 12mm',
            'Alambre negro recocido',
            'Madera para encofrado',
          ]),
          'ubicacion': jsonEncode({
            'latitud': -32.8489,
            'longitud': -68.8392,
            'direccion': 'Av. San Martín 1450, Las Heras, Mendoza',
          }),
          'observaciones':
              'Faltó hormigón el martes. Proveedor reprogramó entrega.',
          'con_foto': 1,
          'imagen': 'assets/images/obra1.png',
          'finalizada': 0,
        },
        {
          'id': '2',
          'nombre': 'Complejo Comercial Belgrano',
          'estado_semaforo': 'aTiempo',
          'fecha_ultimo_reporte':
              DateTime(2026, 9, 18, 17, 15).toIso8601String(),
          'responsable_id': 'u_capataz',
          'responsable_nombre': 'Carlos Méndez (Capataz)',
          'tareas': jsonEncode([
            {
              'id': 't2_1',
              'nombre': 'Fundaciones y encadenado inferior',
              'completada': true,
            },
            {'id': 't2_2', 'nombre': 'Mampostería piso 1', 'completada': true},
            {
              'id': 't2_3',
              'nombre': 'Revocado grueso interior',
              'completada': true,
            },
            {'id': 't2_4', 'nombre': 'Mampostería piso 2', 'completada': true},
            {
              'id': 't2_5',
              'nombre': 'Colocación de aberturas de aluminio',
              'completada': false,
            },
          ]),
          'materiales': jsonEncode([
            'Ladrillón cerámico 18x18x33',
            'Cemento Portland',
            'Cal hidráulica',
            'Arena gruesa',
          ]),
          'ubicacion': jsonEncode({
            'latitud': -32.8895,
            'longitud': -68.8458,
            'direccion': 'Av. Belgrano 820, Ciudad de Mendoza',
          }),
          'observaciones':
              'Sin novedades. Cuadrilla trabajando a ritmo completo.',
          'con_foto': 1,
          'imagen': 'assets/images/obra2.png',
          'finalizada': 0,
        },
        {
          'id': '3',
          'nombre': 'Nave Industrial Parque Sur',
          'estado_semaforo': 'demorada',
          'fecha_ultimo_reporte':
              DateTime(2026, 9, 17, 18, 0).toIso8601String(),
          'responsable_id': 'u_capataz',
          'responsable_nombre': 'Carlos Méndez (Capataz)',
          'tareas': jsonEncode([
            {
              'id': 't3_1',
              'nombre': 'Nivelación y compactación de suelo',
              'completada': true,
            },
            {
              'id': 't3_2',
              'nombre': 'Montaje de cabreadas metálicas',
              'completada': true,
            },
            {
              'id': 't3_3',
              'nombre': 'Instalación eléctrica trifásica',
              'completada': false,
            },
            {
              'id': 't3_4',
              'nombre': 'Piso industrial alisado',
              'completada': false,
            },
          ]),
          'materiales': jsonEncode([
            'Cable subterráneo 4x16mm',
            'Bandejas portacables galvanizadas',
            'Tablero estanco IP65',
            'Jabalina de puesta a tierra',
          ]),
          'ubicacion': jsonEncode({
            'latitud': -32.9254,
            'longitud': -68.8130,
            'direccion': 'Carril Rodríguez Peña 2300, Godoy Cruz, Mendoza',
          }),
          'observaciones': 'Lluvia, se perdieron dos días en tendido exterior.',
          'con_foto': 0,
          'imagen': 'assets/images/obra3.png',
          'finalizada': 0,
        },
        {
          'id': '4',
          'nombre': 'Edificio Mirador del Parque',
          'estado_semaforo': 'demorada',
          'fecha_ultimo_reporte':
              DateTime(2026, 9, 17, 15, 20).toIso8601String(),
          'responsable_id': 'u_capataz',
          'responsable_nombre': 'Carlos Méndez (Capataz)',
          'tareas': jsonEncode([
            {
              'id': 't4_1',
              'nombre': 'Vallado perimetral reglamentario',
              'completada': true,
            },
            {
              'id': 't4_2',
              'nombre': 'Andamios fachada principal',
              'completada': false,
            },
            {
              'id': 't4_3',
              'nombre': 'Revestimiento texturado exterior',
              'completada': false,
            },
          ]),
          'materiales': jsonEncode([
            'Cuerpos de andamio tubular',
            'Tablones metálicos antideslizantes',
            'Revestimiento plástico texturado',
            'Malla de fibra de vidrio',
          ]),
          'ubicacion': jsonEncode({
            'latitud': -32.8930,
            'longitud': -68.8615,
            'direccion': 'Av. Emilio Civit 410, Ciudad de Mendoza',
          }),
          'observaciones':
              'Esperando habilitación municipal para corte parcial de vereda.',
          'con_foto': 0,
          'imagen': 'assets/images/obra4.png',
          'finalizada': 0,
        },
        {
          'id': '5',
          'nombre': 'Barrio Privado Los Olivos',
          'estado_semaforo': 'aTiempo',
          'fecha_ultimo_reporte':
              DateTime(2026, 9, 18, 14, 10).toIso8601String(),
          'responsable_id': 'u_ingeniero',
          'responsable_nombre': 'Ing. Braulio Hormigón',
          'tareas': jsonEncode([
            {
              'id': 't5_1',
              'nombre': 'Movimiento de suelo y apertura de calles',
              'completada': true,
            },
            {
              'id': 't5_2',
              'nombre': 'Red de agua potable y cloacas',
              'completada': true,
            },
            {
              'id': 't5_3',
              'nombre': 'Estructura de hormigón pórtico acceso',
              'completada': false,
            },
          ]),
          'materiales': jsonEncode([
            'Hormigón elaborado H-25',
            'Malla electrosoldada Q188',
            'Caño PVC 110mm',
          ]),
          'ubicacion': jsonEncode({
            'latitud': -32.9612,
            'longitud': -68.8540,
            'direccion': 'Ruta Panamericana Km 12, Luján de Cuyo, Mendoza',
          }),
          'observaciones': 'Avance normal según cronograma semanal.',
          'con_foto': 0,
          'imagen': 'assets/images/obra5.png',
          'finalizada': 0,
        },
        {
          'id': '6',
          'nombre': 'Centro Logístico Ruta 40',
          'estado_semaforo': 'aTiempo',
          'fecha_ultimo_reporte':
              DateTime(2026, 9, 19, 11, 45).toIso8601String(),
          'responsable_id': 'u_ingeniero',
          'responsable_nombre': 'Ing. Braulio Hormigón',
          'tareas': jsonEncode([
            {
              'id': 't6_1',
              'nombre': 'Platea de fundación sector A',
              'completada': true,
            },
            {
              'id': 't6_2',
              'nombre': 'Encofrado de columnas perimetrales',
              'completada': false,
            },
            {
              'id': 't6_3',
              'nombre': 'Vigas de encadenado superior',
              'completada': false,
            },
            {
              'id': 't6_4',
              'nombre': 'Cubierta metálica parabólica',
              'completada': false,
            },
            {
              'id': 't6_5',
              'nombre': 'Dársenas de carga y descarga',
              'completada': false,
            },
          ]),
          'materiales': jsonEncode([
            'Fenólico 18mm para encofrado',
            'Puntales telescópicos metálicos',
            'Desmoldante líquido',
            'Hierro 16mm',
          ]),
          'ubicacion': jsonEncode({
            'latitud': -32.8150,
            'longitud': -68.8210,
            'direccion': 'Ruta Nacional 40 Km 3295, Las Heras, Mendoza',
          }),
          'observaciones': 'Inicio de encofrado en sector norte.',
          'con_foto': 0,
          'imagen': 'assets/images/obra6.png',
          'finalizada': 0,
        },
      ];

  /// Reportes diarios iniciales para consulta de historial y exportación SIGO.
  List<Map<String, dynamic>> _semillasReportes() => [
        {
          'id': 'rep_101',
          'obra_id': '1',
          'obra_nombre': 'Torre Residencial Las Heras',
          'fecha_creacion_local':
              DateTime(2026, 9, 18, 16, 30).toIso8601String(),
          'fecha_sincronizacion':
              DateTime(2026, 9, 18, 18, 0).toIso8601String(),
          'tareas': 'Losa de planta alta',
          'tarea_completada': 0,
          'materiales': jsonEncode([
            'Hierro nervado 12mm',
            'Madera para encofrado',
          ]),
          'observaciones':
              'Faltó hormigón el martes. Proveedor reprogramó entrega.',
          'url_fotos': jsonEncode([
            {
              'rutaLocal': 'assets/images/obra1.png',
              'origen': 'Cámara (Comprimida)',
              'anchoPx': 800,
              'altoPx': 600,
              'calidadPct': 70,
              'pesoKb': 142,
            },
          ]),
          'estado_semaforo': 'problemas',
          'autor_nombre': 'Carlos Méndez (Capataz)',
          'sync_status': 'synced',
          'obra_finalizada': 0,
        },
        {
          'id': 'rep_102',
          'obra_id': '2',
          'obra_nombre': 'Complejo Comercial Belgrano',
          'fecha_creacion_local':
              DateTime(2026, 9, 18, 17, 15).toIso8601String(),
          'fecha_sincronizacion':
              DateTime(2026, 9, 18, 18, 0).toIso8601String(),
          'tareas': 'Mampostería piso 2',
          'tarea_completada': 1,
          'materiales': jsonEncode([
            'Ladrillón cerámico 18x18x33',
            'Cemento Portland',
            'Arena gruesa',
          ]),
          'observaciones':
              'Sin novedades. Se completó el cerramiento del piso 2.',
          'url_fotos': jsonEncode([
            {
              'rutaLocal': 'assets/images/obra2.png',
              'origen': 'Cámara (Comprimida)',
              'anchoPx': 800,
              'altoPx': 600,
              'calidadPct': 70,
              'pesoKb': 158,
            },
          ]),
          'estado_semaforo': 'aTiempo',
          'autor_nombre': 'Carlos Méndez (Capataz)',
          'sync_status': 'synced',
          'obra_finalizada': 0,
        },
        {
          'id': 'rep_103',
          'obra_id': '3',
          'obra_nombre': 'Nave Industrial Parque Sur',
          'fecha_creacion_local':
              DateTime(2026, 9, 17, 18, 0).toIso8601String(),
          'fecha_sincronizacion': null,
          'tareas': 'Instalación eléctrica trifásica',
          'tarea_completada': 0,
          'materiales': jsonEncode(['Bandejas portacables galvanizadas']),
          'observaciones': 'Lluvia, se perdieron dos días en tendido exterior.',
          'url_fotos': jsonEncode([]),
          'estado_semaforo': 'demorada',
          'autor_nombre': 'Carlos Méndez (Capataz)',
          'sync_status': 'pending',
          'obra_finalizada': 0,
        },
      ];

  List<Map<String, dynamic>> _semillasNotificaciones() => [
        {
          'id': 'notif_1',
          'titulo': 'Alerta Roja: Torre Residencial Las Heras',
          'mensaje':
              'La obra pasó a estado "Con problemas" (Rojo). Motivo: Faltó hormigón el martes.',
          'destinatario': 'Ing. Braulio Hormigón / Roberto Del Sur (Dueño)',
          'fecha_hora': DateTime(2026, 9, 18, 16, 31).toIso8601String(),
          'es_alerta_semaforo': 1,
        },
        {
          'id': 'notif_2',
          'titulo': 'Alerta Amarilla: Nave Industrial Parque Sur',
          'mensaje':
              'La obra pasó a estado "Demorada" (Amarillo). Motivo: Lluvia, se perdieron dos días.',
          'destinatario': 'Ing. Braulio Hormigón / Roberto Del Sur (Dueño)',
          'fecha_hora': DateTime(2026, 9, 17, 18, 1).toIso8601String(),
          'es_alerta_semaforo': 1,
        },
      ];
}
