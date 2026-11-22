import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'reloj.dart';

/// Servicio de base de datos local SQLite (Offline-First) normalizada en 3FN.
///
/// Características clave:
/// - Activa `PRAGMA foreign_keys = ON` en cada conexión.
/// - Mantiene migraciones incrementales en `onUpgrade` (`version: 4`) sin
///   perder datos `pending` locales.
/// - Soporta consultas filtradas/paginadas, escrituras granulares por tarea y
///   metadatos de sincronización (`updated_at` UTC, `sync_status`, `deleted_at`,
///   `estado_sincronizacion` y `cola_sincronizacion`).
class BaseDatosLocalService {
  BaseDatosLocalService({
    DatabaseFactory? fabricaBaseDatos,
    Reloj reloj = const RelojDelSistema(),
    bool insertarSemillasDePrueba = true,
    String nombreArchivo = nombreArchivoDb,
    bool instanciaUnica = true,
  })  : _fabricaBaseDatos = fabricaBaseDatos,
        _reloj = reloj,
        _insertarSemillasDePrueba = insertarSemillasDePrueba,
        _nombreArchivo = nombreArchivo,
        _instanciaUnica = instanciaUnica;

  static const nombreArchivoDb = 'constructora_del_sur_v4.db';
  static const nombreArchivoSupabase = 'constructora_del_sur_supabase.db';
  static const versionEsquema = 4;

  final DatabaseFactory? _fabricaBaseDatos;
  final Reloj _reloj;
  final bool _insertarSemillasDePrueba;
  final String _nombreArchivo;
  final bool _instanciaUnica;

  Database? _db;
  bool _inicializado = false;
  bool _usarMemoriaFallback = kIsWeb;
  Future<void>? _inicializacionEnCurso;

  final List<Map<String, dynamic>> _rolesMemoria = [];
  final List<Map<String, dynamic>> _usuariosMemoria = [];
  final List<Map<String, dynamic>> _obrasMemoria = [];
  final List<Map<String, dynamic>> _tareasObraMemoria = [];
  final List<Map<String, dynamic>> _obraMaterialesMemoria = [];
  final List<Map<String, dynamic>> _reportesMemoria = [];
  final List<Map<String, dynamic>> _reporteMaterialesMemoria = [];
  final List<Map<String, dynamic>> _reporteFotosMemoria = [];
  final List<Map<String, dynamic>> _notificacionesMemoria = [];
  final List<Map<String, dynamic>> _plantillasMemoria = [];
  final List<Map<String, dynamic>> _colaSyncMemoria = [];
  String? _ultimaSyncUtcMemoria;
  Map<String, dynamic> _configRecordatorioMemoria = {
    'id': 1,
    'activo': 1,
    'hora': 18,
    'minuto': 0,
  };

  String _ahoraUtcIso() => _reloj.ahora().toUtc().toIso8601String();

  /// Inicializa la base de datos SQLite con claves foráneas activas y migraciones.
  ///
  /// Reabre automáticamente la conexión si fue cerrada externamente (por ejemplo,
  /// tras un Hot Restart o una tarea concurrente) y serializa aperturas paralelas.
  Future<void> inicializar() async {
    if (_inicializado &&
        (_usarMemoriaFallback || (_db != null && _db!.isOpen))) {
      return;
    }

    final enCurso = _inicializacionEnCurso;
    if (enCurso != null) {
      await enCurso;
      if (_inicializado &&
          (_usarMemoriaFallback || (_db != null && _db!.isOpen))) {
        return;
      }
    }

    final futuro = _abrirBaseDatos();
    _inicializacionEnCurso = futuro;
    try {
      await futuro;
    } finally {
      if (identical(_inicializacionEnCurso, futuro)) {
        _inicializacionEnCurso = null;
      }
    }
  }

  Future<void> _abrirBaseDatos() async {
    if (_db != null && !_db!.isOpen) {
      _db = null;
      _inicializado = false;
    }

    if (!_usarMemoriaFallback) {
      try {
        final fabrica = _fabricaBaseDatos ?? databaseFactory;
        final rutaBases = await fabrica.getDatabasesPath();
        final rutaArchivo = p.join(rutaBases, _nombreArchivo);
        _db = await fabrica.openDatabase(
          rutaArchivo,
          options: OpenDatabaseOptions(
            version: versionEsquema,
            singleInstance: _instanciaUnica,
            onConfigure: (db) async {
              await db.execute('PRAGMA foreign_keys = ON');
            },
            onCreate: (db, version) async {
              await _crearTablasSql(db);
              await _crearIndicesSql(db);
              await _insertarCatalogoRolesSql(db);
              if (_insertarSemillasDePrueba) {
                await _insertarSemillasSql(db);
              }
            },
            onUpgrade: (db, oldVersion, newVersion) async {
              if (oldVersion < 2) {
                await _migrarV1AV2(db);
              }
              if (oldVersion < 3) {
                await _migrarV2AV3(db);
              }
              if (oldVersion < 4) {
                await _migrarV3AV4(db);
              }
              await _crearIndicesSql(db);
            },
          ),
        );
      } catch (_) {
        // Si el entorno de ejecución es Desktop/Test sin sqflite_common_ffi
        // configurado, opera de forma transparente sobre las tablas en memoria.
        _usarMemoriaFallback = true;
      }
    }

    if (_usarMemoriaFallback && _rolesMemoria.isEmpty) {
      _rolesMemoria.addAll(_semillasRoles());
      if (_insertarSemillasDePrueba) {
        _cargarSemillasEnMemoria();
      }
    }
    _inicializado = true;
  }

  Future<void> _crearTablasSql(Database db) async {
    await db.execute('''
      CREATE TABLE roles (
        id TEXT PRIMARY KEY,
        codigo TEXT NOT NULL UNIQUE,
        nombre TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE usuarios (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        rol_id TEXT NOT NULL,
        nombre TEXT NOT NULL,
        contrasenia TEXT NOT NULL,
        telefono TEXT NOT NULL DEFAULT '',
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        FOREIGN KEY (rol_id) REFERENCES roles(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE obras (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        estado_semaforo TEXT NOT NULL,
        fecha_ultimo_reporte TEXT NOT NULL,
        responsable_id TEXT NOT NULL,
        ingeniero_id TEXT,
        tarea_actual_id TEXT,
        ubicacion_latitud REAL NOT NULL,
        ubicacion_longitud REAL NOT NULL,
        ubicacion_direccion TEXT NOT NULL,
        observaciones TEXT NOT NULL,
        con_foto INTEGER NOT NULL DEFAULT 0,
        imagen TEXT,
        imagen_url TEXT,
        finalizada INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        deleted_at TEXT,
        FOREIGN KEY (responsable_id) REFERENCES usuarios(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT,
        FOREIGN KEY (ingeniero_id) REFERENCES usuarios(id)
          ON UPDATE CASCADE
          ON DELETE SET NULL,
        FOREIGN KEY (tarea_actual_id) REFERENCES tareas_obra(id)
          ON UPDATE CASCADE
          ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE tareas_obra (
        id TEXT PRIMARY KEY,
        obra_id TEXT NOT NULL,
        nombre TEXT NOT NULL,
        completada INTEGER NOT NULL DEFAULT 0,
        orden INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        FOREIGN KEY (obra_id) REFERENCES obras(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE obra_materiales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        obra_id TEXT NOT NULL,
        nombre TEXT NOT NULL,
        FOREIGN KEY (obra_id) REFERENCES obras(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE reportes_diarios (
        id TEXT PRIMARY KEY,
        obra_id TEXT NOT NULL,
        autor_id TEXT NOT NULL,
        fecha_creacion_local TEXT NOT NULL,
        fecha_sincronizacion TEXT,
        tarea_seleccionada TEXT NOT NULL,
        tarea_completada INTEGER NOT NULL DEFAULT 0,
        observaciones TEXT NOT NULL,
        estado_semaforo TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        obra_finalizada INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (obra_id) REFERENCES obras(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE,
        FOREIGN KEY (autor_id) REFERENCES usuarios(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE reporte_materiales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reporte_id TEXT NOT NULL,
        nombre TEXT NOT NULL,
        FOREIGN KEY (reporte_id) REFERENCES reportes_diarios(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE reporte_fotos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reporte_id TEXT NOT NULL,
        ruta_local TEXT NOT NULL,
        origen TEXT NOT NULL,
        ancho_px INTEGER NOT NULL,
        alto_px INTEGER NOT NULL,
        calidad_pct INTEGER NOT NULL,
        peso_kb INTEGER NOT NULL,
        bytes_base64 TEXT,
        url_remota TEXT,
        estado_subida TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (reporte_id) REFERENCES reportes_diarios(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE notificaciones (
        id TEXT PRIMARY KEY,
        obra_id TEXT,
        titulo TEXT NOT NULL,
        mensaje TEXT NOT NULL,
        destinatario TEXT NOT NULL,
        fecha_hora TEXT NOT NULL,
        es_alerta_semaforo INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        FOREIGN KEY (obra_id) REFERENCES obras(id)
          ON UPDATE CASCADE
          ON DELETE SET NULL
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

    await db.execute('''
      CREATE TABLE estado_sincronizacion (
        id INTEGER PRIMARY KEY,
        ultima_sync_utc TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cola_sincronizacion (
        id TEXT PRIMARY KEY,
        entidad TEXT NOT NULL,
        entidad_id TEXT NOT NULL,
        operacion TEXT NOT NULL,
        reintentos INTEGER NOT NULL DEFAULT 0,
        ultimo_error TEXT,
        creado_en TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_plantillas (
        id TEXT PRIMARY KEY,
        usuario_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        deleted_at TEXT,
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _crearIndicesSql(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_usuarios_rol_id ON usuarios(rol_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_obras_responsable_id '
      'ON obras(responsable_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_obras_ingeniero_id '
      'ON obras(ingeniero_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_obras_tarea_actual_id '
      'ON obras(tarea_actual_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_obras_sync_status ON obras(sync_status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tareas_obra_obra_id '
      'ON tareas_obra(obra_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tareas_obra_sync_status '
      'ON tareas_obra(sync_status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_obra_materiales_obra_id '
      'ON obra_materiales(obra_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reportes_diarios_obra_id '
      'ON reportes_diarios(obra_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reportes_diarios_autor_id '
      'ON reportes_diarios(autor_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reportes_diarios_sync_status '
      'ON reportes_diarios(sync_status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reporte_materiales_reporte_id '
      'ON reporte_materiales(reporte_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reporte_fotos_reporte_id '
      'ON reporte_fotos(reporte_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notificaciones_obra_id '
      'ON notificaciones(obra_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cola_sync_entidad '
      'ON cola_sincronizacion(entidad, entidad_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_catalogo_plantillas_usuario_tipo '
      'ON catalogo_plantillas(usuario_id, tipo)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_catalogo_plantillas_sync_status '
      'ON catalogo_plantillas(sync_status)',
    );
  }

  /// Migración incremental v1 -> v2 preservando los datos locales existentes.
  Future<void> _migrarV1AV2(Database db) async {
    final ahora = _ahoraUtcIso();
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        await txn.execute('''
          CREATE TABLE usuarios_v2 (
            id TEXT PRIMARY KEY,
            username TEXT NOT NULL UNIQUE,
            rol_id TEXT NOT NULL,
            nombre TEXT NOT NULL,
            contrasenia TEXT NOT NULL,
            telefono TEXT NOT NULL DEFAULT '',
            updated_at TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'synced',
            FOREIGN KEY (rol_id) REFERENCES roles(id)
              ON UPDATE CASCADE
              ON DELETE RESTRICT
          )
        ''');
        await txn.execute(
          '''
          INSERT INTO usuarios_v2
            (id, username, rol_id, nombre, contrasenia, telefono, updated_at, sync_status)
          SELECT
            id, username, rol_id, nombre, contrasenia, '', ?, 'synced'
          FROM usuarios
          ''',
          [ahora],
        );
        await txn.execute('DROP TABLE usuarios');
        await txn.execute('ALTER TABLE usuarios_v2 RENAME TO usuarios');

        await txn.execute('ALTER TABLE obras ADD COLUMN imagen_url TEXT');
        await txn.execute(
          "ALTER TABLE obras ADD COLUMN updated_at TEXT NOT NULL DEFAULT '$ahora'",
        );
        await txn.execute(
          "ALTER TABLE obras ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'synced'",
        );
        await txn.execute('ALTER TABLE obras ADD COLUMN deleted_at TEXT');

        await txn.execute(
          "ALTER TABLE tareas_obra ADD COLUMN updated_at TEXT NOT NULL DEFAULT '$ahora'",
        );
        await txn.execute(
          "ALTER TABLE tareas_obra ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'synced'",
        );

        await txn.execute(
          "ALTER TABLE reportes_diarios ADD COLUMN updated_at TEXT NOT NULL DEFAULT '$ahora'",
        );

        await txn.execute(
          'ALTER TABLE reporte_fotos ADD COLUMN url_remota TEXT',
        );
        await txn.execute(
          "ALTER TABLE reporte_fotos ADD COLUMN estado_subida TEXT NOT NULL DEFAULT 'synced'",
        );

        await txn.execute(
          "ALTER TABLE notificaciones ADD COLUMN updated_at TEXT NOT NULL DEFAULT '$ahora'",
        );
        await txn.execute(
          "ALTER TABLE notificaciones ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'synced'",
        );

        await txn.execute('''
          CREATE TABLE IF NOT EXISTS estado_sincronizacion (
            id INTEGER PRIMARY KEY,
            ultima_sync_utc TEXT
          )
        ''');
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS cola_sincronizacion (
            id TEXT PRIMARY KEY,
            entidad TEXT NOT NULL,
            entidad_id TEXT NOT NULL,
            operacion TEXT NOT NULL,
            reintentos INTEGER NOT NULL DEFAULT 0,
            ultimo_error TEXT,
            creado_en TEXT NOT NULL
          )
        ''');
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  /// Migración incremental v2 -> v3: agrega `obras.ingeniero_id` (FK opcional a
  /// `usuarios.id`) para vincular al ingeniero supervisor/creador de cada obra.
  Future<void> _migrarV2AV3(Database db) async {
    await db.execute(
      'ALTER TABLE obras ADD COLUMN ingeniero_id TEXT '
      'REFERENCES usuarios(id) ON UPDATE CASCADE ON DELETE SET NULL',
    );
  }

  /// Migración incremental v3 -> v4: agrega `obras.tarea_actual_id` y la tabla
  /// `catalogo_plantillas` (catálogo individual por ingeniero de tareas y
  /// materiales frecuentes).
  Future<void> _migrarV3AV4(Database db) async {
    await db.execute(
      'ALTER TABLE obras ADD COLUMN tarea_actual_id TEXT '
      'REFERENCES tareas_obra(id) ON UPDATE CASCADE ON DELETE SET NULL',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalogo_plantillas (
        id TEXT PRIMARY KEY,
        usuario_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        nombre TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        deleted_at TEXT,
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _insertarCatalogoRolesSql(Database db) async {
    for (final rol in _semillasRoles()) {
      await db.insert('roles', rol,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await db.insert(
      'configuracion_recordatorio',
      {'id': 1, 'activo': 1, 'hora': 18, 'minuto': 0},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert(
      'estado_sincronizacion',
      {'id': 1, 'ultima_sync_utc': null},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _insertarSemillasSql(Database db) async {
    for (final usuario in _semillasUsuarios()) {
      await db.insert('usuarios', usuario);
    }
    for (final obra in _semillasObras()) {
      await db.insert('obras', obra);
    }
    for (final tarea in _semillasTareasObra()) {
      await db.insert('tareas_obra', tarea);
    }
    for (final material in _semillasObraMateriales()) {
      await db.insert('obra_materiales', material);
    }
    for (final reporte in _semillasReportes()) {
      await db.insert('reportes_diarios', reporte);
    }
    for (final material in _semillasReporteMateriales()) {
      await db.insert('reporte_materiales', material);
    }
    for (final foto in _semillasReporteFotos()) {
      await db.insert('reporte_fotos', foto);
    }
    for (final notificacion in _semillasNotificaciones()) {
      await db.insert('notificaciones', notificacion);
    }
    for (final plantilla in _semillasPlantillas()) {
      await db.insert('catalogo_plantillas', plantilla);
    }
  }

  void _cargarSemillasEnMemoria() {
    _usuariosMemoria
      ..clear()
      ..addAll(_semillasUsuarios());
    _obrasMemoria
      ..clear()
      ..addAll(_semillasObras());
    _tareasObraMemoria
      ..clear()
      ..addAll(_semillasTareasObra());
    _obraMaterialesMemoria
      ..clear()
      ..addAll(_semillasObraMateriales());
    _reportesMemoria
      ..clear()
      ..addAll(_semillasReportes());
    _reporteMaterialesMemoria
      ..clear()
      ..addAll(_semillasReporteMateriales());
    _reporteFotosMemoria
      ..clear()
      ..addAll(_semillasReporteFotos());
    _notificacionesMemoria
      ..clear()
      ..addAll(_semillasNotificaciones());
    _plantillasMemoria
      ..clear()
      ..addAll(_semillasPlantillas());
  }

  /// Obtiene todos los registros crudos de la tabla `roles`.
  Future<List<Map<String, dynamic>>> obtenerRolesCrudos() async {
    await inicializar();
    if (_usarMemoriaFallback) {
      return _rolesMemoria.map(Map<String, dynamic>.from).toList();
    }
    return _db!.query('roles', orderBy: 'id ASC');
  }

  /// Inserta o actualiza un rol en el catálogo `roles`.
  Future<void> guardarRolCrudo(Map<String, dynamic> rol) async {
    await inicializar();
    final id = rol['id'] as String;
    if (_usarMemoriaFallback) {
      final idx = _rolesMemoria.indexWhere((r) => r['id'] == id);
      if (idx == -1) {
        _rolesMemoria.add(Map<String, dynamic>.from(rol));
      } else {
        _rolesMemoria[idx] = Map<String, dynamic>.from(rol);
      }
      return;
    }
    final actualizados = await _db!.update(
      'roles',
      rol,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (actualizados == 0) {
      await _db!.insert('roles', rol);
    }
  }

  /// Obtiene todos los usuarios unidos a su rol (`roles`) en relación 1:N.
  Future<List<Map<String, dynamic>>> obtenerUsuariosCrudos() async {
    await inicializar();
    if (_usarMemoriaFallback) {
      return _usuariosMemoria.map((u) {
        final rol = _buscarRolEnMemoria(u['rol_id'] as String);
        return {
          ...u,
          'rol_codigo': rol?['codigo'],
          'rol_nombre': rol?['nombre'],
        };
      }).toList();
    }
    return _db!.rawQuery('''
      SELECT
        u.id,
        u.username,
        u.rol_id,
        u.nombre,
        u.contrasenia,
        u.telefono,
        u.updated_at,
        u.sync_status,
        r.codigo AS rol_codigo,
        r.nombre AS rol_nombre
      FROM usuarios u
      INNER JOIN roles r ON r.id = u.rol_id
      ORDER BY u.id ASC
    ''');
  }

  /// Inserta o actualiza un usuario en `usuarios` validando FK `rol_id` y
  /// resolviendo colisiones de `username` (apoyado en `ON UPDATE CASCADE`).
  Future<void> guardarUsuarioCrudo(Map<String, dynamic> datos) async {
    await inicializar();
    final id = datos['id'] as String;
    final username = datos['username'] as String;
    final rolId = datos['rol_id'] as String;
    final fila = {
      'telefono': '',
      'updated_at': _ahoraUtcIso(),
      'sync_status': 'pending',
      ...datos,
    };

    if (_usarMemoriaFallback) {
      if (_buscarRolEnMemoria(rolId) == null) {
        throw StateError('Violación de FK: rol_id "$rolId" no existe.');
      }
      var indice = _usuariosMemoria.indexWhere((u) => u['id'] == id);
      if (indice == -1) {
        indice = _usuariosMemoria.indexWhere((u) => u['username'] == username);
      }
      if (indice == -1) {
        _usuariosMemoria.add(Map<String, dynamic>.from(fila));
      } else {
        _usuariosMemoria[indice] = Map<String, dynamic>.from(fila);
      }
      return;
    }

    var actualizados = await _db!.update(
      'usuarios',
      fila,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (actualizados == 0) {
      actualizados = await _db!.update(
        'usuarios',
        fila,
        where: 'username = ?',
        whereArgs: [username],
      );
    }
    if (actualizados == 0) {
      await _db!.insert('usuarios', fila);
    }
  }

  /// Actualiza los datos de un usuario existente en la tabla `usuarios`.
  Future<void> actualizarUsuarioCrudo(Map<String, dynamic> datos) =>
      guardarUsuarioCrudo(datos);

  /// Obtiene las obras activas (no borradas lógicamente), con soporte opcional
  /// de filtro por responsable y paginación (`limite`, `desplazamiento`).
  Future<List<Map<String, dynamic>>> obtenerObrasCrudas({
    int? limite,
    int? desplazamiento,
    String? responsableId,
  }) async {
    await inicializar();
    if (_usarMemoriaFallback) {
      Iterable<Map<String, dynamic>> filtradas = _obrasMemoria.where(
        (o) => o['deleted_at'] == null,
      );
      if (responsableId != null) {
        filtradas =
            filtradas.where((o) => o['responsable_id'] == responsableId);
      }
      var lista = filtradas.toList();
      if (desplazamiento != null && desplazamiento > 0) {
        lista = desplazamiento >= lista.length
            ? <Map<String, dynamic>>[]
            : lista.sublist(desplazamiento);
      }
      if (limite != null && limite < lista.length) {
        lista = lista.sublist(0, limite);
      }

      return lista.map((obra) {
        final obraId = obra['id'] as String;
        final responsable =
            _buscarUsuarioEnMemoria(obra['responsable_id'] as String);
        final ingenieroId = obra['ingeniero_id'] as String?;
        final ingeniero =
            ingenieroId != null ? _buscarUsuarioEnMemoria(ingenieroId) : null;
        final tareas = _tareasObraMemoria
            .where((t) => t['obra_id'] == obraId)
            .toList()
          ..sort((a, b) => (a['orden'] as int).compareTo(b['orden'] as int));
        final materiales = _obraMaterialesMemoria
            .where((m) => m['obra_id'] == obraId)
            .map((m) => m['nombre'] as String)
            .toList();

        return {
          ...obra,
          'responsable_nombre': responsable?['nombre'] ?? 'Capataz',
          'ingeniero_nombre': ingeniero?['nombre'],
          'tareas': tareas.map(Map<String, dynamic>.from).toList(),
          'materiales': materiales,
        };
      }).toList();
    }

    final whereClausulas = <String>['o.deleted_at IS NULL'];
    final args = <Object?>[];
    if (responsableId != null) {
      whereClausulas.add('o.responsable_id = ?');
      args.add(responsableId);
    }

    final paginacion = StringBuffer();
    if (limite != null) {
      paginacion.write(' LIMIT ?');
      args.add(limite);
      if (desplazamiento != null) {
        paginacion.write(' OFFSET ?');
        args.add(desplazamiento);
      }
    }

    final obras = await _db!.rawQuery(
      '''
      SELECT
        o.id,
        o.nombre,
        o.estado_semaforo,
        o.fecha_ultimo_reporte,
        o.responsable_id,
        u.nombre AS responsable_nombre,
        o.ingeniero_id,
        ing.nombre AS ingeniero_nombre,
        o.tarea_actual_id,
        o.ubicacion_latitud,
        o.ubicacion_longitud,
        o.ubicacion_direccion,
        o.observaciones,
        o.con_foto,
        o.imagen,
        o.imagen_url,
        o.finalizada,
        o.updated_at,
        o.sync_status,
        o.deleted_at
      FROM obras o
      INNER JOIN usuarios u ON u.id = o.responsable_id
      LEFT JOIN usuarios ing ON ing.id = o.ingeniero_id
      WHERE ${whereClausulas.join(' AND ')}
      ${paginacion.toString()}
      ''',
      args,
    );

    if (obras.isEmpty) return const [];

    final ids = obras.map((o) => o['id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(', ');

    final tareas = await _db!.query(
      'tareas_obra',
      where: 'obra_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'orden ASC',
    );
    final materiales = await _db!.query(
      'obra_materiales',
      where: 'obra_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'id ASC',
    );

    final tareasPorObra = <String, List<Map<String, dynamic>>>{};
    for (final tarea in tareas) {
      final obraId = tarea['obra_id'] as String;
      tareasPorObra.putIfAbsent(obraId, () => []).add(tarea);
    }

    final materialesPorObra = <String, List<String>>{};
    for (final material in materiales) {
      final obraId = material['obra_id'] as String;
      materialesPorObra
          .putIfAbsent(obraId, () => [])
          .add(material['nombre'] as String);
    }

    return obras.map((obra) {
      final obraId = obra['id'] as String;
      return {
        ...obra,
        'tareas': tareasPorObra[obraId] ?? const <Map<String, dynamic>>[],
        'materiales': materialesPorObra[obraId] ?? const <String>[],
      };
    }).toList();
  }

  /// Inserta o actualiza una obra y sus tablas hijas (`tareas_obra` y
  /// `obra_materiales`) de forma transaccional sin disparar `ON DELETE CASCADE`.
  Future<void> guardarObraCruda({
    required Map<String, dynamic> obra,
    required List<Map<String, dynamic>> tareas,
    required List<String> materiales,
  }) async {
    await inicializar();
    final id = obra['id'] as String;
    final responsableId = obra['responsable_id'] as String;
    final filaObra = {
      'updated_at': _ahoraUtcIso(),
      'sync_status': 'pending',
      ...obra,
    };

    if (_usarMemoriaFallback) {
      if (_buscarUsuarioEnMemoria(responsableId) == null) {
        throw StateError(
          'Violación de FK: responsable_id "$responsableId" no existe.',
        );
      }
      final ingenieroId = obra['ingeniero_id'] as String?;
      if (ingenieroId != null && _buscarUsuarioEnMemoria(ingenieroId) == null) {
        throw StateError(
          'Violación de FK: ingeniero_id "$ingenieroId" no existe.',
        );
      }
      final indice = _obrasMemoria.indexWhere((o) => o['id'] == id);
      if (indice == -1) {
        _obrasMemoria.add(Map<String, dynamic>.from(filaObra));
      } else {
        _obrasMemoria[indice] = Map<String, dynamic>.from(filaObra);
      }
      _tareasObraMemoria.removeWhere((t) => t['obra_id'] == id);
      _tareasObraMemoria.addAll(tareas.map(Map<String, dynamic>.from));
      _obraMaterialesMemoria.removeWhere((m) => m['obra_id'] == id);
      for (final nombreMaterial in materiales) {
        _obraMaterialesMemoria.add({'obra_id': id, 'nombre': nombreMaterial});
      }
      return;
    }

    await _db!.transaction((txn) async {
      final tareaActualId = filaObra['tarea_actual_id'] as String?;
      final filaSinTareaActual = Map<String, dynamic>.from(filaObra)
        ..['tarea_actual_id'] = null;

      final actualizados = await txn.update(
        'obras',
        filaSinTareaActual,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (actualizados == 0) {
        await txn.insert('obras', filaSinTareaActual);
      }

      await txn.delete('tareas_obra', where: 'obra_id = ?', whereArgs: [id]);
      for (final tarea in tareas) {
        await txn.insert('tareas_obra', tarea);
      }

      if (tareaActualId != null &&
          tareas.any((t) => t['id'] == tareaActualId)) {
        await txn.update(
          'obras',
          {'tarea_actual_id': tareaActualId},
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      await txn.delete(
        'obra_materiales',
        where: 'obra_id = ?',
        whereArgs: [id],
      );
      for (final nombreMaterial in materiales) {
        await txn.insert('obra_materiales', {
          'obra_id': id,
          'nombre': nombreMaterial,
        });
      }
    });
  }

  /// Actualiza la tarea actual elegida explícitamente para una obra sin
  /// reescribir tareas ni materiales.
  Future<void> actualizarTareaActualObraCruda({
    required String obraId,
    required String? tareaActualId,
    required DateTime updatedAtUtc,
  }) async {
    await inicializar();
    final valores = <String, dynamic>{
      'tarea_actual_id': tareaActualId,
      'updated_at': updatedAtUtc.toUtc().toIso8601String(),
      'sync_status': 'pending',
    };
    if (_usarMemoriaFallback) {
      final idx = _obrasMemoria.indexWhere((o) => o['id'] == obraId);
      if (idx != -1) {
        _obrasMemoria[idx] = {..._obrasMemoria[idx], ...valores};
      }
      return;
    }
    await _db!.update('obras', valores, where: 'id = ?', whereArgs: [obraId]);
  }

  /// Agrega un material nuevo a una obra en curso evitando duplicados y marca
  /// la obra como `pending` para que se sincronice con Supabase.
  Future<void> agregarMaterialAObraCruda({
    required String obraId,
    required String nombreMaterial,
    required DateTime updatedAtUtc,
  }) async {
    await inicializar();
    final limpio = nombreMaterial.trim();
    if (limpio.isEmpty) return;
    final limpioLower = limpio.toLowerCase();
    final ahoraIso = updatedAtUtc.toUtc().toIso8601String();

    if (_usarMemoriaFallback) {
      if (_buscarObraEnMemoria(obraId) == null) {
        throw StateError('Violación de FK: obra_id "$obraId" no existe.');
      }
      final yaExiste = _obraMaterialesMemoria.any(
        (m) =>
            m['obra_id'] == obraId &&
            (m['nombre'] as String).trim().toLowerCase() == limpioLower,
      );
      if (!yaExiste) {
        _obraMaterialesMemoria.add({'obra_id': obraId, 'nombre': limpio});
      }
      final idx = _obrasMemoria.indexWhere((o) => o['id'] == obraId);
      if (idx != -1) {
        _obrasMemoria[idx] = {
          ..._obrasMemoria[idx],
          'updated_at': ahoraIso,
          'sync_status': 'pending',
        };
      }
      return;
    }

    await _db!.transaction((txn) async {
      final existentes = await txn.query(
        'obra_materiales',
        columns: ['nombre'],
        where: 'obra_id = ?',
        whereArgs: [obraId],
      );
      final yaExiste = existentes.any(
        (m) => (m['nombre'] as String).trim().toLowerCase() == limpioLower,
      );
      if (!yaExiste) {
        await txn.insert('obra_materiales', {
          'obra_id': obraId,
          'nombre': limpio,
        });
      }
      await txn.update(
        'obras',
        {'updated_at': ahoraIso, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: [obraId],
      );
    });
  }

  /// Obtiene las plantillas activas (tareas/materiales frecuentes) del usuario.
  Future<List<Map<String, dynamic>>> obtenerPlantillasCrudas({
    required String usuarioId,
    String? tipo,
  }) async {
    await inicializar();
    if (_usarMemoriaFallback) {
      final filtradas = _plantillasMemoria.where((p) {
        if (p['deleted_at'] != null) return false;
        if (p['usuario_id'] != usuarioId) return false;
        if (tipo != null && p['tipo'] != tipo) return false;
        return true;
      }).toList()
        ..sort(
          (a, b) => (a['nombre'] as String)
              .toLowerCase()
              .compareTo((b['nombre'] as String).toLowerCase()),
        );
      return filtradas.map(Map<String, dynamic>.from).toList();
    }

    final whereClausulas = <String>['usuario_id = ?', 'deleted_at IS NULL'];
    final args = <Object?>[usuarioId];
    if (tipo != null) {
      whereClausulas.add('tipo = ?');
      args.add(tipo);
    }
    return _db!.query(
      'catalogo_plantillas',
      where: whereClausulas.join(' AND '),
      whereArgs: args,
      orderBy: 'LOWER(nombre) ASC',
    );
  }

  /// Inserta o actualiza una plantilla en `catalogo_plantillas`.
  Future<void> guardarPlantillaCruda(Map<String, dynamic> plantilla) async {
    await inicializar();
    final id = plantilla['id'] as String;
    final usuarioId = plantilla['usuario_id'] as String;
    final fila = {
      'updated_at': _ahoraUtcIso(),
      'sync_status': 'pending',
      ...plantilla,
    };

    if (_usarMemoriaFallback) {
      if (_buscarUsuarioEnMemoria(usuarioId) == null) {
        throw StateError('Violación de FK: usuario_id "$usuarioId" no existe.');
      }
      final idx = _plantillasMemoria.indexWhere((p) => p['id'] == id);
      if (idx == -1) {
        _plantillasMemoria.add(Map<String, dynamic>.from(fila));
      } else {
        _plantillasMemoria[idx] = Map<String, dynamic>.from(fila);
      }
      return;
    }

    final actualizados = await _db!.update(
      'catalogo_plantillas',
      fila,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (actualizados == 0) {
      await _db!.insert('catalogo_plantillas', fila);
    }
  }

  /// Marca una plantilla como eliminada lógicamente (`deleted_at`) para
  /// sincronizar su borrado con Supabase sin afectar obras ya creadas.
  Future<void> eliminarPlantillaCruda({
    required String id,
    required DateTime deletedAtUtc,
  }) async {
    await inicializar();
    final iso = deletedAtUtc.toUtc().toIso8601String();
    final valores = {
      'deleted_at': iso,
      'updated_at': iso,
      'sync_status': 'pending',
    };
    if (_usarMemoriaFallback) {
      final idx = _plantillasMemoria.indexWhere((p) => p['id'] == id);
      if (idx != -1) {
        _plantillasMemoria[idx] = {..._plantillasMemoria[idx], ...valores};
      }
      return;
    }
    await _db!.update(
      'catalogo_plantillas',
      valores,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Actualiza únicamente el semáforo y la fecha del último reporte de una obra
  /// sin reescribir `tareas_obra` ni `obra_materiales`.
  Future<void> actualizarSemaforoObraCruda({
    required String obraId,
    required String estadoSemaforo,
    required DateTime fechaUltimoReporteUtc,
    required DateTime updatedAtUtc,
  }) async {
    await inicializar();
    final valores = {
      'estado_semaforo': estadoSemaforo,
      'fecha_ultimo_reporte': fechaUltimoReporteUtc.toUtc().toIso8601String(),
      'updated_at': updatedAtUtc.toUtc().toIso8601String(),
      'sync_status': 'pending',
    };
    if (_usarMemoriaFallback) {
      final idx = _obrasMemoria.indexWhere((o) => o['id'] == obraId);
      if (idx != -1) {
        _obrasMemoria[idx] = {..._obrasMemoria[idx], ...valores};
      }
      return;
    }
    await _db!.update('obras', valores, where: 'id = ?', whereArgs: [obraId]);
  }

  /// Inserta una sola tarea en `tareas_obra` sin reescribir la obra entera.
  Future<void> insertarTareaCruda(Map<String, dynamic> tarea) async {
    await inicializar();
    final obraId = tarea['obra_id'] as String;
    final fila = {
      'updated_at': _ahoraUtcIso(),
      'sync_status': 'pending',
      ...tarea,
    };
    if (_usarMemoriaFallback) {
      if (_buscarObraEnMemoria(obraId) == null) {
        throw StateError('Violación de FK: obra_id "$obraId" no existe.');
      }
      final idx = _tareasObraMemoria.indexWhere((t) => t['id'] == fila['id']);
      if (idx == -1) {
        _tareasObraMemoria.add(Map<String, dynamic>.from(fila));
      } else {
        _tareasObraMemoria[idx] = Map<String, dynamic>.from(fila);
      }
      return;
    }
    final actualizados = await _db!.update(
      'tareas_obra',
      fila,
      where: 'id = ?',
      whereArgs: [fila['id']],
    );
    if (actualizados == 0) {
      await _db!.insert('tareas_obra', fila);
    }
  }

  /// Actualiza atómicamente el estado de completitud de una sola tarea.
  Future<void> actualizarEstadoTareaCruda({
    required String tareaId,
    required bool completada,
    required DateTime updatedAtUtc,
  }) async {
    await inicializar();
    final valores = {
      'completada': completada ? 1 : 0,
      'updated_at': updatedAtUtc.toUtc().toIso8601String(),
      'sync_status': 'pending',
    };
    if (_usarMemoriaFallback) {
      final idx = _tareasObraMemoria.indexWhere((t) => t['id'] == tareaId);
      if (idx != -1) {
        _tareasObraMemoria[idx] = {..._tareasObraMemoria[idx], ...valores};
      }
      return;
    }
    await _db!.update(
      'tareas_obra',
      valores,
      where: 'id = ?',
      whereArgs: [tareaId],
    );
  }

  /// Obtiene reportes diarios filtrados opcionalmente por [obraId] y paginados.
  Future<List<Map<String, dynamic>>> obtenerReportesCrudos({
    String? obraId,
    int? limite,
    int? desplazamiento,
  }) async {
    await inicializar();
    if (_usarMemoriaFallback) {
      var lista = _reportesMemoria
          .where((r) => obraId == null || r['obra_id'] == obraId)
          .map(Map<String, dynamic>.from)
          .toList()
        ..sort(
          (a, b) => (b['fecha_creacion_local'] as String)
              .compareTo(a['fecha_creacion_local'] as String),
        );
      if (desplazamiento != null && desplazamiento > 0) {
        lista = desplazamiento >= lista.length
            ? <Map<String, dynamic>>[]
            : lista.sublist(desplazamiento);
      }
      if (limite != null && limite < lista.length) {
        lista = lista.sublist(0, limite);
      }

      return lista.map((reporte) {
        final reporteId = reporte['id'] as String;
        final obra = _buscarObraEnMemoria(reporte['obra_id'] as String);
        final autor = _buscarUsuarioEnMemoria(reporte['autor_id'] as String);
        final materiales = _reporteMaterialesMemoria
            .where((m) => m['reporte_id'] == reporteId)
            .map((m) => m['nombre'] as String)
            .toList();
        final fotos = _reporteFotosMemoria
            .where((f) => f['reporte_id'] == reporteId)
            .map(Map<String, dynamic>.from)
            .toList();

        return {
          ...reporte,
          'obra_nombre': obra?['nombre'] ?? '',
          'autor_nombre': autor?['nombre'] ?? 'Capataz',
          'materiales': materiales,
          'fotos': fotos,
        };
      }).toList();
    }

    final args = <Object?>[];
    final whereSql = obraId != null ? 'WHERE r.obra_id = ?' : '';
    if (obraId != null) args.add(obraId);

    final paginacion = StringBuffer();
    if (limite != null) {
      paginacion.write(' LIMIT ?');
      args.add(limite);
      if (desplazamiento != null) {
        paginacion.write(' OFFSET ?');
        args.add(desplazamiento);
      }
    }

    final reportes = await _db!.rawQuery(
      '''
      SELECT
        r.id,
        r.obra_id,
        o.nombre AS obra_nombre,
        r.autor_id,
        u.nombre AS autor_nombre,
        r.fecha_creacion_local,
        r.fecha_sincronizacion,
        r.tarea_seleccionada,
        r.tarea_completada,
        r.observaciones,
        r.estado_semaforo,
        r.sync_status,
        r.obra_finalizada,
        r.updated_at
      FROM reportes_diarios r
      INNER JOIN obras o ON o.id = r.obra_id
      INNER JOIN usuarios u ON u.id = r.autor_id
      $whereSql
      ORDER BY r.fecha_creacion_local DESC
      ${paginacion.toString()}
      ''',
      args,
    );

    if (reportes.isEmpty) return const [];

    final ids = reportes.map((r) => r['id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(', ');

    final materiales = await _db!.query(
      'reporte_materiales',
      where: 'reporte_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'id ASC',
    );
    final fotos = await _db!.query(
      'reporte_fotos',
      where: 'reporte_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'id ASC',
    );

    final materialesPorReporte = <String, List<String>>{};
    for (final material in materiales) {
      final reporteId = material['reporte_id'] as String;
      materialesPorReporte
          .putIfAbsent(reporteId, () => [])
          .add(material['nombre'] as String);
    }

    final fotosPorReporte = <String, List<Map<String, dynamic>>>{};
    for (final foto in fotos) {
      final reporteId = foto['reporte_id'] as String;
      fotosPorReporte.putIfAbsent(reporteId, () => []).add(foto);
    }

    return reportes.map((reporte) {
      final reporteId = reporte['id'] as String;
      return {
        ...reporte,
        'materiales': materialesPorReporte[reporteId] ?? const <String>[],
        'fotos': fotosPorReporte[reporteId] ?? const <Map<String, dynamic>>[],
      };
    }).toList();
  }

  /// Obtiene el historial de reportes diarios de una obra puntual filtrando
  /// directamente en SQL.
  Future<List<Map<String, dynamic>>> obtenerReportesPorObraCrudos(
    String obraId, {
    int? limite,
    int? desplazamiento,
  }) =>
      obtenerReportesCrudos(
        obraId: obraId,
        limite: limite,
        desplazamiento: desplazamiento,
      );

  /// Inserta o actualiza un reporte diario junto con `reporte_materiales` y
  /// `reporte_fotos` dentro de una transacción.
  Future<void> guardarReporteCrudo({
    required Map<String, dynamic> reporte,
    required List<String> materiales,
    required List<Map<String, dynamic>> fotos,
  }) async {
    await inicializar();
    final id = reporte['id'] as String;
    final obraId = reporte['obra_id'] as String;
    final autorId = reporte['autor_id'] as String;
    final filaReporte = {
      'updated_at': _ahoraUtcIso(),
      ...reporte,
    };

    if (_usarMemoriaFallback) {
      if (_buscarObraEnMemoria(obraId) == null) {
        throw StateError('Violación de FK: obra_id "$obraId" no existe.');
      }
      if (_buscarUsuarioEnMemoria(autorId) == null) {
        throw StateError('Violación de FK: autor_id "$autorId" no existe.');
      }
      final indice = _reportesMemoria.indexWhere((r) => r['id'] == id);
      if (indice == -1) {
        _reportesMemoria.insert(0, Map<String, dynamic>.from(filaReporte));
      } else {
        _reportesMemoria[indice] = Map<String, dynamic>.from(filaReporte);
      }
      _reporteMaterialesMemoria.removeWhere((m) => m['reporte_id'] == id);
      for (final nombreMaterial in materiales) {
        _reporteMaterialesMemoria.add({
          'reporte_id': id,
          'nombre': nombreMaterial,
        });
      }
      _reporteFotosMemoria.removeWhere((f) => f['reporte_id'] == id);
      _reporteFotosMemoria.addAll(fotos.map(Map<String, dynamic>.from));
      return;
    }

    await _db!.transaction((txn) async {
      final actualizados = await txn.update(
        'reportes_diarios',
        filaReporte,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (actualizados == 0) {
        await txn.insert('reportes_diarios', filaReporte);
      }

      await txn.delete(
        'reporte_materiales',
        where: 'reporte_id = ?',
        whereArgs: [id],
      );
      for (final nombreMaterial in materiales) {
        await txn.insert('reporte_materiales', {
          'reporte_id': id,
          'nombre': nombreMaterial,
        });
      }

      await txn.delete(
        'reporte_fotos',
        where: 'reporte_id = ?',
        whereArgs: [id],
      );
      for (final foto in fotos) {
        await txn.insert('reporte_fotos', foto);
      }
    });
  }

  /// Marca todos los reportes con `sync_status = 'pending'` como `'synced'`.
  Future<int> marcarReportesComoSincronizados(DateTime fechaSync) async {
    await inicializar();
    final isoFecha = fechaSync.toUtc().toIso8601String();
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

  /// Devuelve todas las filas pendientes (`sync_status = 'pending'`) de una
  /// tabla específica para el motor de sincronización Push.
  Future<List<Map<String, dynamic>>> obtenerPendientesDeTabla(
    String tabla,
  ) async {
    await inicializar();
    if (_usarMemoriaFallback) {
      final origen = _listaMemoriaPorTabla(tabla);
      return origen
          .where((fila) => fila['sync_status'] == 'pending')
          .map(Map<String, dynamic>.from)
          .toList();
    }
    return _db!.query(
      tabla,
      where: 'sync_status = ?',
      whereArgs: ['pending'],
    );
  }

  /// Devuelve los materiales asociados a una obra (para Push remoto).
  Future<List<String>> obtenerMaterialesDeObra(String obraId) async {
    await inicializar();
    if (_usarMemoriaFallback) {
      return _obraMaterialesMemoria
          .where((m) => m['obra_id'] == obraId)
          .map((m) => m['nombre'] as String)
          .toList();
    }
    final filas = await _db!.query(
      'obra_materiales',
      where: 'obra_id = ?',
      whereArgs: [obraId],
      orderBy: 'id ASC',
    );
    return filas.map((f) => f['nombre'] as String).toList();
  }

  /// Devuelve los materiales consumidos de un reporte (para Push remoto).
  Future<List<String>> obtenerMaterialesDeReporte(String reporteId) async {
    await inicializar();
    if (_usarMemoriaFallback) {
      return _reporteMaterialesMemoria
          .where((m) => m['reporte_id'] == reporteId)
          .map((m) => m['nombre'] as String)
          .toList();
    }
    final filas = await _db!.query(
      'reporte_materiales',
      where: 'reporte_id = ?',
      whereArgs: [reporteId],
      orderBy: 'id ASC',
    );
    return filas.map((f) => f['nombre'] as String).toList();
  }

  /// Devuelve las fotos asociadas a un reporte (para Push a Storage).
  Future<List<Map<String, dynamic>>> obtenerFotosDeReporte(
    String reporteId,
  ) async {
    await inicializar();
    if (_usarMemoriaFallback) {
      return _reporteFotosMemoria
          .where((f) => f['reporte_id'] == reporteId)
          .map(Map<String, dynamic>.from)
          .toList();
    }
    return _db!.query(
      'reporte_fotos',
      where: 'reporte_id = ?',
      whereArgs: [reporteId],
      orderBy: 'id ASC',
    );
  }

  /// Actualiza la URL remota de la foto de portada de una obra tras subirla
  /// al bucket de Storage.
  Future<void> actualizarImagenUrlObra({
    required String obraId,
    required String imagenUrl,
  }) async {
    await inicializar();
    if (_usarMemoriaFallback) {
      final idx = _obrasMemoria.indexWhere((o) => o['id'] == obraId);
      if (idx != -1) {
        _obrasMemoria[idx] = {..._obrasMemoria[idx], 'imagen_url': imagenUrl};
      }
      return;
    }
    await _db!.update(
      'obras',
      {'imagen_url': imagenUrl},
      where: 'id = ?',
      whereArgs: [obraId],
    );
  }

  /// Actualiza la URL remota y el estado de subida de una fotografía tras
  /// confirmarse su carga en Storage.
  Future<void> actualizarFotoSincronizada({
    required String reporteId,
    required String rutaLocal,
    required String urlRemota,
  }) async {
    await inicializar();
    if (_usarMemoriaFallback) {
      for (var i = 0; i < _reporteFotosMemoria.length; i++) {
        final f = _reporteFotosMemoria[i];
        if (f['reporte_id'] == reporteId && f['ruta_local'] == rutaLocal) {
          _reporteFotosMemoria[i] = {
            ...f,
            'url_remota': urlRemota,
            'estado_subida': 'synced',
          };
        }
      }
      return;
    }
    await _db!.update(
      'reporte_fotos',
      {'url_remota': urlRemota, 'estado_subida': 'synced'},
      where: 'reporte_id = ? AND ruta_local = ?',
      whereArgs: [reporteId, rutaLocal],
    );
  }

  /// Marca una fila concreta de [tabla] como `synced` tras confirmación remota.
  Future<void> marcarEntidadSincronizada({
    required String tabla,
    required String id,
    DateTime? fechaSyncUtc,
  }) async {
    await inicializar();
    final valores = <String, dynamic>{'sync_status': 'synced'};
    if (tabla == 'reportes_diarios' && fechaSyncUtc != null) {
      valores['fecha_sincronizacion'] = fechaSyncUtc.toUtc().toIso8601String();
    }

    if (_usarMemoriaFallback) {
      final lista = _listaMemoriaPorTabla(tabla);
      final idx = lista.indexWhere((e) => e['id'] == id);
      if (idx != -1) {
        lista[idx] = {...lista[idx], ...valores};
      }
      return;
    }
    await _db!.update(tabla, valores, where: 'id = ?', whereArgs: [id]);
  }

  /// Verifica si un registro local está actualmente en estado `pending`.
  /// Usado en Pull para aplicar *local-pending wins*.
  Future<bool> estaPendienteLocal({
    required String tabla,
    required String id,
  }) async {
    await inicializar();
    if (_usarMemoriaFallback) {
      final lista = _listaMemoriaPorTabla(tabla);
      for (final fila in lista) {
        if (fila['id'] == id) return fila['sync_status'] == 'pending';
      }
      return false;
    }
    final filas = await _db!.query(
      tabla,
      columns: ['sync_status'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (filas.isEmpty) return false;
    return filas.first['sync_status'] == 'pending';
  }

  /// Registra o incrementa un fallo de sincronización en `cola_sincronizacion`.
  Future<void> registrarFalloSincronizacion({
    required String entidad,
    required String entidadId,
    required String operacion,
    required String error,
  }) async {
    await inicializar();
    final clave = '${entidad}_$entidadId';
    final ahora = _ahoraUtcIso();
    if (_usarMemoriaFallback) {
      final idx = _colaSyncMemoria.indexWhere((c) => c['id'] == clave);
      if (idx == -1) {
        _colaSyncMemoria.add({
          'id': clave,
          'entidad': entidad,
          'entidad_id': entidadId,
          'operacion': operacion,
          'reintentos': 1,
          'ultimo_error': error,
          'creado_en': ahora,
        });
      } else {
        final actual = _colaSyncMemoria[idx];
        _colaSyncMemoria[idx] = {
          ...actual,
          'reintentos': (actual['reintentos'] as int? ?? 0) + 1,
          'ultimo_error': error,
        };
      }
      return;
    }

    final existentes = await _db!.query(
      'cola_sincronizacion',
      where: 'id = ?',
      whereArgs: [clave],
      limit: 1,
    );
    if (existentes.isEmpty) {
      await _db!.insert('cola_sincronizacion', {
        'id': clave,
        'entidad': entidad,
        'entidad_id': entidadId,
        'operacion': operacion,
        'reintentos': 1,
        'ultimo_error': error,
        'creado_en': ahora,
      });
    } else {
      final reintentos = (existentes.first['reintentos'] as int? ?? 0) + 1;
      await _db!.update(
        'cola_sincronizacion',
        {'reintentos': reintentos, 'ultimo_error': error},
        where: 'id = ?',
        whereArgs: [clave],
      );
    }
  }

  /// Elimina una entrada de error de `cola_sincronizacion` cuando tiene éxito.
  Future<void> limpiarFalloSincronizacion({
    required String entidad,
    required String entidadId,
  }) async {
    await inicializar();
    final clave = '${entidad}_$entidadId';
    if (_usarMemoriaFallback) {
      _colaSyncMemoria.removeWhere((c) => c['id'] == clave);
      return;
    }
    await _db!.delete(
      'cola_sincronizacion',
      where: 'id = ?',
      whereArgs: [clave],
    );
  }

  /// Devuelve el detalle actual de elementos con reintentos en `cola_sincronizacion`.
  Future<List<Map<String, dynamic>>> obtenerFallosSincronizacion() async {
    await inicializar();
    if (_usarMemoriaFallback) {
      return _colaSyncMemoria.map(Map<String, dynamic>.from).toList();
    }
    return _db!.query('cola_sincronizacion', orderBy: 'creado_en ASC');
  }

  /// Devuelve la marca de tiempo UTC de la última sincronización exitosa.
  Future<DateTime?> obtenerUltimaSyncUtc() async {
    await inicializar();
    if (_usarMemoriaFallback) {
      return _ultimaSyncUtcMemoria != null
          ? DateTime.parse(_ultimaSyncUtcMemoria!)
          : null;
    }
    final filas = await _db!.query('estado_sincronizacion', limit: 1);
    if (filas.isEmpty) return null;
    final raw = filas.first['ultima_sync_utc'] as String?;
    return raw != null ? DateTime.parse(raw) : null;
  }

  /// Persiste la marca de tiempo UTC de la última sincronización exitosa.
  Future<void> guardarUltimaSyncUtc(DateTime fechaUtc) async {
    await inicializar();
    final iso = fechaUtc.toUtc().toIso8601String();
    if (_usarMemoriaFallback) {
      _ultimaSyncUtcMemoria = iso;
      return;
    }
    final actualizados = await _db!.update(
      'estado_sincronizacion',
      {'ultima_sync_utc': iso},
      where: 'id = ?',
      whereArgs: [1],
    );
    if (actualizados == 0) {
      await _db!.insert('estado_sincronizacion', {
        'id': 1,
        'ultima_sync_utc': iso,
      });
    }
  }

  /// Obtiene el historial de notificaciones emitidas.
  Future<List<Map<String, dynamic>>> obtenerNotificacionesCrudas() async {
    await inicializar();
    if (_usarMemoriaFallback) {
      final copia = List<Map<String, dynamic>>.from(_notificacionesMemoria)
        ..sort(
          (a, b) =>
              (b['fecha_hora'] as String).compareTo(a['fecha_hora'] as String),
        );
      return copia;
    }
    return _db!.query('notificaciones', orderBy: 'fecha_hora DESC');
  }

  /// Registra una nueva notificación en la base local respetando FK `obra_id`.
  Future<void> guardarNotificacionCruda(Map<String, dynamic> notifMap) async {
    await inicializar();
    final id = notifMap['id'] as String;
    final obraId = notifMap['obra_id'] as String?;
    final datosNormalizados = <String, dynamic>{
      'updated_at': _ahoraUtcIso(),
      'sync_status': 'pending',
      ...notifMap,
    };

    if (_usarMemoriaFallback) {
      if (obraId != null && _buscarObraEnMemoria(obraId) == null) {
        datosNormalizados['obra_id'] = null;
      }
      final indice = _notificacionesMemoria.indexWhere((n) => n['id'] == id);
      if (indice == -1) {
        _notificacionesMemoria.insert(0, datosNormalizados);
      } else {
        _notificacionesMemoria[indice] = datosNormalizados;
      }
      return;
    }

    if (obraId != null) {
      final existe = await _db!.query(
        'obras',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [obraId],
        limit: 1,
      );
      if (existe.isEmpty) {
        datosNormalizados['obra_id'] = null;
      }
    }

    final actualizados = await _db!.update(
      'notificaciones',
      datosNormalizados,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (actualizados == 0) {
      await _db!.insert('notificaciones', datosNormalizados);
    }
  }

  /// Obtiene la configuración del recordatorio diario de sincronización.
  Future<Map<String, dynamic>> obtenerConfiguracionRecordatorio() async {
    await inicializar();
    if (_usarMemoriaFallback) {
      return Map<String, dynamic>.from(_configRecordatorioMemoria);
    }
    final filas = await _db!.query('configuracion_recordatorio', limit: 1);
    if (filas.isEmpty) {
      return {'id': 1, 'activo': 1, 'hora': 18, 'minuto': 0};
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
    final actualizados = await _db!.update(
      'configuracion_recordatorio',
      valores,
      where: 'id = ?',
      whereArgs: [1],
    );
    if (actualizados == 0) {
      await _db!.insert('configuracion_recordatorio', valores);
    }
  }

  /// Cierra la conexión SQLite cuando ya no se utiliza.
  Future<void> cerrar() async {
    await _db?.close();
    _db = null;
    _inicializado = false;
  }

  List<Map<String, dynamic>> _listaMemoriaPorTabla(String tabla) =>
      switch (tabla) {
        'usuarios' => _usuariosMemoria,
        'obras' => _obrasMemoria,
        'tareas_obra' => _tareasObraMemoria,
        'reportes_diarios' => _reportesMemoria,
        'notificaciones' => _notificacionesMemoria,
        'catalogo_plantillas' => _plantillasMemoria,
        _ => throw ArgumentError('Tabla no soportada para sync: $tabla'),
      };

  Map<String, dynamic>? _buscarRolEnMemoria(String id) {
    for (final rol in _rolesMemoria) {
      if (rol['id'] == id) return rol;
    }
    return null;
  }

  Map<String, dynamic>? _buscarUsuarioEnMemoria(String id) {
    for (final usuario in _usuariosMemoria) {
      if (usuario['id'] == id) return usuario;
    }
    return null;
  }

  Map<String, dynamic>? _buscarObraEnMemoria(String id) {
    for (final obra in _obrasMemoria) {
      if (obra['id'] == id) return obra;
    }
    return null;
  }

  /// Catálogo inicial con los 3 roles operativos del proyecto.
  List<Map<String, dynamic>> _semillasRoles() => [
        {
          'id': 'rol_ingeniero',
          'codigo': 'ingeniero',
          'nombre': 'Ingeniero Jefe de Obra',
        },
        {
          'id': 'rol_capataz',
          'codigo': 'capataz',
          'nombre': 'Capataz de Obra',
        },
        {
          'id': 'rol_duenio',
          'codigo': 'duenio',
          'nombre': 'Dueño / Gerencia',
        },
      ];

  /// 3 usuarios de prueba vinculados con `roles` (1:N) incluyendo `telefono`.
  List<Map<String, dynamic>> _semillasUsuarios() {
    final ts = DateTime.utc(2026, 9, 18).toIso8601String();
    return [
      {
        'id': 'u_ingeniero',
        'username': 'ingeniero',
        'rol_id': 'rol_ingeniero',
        'nombre': 'Ing. Braulio Hormigón',
        'contrasenia': '1234',
        'telefono': '+54 9 261 555-0101',
        'updated_at': ts,
        'sync_status': 'synced',
      },
      {
        'id': 'u_capataz',
        'username': 'capataz',
        'rol_id': 'rol_capataz',
        'nombre': 'Carlos Méndez (Capataz)',
        'contrasenia': '1234',
        'telefono': '+54 9 261 555-0102',
        'updated_at': ts,
        'sync_status': 'synced',
      },
      {
        'id': 'u_duenio',
        'username': 'dueno',
        'rol_id': 'rol_duenio',
        'nombre': 'Roberto Del Sur (Dueño)',
        'contrasenia': '1234',
        'telefono': '+54 9 261 555-0100',
        'updated_at': ts,
        'sync_status': 'synced',
      },
    ];
  }

  /// Las 6 obras activas iniciales con ubicación atómica y FK a `usuarios`.
  List<Map<String, dynamic>> _semillasObras() => [
        {
          'id': '1',
          'nombre': 'Torre Residencial Las Heras',
          'estado_semaforo': 'problemas',
          'fecha_ultimo_reporte':
              DateTime.utc(2026, 9, 18, 16, 30).toIso8601String(),
          'responsable_id': 'u_capataz',
          'ingeniero_id': 'u_ingeniero',
          'ubicacion_latitud': -32.8489,
          'ubicacion_longitud': -68.8392,
          'ubicacion_direccion': 'Av. San Martín 1450, Las Heras, Mendoza',
          'observaciones':
              'Faltó hormigón el martes. Proveedor reprogramó entrega.',
          'con_foto': 1,
          'imagen': 'assets/images/obra1.png',
          'imagen_url': null,
          'finalizada': 0,
          'updated_at': DateTime.utc(2026, 9, 18, 16, 30).toIso8601String(),
          'sync_status': 'synced',
          'deleted_at': null,
        },
        {
          'id': '2',
          'nombre': 'Complejo Comercial Belgrano',
          'estado_semaforo': 'aTiempo',
          'fecha_ultimo_reporte':
              DateTime.utc(2026, 9, 18, 17, 15).toIso8601String(),
          'responsable_id': 'u_capataz',
          'ingeniero_id': 'u_ingeniero',
          'ubicacion_latitud': -32.8895,
          'ubicacion_longitud': -68.8458,
          'ubicacion_direccion': 'Av. Belgrano 820, Ciudad de Mendoza',
          'observaciones':
              'Sin novedades. Cuadrilla trabajando a ritmo completo.',
          'con_foto': 1,
          'imagen': 'assets/images/obra2.png',
          'imagen_url': null,
          'finalizada': 0,
          'updated_at': DateTime.utc(2026, 9, 18, 17, 15).toIso8601String(),
          'sync_status': 'synced',
          'deleted_at': null,
        },
        {
          'id': '3',
          'nombre': 'Nave Industrial Parque Sur',
          'estado_semaforo': 'demorada',
          'fecha_ultimo_reporte':
              DateTime.utc(2026, 9, 17, 18, 0).toIso8601String(),
          'responsable_id': 'u_capataz',
          'ingeniero_id': 'u_ingeniero',
          'ubicacion_latitud': -32.9254,
          'ubicacion_longitud': -68.8130,
          'ubicacion_direccion':
              'Carril Rodríguez Peña 2300, Godoy Cruz, Mendoza',
          'observaciones': 'Lluvia, se perdieron dos días en tendido exterior.',
          'con_foto': 0,
          'imagen': 'assets/images/obra3.png',
          'imagen_url': null,
          'finalizada': 0,
          'updated_at': DateTime.utc(2026, 9, 17, 18, 0).toIso8601String(),
          'sync_status': 'synced',
          'deleted_at': null,
        },
        {
          'id': '4',
          'nombre': 'Edificio Mirador del Parque',
          'estado_semaforo': 'demorada',
          'fecha_ultimo_reporte':
              DateTime.utc(2026, 9, 17, 15, 20).toIso8601String(),
          'responsable_id': 'u_capataz',
          'ingeniero_id': 'u_ingeniero',
          'ubicacion_latitud': -32.8930,
          'ubicacion_longitud': -68.8615,
          'ubicacion_direccion': 'Av. Emilio Civit 410, Ciudad de Mendoza',
          'observaciones':
              'Esperando habilitación municipal para corte parcial de vereda.',
          'con_foto': 0,
          'imagen': 'assets/images/obra4.png',
          'imagen_url': null,
          'finalizada': 0,
          'updated_at': DateTime.utc(2026, 9, 17, 15, 20).toIso8601String(),
          'sync_status': 'synced',
          'deleted_at': null,
        },
        {
          'id': '5',
          'nombre': 'Barrio Privado Los Olivos',
          'estado_semaforo': 'aTiempo',
          'fecha_ultimo_reporte':
              DateTime.utc(2026, 9, 18, 14, 10).toIso8601String(),
          'responsable_id': 'u_ingeniero',
          'ingeniero_id': 'u_ingeniero',
          'ubicacion_latitud': -32.9612,
          'ubicacion_longitud': -68.8540,
          'ubicacion_direccion':
              'Ruta Panamericana Km 12, Luján de Cuyo, Mendoza',
          'observaciones': 'Avance normal según cronograma semanal.',
          'con_foto': 0,
          'imagen': 'assets/images/obra5.png',
          'imagen_url': null,
          'finalizada': 0,
          'updated_at': DateTime.utc(2026, 9, 18, 14, 10).toIso8601String(),
          'sync_status': 'synced',
          'deleted_at': null,
        },
        {
          'id': '6',
          'nombre': 'Centro Logístico Ruta 40',
          'estado_semaforo': 'aTiempo',
          'fecha_ultimo_reporte':
              DateTime.utc(2026, 9, 19, 11, 45).toIso8601String(),
          'responsable_id': 'u_ingeniero',
          'ingeniero_id': 'u_ingeniero',
          'ubicacion_latitud': -32.8150,
          'ubicacion_longitud': -68.8210,
          'ubicacion_direccion': 'Ruta Nacional 40 Km 3295, Las Heras, Mendoza',
          'observaciones': 'Inicio de encofrado en sector norte.',
          'con_foto': 0,
          'imagen': 'assets/images/obra6.png',
          'imagen_url': null,
          'finalizada': 0,
          'updated_at': DateTime.utc(2026, 9, 19, 11, 45).toIso8601String(),
          'sync_status': 'synced',
          'deleted_at': null,
        },
      ];

  /// Tareas normalizadas en `tareas_obra` (1:N con `obras`).
  List<Map<String, dynamic>> _semillasTareasObra() {
    final ts = DateTime.utc(2026, 9, 18).toIso8601String();
    Map<String, dynamic> tarea(
      String id,
      String obraId,
      String nombre,
      int completada,
      int orden,
    ) =>
        {
          'id': id,
          'obra_id': obraId,
          'nombre': nombre,
          'completada': completada,
          'orden': orden,
          'updated_at': ts,
          'sync_status': 'synced',
        };

    return [
      tarea('t1_1', '1', 'Replanteo y excavación de bases', 1, 0),
      tarea('t1_2', '1', 'Losa de planta alta', 0, 1),
      tarea('t1_3', '1', 'Columnas de hormigón piso 2', 0, 2),
      tarea('t2_1', '2', 'Fundaciones y encadenado inferior', 1, 0),
      tarea('t2_2', '2', 'Mampostería piso 1', 1, 1),
      tarea('t2_3', '2', 'Revocado grueso interior', 1, 2),
      tarea('t2_4', '2', 'Mampostería piso 2', 1, 3),
      tarea('t2_5', '2', 'Colocación de aberturas de aluminio', 0, 4),
      tarea('t3_1', '3', 'Nivelación y compactación de suelo', 1, 0),
      tarea('t3_2', '3', 'Montaje de cabreadas metálicas', 1, 1),
      tarea('t3_3', '3', 'Instalación eléctrica trifásica', 0, 2),
      tarea('t3_4', '3', 'Piso industrial alisado', 0, 3),
      tarea('t4_1', '4', 'Vallado perimetral reglamentario', 1, 0),
      tarea('t4_2', '4', 'Andamios fachada principal', 0, 1),
      tarea('t4_3', '4', 'Revestimiento texturado exterior', 0, 2),
      tarea('t5_1', '5', 'Movimiento de suelo y apertura de calles', 1, 0),
      tarea('t5_2', '5', 'Red de agua potable y cloacas', 1, 1),
      tarea('t5_3', '5', 'Estructura de hormigón pórtico acceso', 0, 2),
      tarea('t6_1', '6', 'Platea de fundación sector A', 1, 0),
      tarea('t6_2', '6', 'Encofrado de columnas perimetrales', 0, 1),
      tarea('t6_3', '6', 'Vigas de encadenado superior', 0, 2),
      tarea('t6_4', '6', 'Cubierta metálica parabólica', 0, 3),
      tarea('t6_5', '6', 'Dársenas de carga y descarga', 0, 4),
    ];
  }

  /// Materiales asignados a cada obra en `obra_materiales` (1:N con `obras`).
  List<Map<String, dynamic>> _semillasObraMateriales() => [
        {'obra_id': '1', 'nombre': 'Hormigón H-21'},
        {'obra_id': '1', 'nombre': 'Hierro nervado 12mm'},
        {'obra_id': '1', 'nombre': 'Alambre negro recocido'},
        {'obra_id': '1', 'nombre': 'Madera para encofrado'},
        {'obra_id': '2', 'nombre': 'Ladrillón cerámico 18x18x33'},
        {'obra_id': '2', 'nombre': 'Cemento Portland'},
        {'obra_id': '2', 'nombre': 'Cal hidráulica'},
        {'obra_id': '2', 'nombre': 'Arena gruesa'},
        {'obra_id': '3', 'nombre': 'Cable subterráneo 4x16mm'},
        {'obra_id': '3', 'nombre': 'Bandejas portacables galvanizadas'},
        {'obra_id': '3', 'nombre': 'Tablero estanco IP65'},
        {'obra_id': '3', 'nombre': 'Jabalina de puesta a tierra'},
        {'obra_id': '4', 'nombre': 'Cuerpos de andamio tubular'},
        {'obra_id': '4', 'nombre': 'Tablones metálicos antideslizantes'},
        {'obra_id': '4', 'nombre': 'Revestimiento plástico texturado'},
        {'obra_id': '4', 'nombre': 'Malla de fibra de vidrio'},
        {'obra_id': '5', 'nombre': 'Hormigón elaborado H-25'},
        {'obra_id': '5', 'nombre': 'Malla electrosoldada Q188'},
        {'obra_id': '5', 'nombre': 'Caño PVC 110mm'},
        {'obra_id': '6', 'nombre': 'Fenólico 18mm para encofrado'},
        {'obra_id': '6', 'nombre': 'Puntales telescópicos metálicos'},
        {'obra_id': '6', 'nombre': 'Desmoldante líquido'},
        {'obra_id': '6', 'nombre': 'Hierro 16mm'},
      ];

  /// Reportes diarios iniciales con FKs a `obras` y `usuarios`.
  List<Map<String, dynamic>> _semillasReportes() => [
        {
          'id': 'rep_101',
          'obra_id': '1',
          'autor_id': 'u_capataz',
          'fecha_creacion_local':
              DateTime.utc(2026, 9, 18, 16, 30).toIso8601String(),
          'fecha_sincronizacion':
              DateTime.utc(2026, 9, 18, 18, 0).toIso8601String(),
          'tarea_seleccionada': 'Losa de planta alta',
          'tarea_completada': 0,
          'observaciones':
              'Faltó hormigón el martes. Proveedor reprogramó entrega.',
          'estado_semaforo': 'problemas',
          'sync_status': 'synced',
          'obra_finalizada': 0,
          'updated_at': DateTime.utc(2026, 9, 18, 16, 30).toIso8601String(),
        },
        {
          'id': 'rep_102',
          'obra_id': '2',
          'autor_id': 'u_capataz',
          'fecha_creacion_local':
              DateTime.utc(2026, 9, 18, 17, 15).toIso8601String(),
          'fecha_sincronizacion':
              DateTime.utc(2026, 9, 18, 18, 0).toIso8601String(),
          'tarea_seleccionada': 'Mampostería piso 2',
          'tarea_completada': 1,
          'observaciones':
              'Sin novedades. Se completó el cerramiento del piso 2.',
          'estado_semaforo': 'aTiempo',
          'sync_status': 'synced',
          'obra_finalizada': 0,
          'updated_at': DateTime.utc(2026, 9, 18, 17, 15).toIso8601String(),
        },
        {
          'id': 'rep_103',
          'obra_id': '3',
          'autor_id': 'u_capataz',
          'fecha_creacion_local':
              DateTime.utc(2026, 9, 17, 18, 0).toIso8601String(),
          'fecha_sincronizacion': null,
          'tarea_seleccionada': 'Instalación eléctrica trifásica',
          'tarea_completada': 0,
          'observaciones': 'Lluvia, se perdieron dos días en tendido exterior.',
          'estado_semaforo': 'demorada',
          'sync_status': 'pending',
          'obra_finalizada': 0,
          'updated_at': DateTime.utc(2026, 9, 17, 18, 0).toIso8601String(),
        },
      ];

  /// Materiales consumidos por reporte en `reporte_materiales`.
  List<Map<String, dynamic>> _semillasReporteMateriales() => [
        {'reporte_id': 'rep_101', 'nombre': 'Hierro nervado 12mm'},
        {'reporte_id': 'rep_101', 'nombre': 'Madera para encofrado'},
        {'reporte_id': 'rep_102', 'nombre': 'Ladrillón cerámico 18x18x33'},
        {'reporte_id': 'rep_102', 'nombre': 'Cemento Portland'},
        {'reporte_id': 'rep_102', 'nombre': 'Arena gruesa'},
        {
          'reporte_id': 'rep_103',
          'nombre': 'Bandejas portacables galvanizadas'
        },
      ];

  /// Fotografías comprimidas asociadas a reportes en `reporte_fotos`.
  List<Map<String, dynamic>> _semillasReporteFotos() => [
        {
          'reporte_id': 'rep_101',
          'ruta_local': 'assets/images/obra1.png',
          'origen': 'Cámara (Comprimida)',
          'ancho_px': 800,
          'alto_px': 600,
          'calidad_pct': 70,
          'peso_kb': 142,
          'bytes_base64': null,
          'url_remota': null,
          'estado_subida': 'synced',
        },
        {
          'reporte_id': 'rep_102',
          'ruta_local': 'assets/images/obra2.png',
          'origen': 'Cámara (Comprimida)',
          'ancho_px': 800,
          'alto_px': 600,
          'calidad_pct': 70,
          'peso_kb': 158,
          'bytes_base64': null,
          'url_remota': null,
          'estado_subida': 'synced',
        },
      ];

  List<Map<String, dynamic>> _semillasNotificaciones() => [
        {
          'id': 'notif_1',
          'obra_id': '1',
          'titulo': 'Alerta Roja: Torre Residencial Las Heras',
          'mensaje':
              'La obra pasó a estado "Con problemas" (Rojo). Motivo: Faltó hormigón el martes.',
          'destinatario': 'Ing. Braulio Hormigón / Roberto Del Sur (Dueño)',
          'fecha_hora': DateTime.utc(2026, 9, 18, 16, 31).toIso8601String(),
          'es_alerta_semaforo': 1,
          'updated_at': DateTime.utc(2026, 9, 18, 16, 31).toIso8601String(),
          'sync_status': 'synced',
        },
        {
          'id': 'notif_2',
          'obra_id': '3',
          'titulo': 'Alerta Amarilla: Nave Industrial Parque Sur',
          'mensaje':
              'La obra pasó a estado "Demorada" (Amarillo). Motivo: Lluvia, se perdieron dos días.',
          'destinatario': 'Ing. Braulio Hormigón / Roberto Del Sur (Dueño)',
          'fecha_hora': DateTime.utc(2026, 9, 17, 18, 1).toIso8601String(),
          'es_alerta_semaforo': 1,
          'updated_at': DateTime.utc(2026, 9, 17, 18, 1).toIso8601String(),
          'sync_status': 'synced',
        },
      ];

  /// Catálogo inicial de tareas y materiales frecuentes para el ingeniero
  /// en modo demo/test (sugerencias opcionales, nunca precargadas en la obra).
  List<Map<String, dynamic>> _semillasPlantillas() {
    final ts = DateTime.utc(2026, 9, 18).toIso8601String();
    Map<String, dynamic> item(String id, String tipo, String nombre) => {
          'id': id,
          'usuario_id': 'u_ingeniero',
          'tipo': tipo,
          'nombre': nombre,
          'updated_at': ts,
          'sync_status': 'synced',
          'deleted_at': null,
        };
    return [
      item('plt_t1', 'tarea', 'Replanteo y nivelación de terreno'),
      item('plt_t2', 'tarea', 'Excavación de fundaciones'),
      item('plt_t3', 'tarea', 'Hormigonado de estructura'),
      item('plt_m1', 'material', 'Hormigón H-21'),
      item('plt_m2', 'material', 'Hierro nervado 12mm'),
      item('plt_m3', 'material', 'Cemento Portland'),
    ];
  }
}
