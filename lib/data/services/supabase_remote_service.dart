import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'fuente_datos_remota.dart';

/// Implementación real de [FuenteDatosRemota] sobre Supabase (`EgiMobile`):
/// PostgreSQL + RLS + bucket privado `fotos-obras` + Realtime (`postgres_changes`).
class SupabaseRemoteService implements FuenteDatosRemota {
  SupabaseRemoteService({
    required SupabaseClient client,
    this.bucketFotos = 'fotos-obras',
    this.duracionUrlFirmadaSegundos = 60 * 60 * 24 * 7,
  }) : _client = client;

  static const _tablasRealtime = [
    'obras',
    'tareas_obra',
    'reportes_diarios',
    'reporte_fotos',
    'notificaciones',
    'catalogo_plantillas',
    'configuracion_recordatorio',
  ];

  final SupabaseClient _client;
  final String bucketFotos;
  final int duracionUrlFirmadaSegundos;

  /// Solo opera cuando existe una sesión JWT válida para cumplir RLS.
  @override
  bool get estaDisponible => _client.auth.currentSession != null;

  @override
  Future<String> subirFoto({
    required String rutaLocal,
    required String destinoStorage,
    Uint8List? bytes,
  }) async {
    if (bytes == null || bytes.isEmpty) {
      throw StateError(
        'No se pudieron leer los bytes locales de la fotografía "$rutaLocal".',
      );
    }

    final storagePath = normalizarRutaEnBucket(
      destinoStorage: destinoStorage,
      bucket: bucketFotos,
    );

    final storage = _client.storage.from(bucketFotos);
    await storage.uploadBinary(
      storagePath,
      bytes,
      fileOptions: const FileOptions(
        upsert: true,
        contentType: 'image/jpeg',
      ),
    );

    return storage.createSignedUrl(storagePath, duracionUrlFirmadaSegundos);
  }

  @override
  Future<void> upsertUsuario(Map<String, dynamic> usuario) async {
    final payload = mapearUsuarioLocalARemoto(usuario);
    await _client.from('usuarios').upsert(payload, onConflict: 'id');
  }

  @override
  Future<void> actualizarFcmToken({
    required String usuarioId,
    required String? fcmToken,
  }) async {
    if (!estaDisponible) return;
    await _client
        .from('usuarios')
        .update({'fcm_token': fcmToken}).eq('id', usuarioId);
  }

  @override
  Future<void> upsertObra({
    required Map<String, dynamic> obra,
    required List<String> materiales,
  }) async {
    final obraId = obra['id'] as String;
    final payload = mapearObraLocalARemoto(obra);

    // Intenta UPDATE primero para respetar RLS de capataz (en PostgreSQL,
    // `INSERT ... ON CONFLICT DO UPDATE` exige permiso RLS de INSERT incluso
    // cuando la fila ya existe). Solo inserta si la obra todavía no existe.
    final actualizadas = await _client
        .from('obras')
        .update(payload)
        .eq('id', obraId)
        .select('id');

    final fueNueva = actualizadas.isEmpty;
    if (fueNueva) {
      await _client.from('obras').insert(payload);
    }

    if (materiales.isNotEmpty) {
      final filasMateriales = materiales
          .map((nombre) => {'obra_id': obraId, 'nombre': nombre})
          .toList();
      try {
        await _client.from('obra_materiales').upsert(
              filasMateriales,
              onConflict: 'obra_id,nombre',
            );
      } on PostgrestException catch (e) {
        // Si un capataz solo actualizó el semáforo de una obra existente,
        // no tiene permiso RLS para insertar en `obra_materiales`.
        if (fueNueva || e.code != '42501') {
          rethrow;
        }
      }
    }
  }

  @override
  Future<void> upsertTarea(Map<String, dynamic> tarea) async {
    final payload = mapearTareaLocalARemoto(tarea);
    await _client.from('tareas_obra').upsert(payload, onConflict: 'id');
  }

  @override
  Future<void> upsertReporte({
    required Map<String, dynamic> reporte,
    required List<String> materiales,
    required List<Map<String, dynamic>> fotos,
  }) async {
    final reporteId = reporte['id'] as String;
    final obraId = reporte['obra_id'] as String;
    final payload = mapearReporteLocalARemoto(reporte);
    await _client.from('reportes_diarios').upsert(payload, onConflict: 'id');

    if (materiales.isNotEmpty) {
      final filasMateriales = materiales
          .map((nombre) => {'reporte_id': reporteId, 'nombre': nombre})
          .toList();
      await _client.from('reporte_materiales').upsert(
            filasMateriales,
            onConflict: 'reporte_id,nombre',
          );
    }

    if (fotos.isNotEmpty) {
      final filasFotos = [
        for (var i = 0; i < fotos.length; i++)
          mapearFotoLocalARemoto(
            fotos[i],
            reporteId: reporteId,
            storagePath: '$obraId/${reporteId}_$i.jpg',
          ),
      ];
      await _client.from('reporte_fotos').upsert(
            filasFotos,
            onConflict: 'reporte_id,ruta_local',
          );
    }
  }

  @override
  Future<void> upsertNotificacion(Map<String, dynamic> notificacion) async {
    final payload = mapearNotificacionLocalARemoto(notificacion);
    await _client.from('notificaciones').upsert(payload, onConflict: 'id');

    if (_aBooleano(notificacion['es_alerta_semaforo'])) {
      try {
        await _client.functions.invoke(
          'enviar-push-fcm',
          body: {'notificacion_id': notificacion['id']},
        );
      } catch (_) {
        // Si la Edge Function o el secret FCM todavía no están listos, no
        // bloquea la sincronización de datos en PostgreSQL.
      }
    }
  }

  @override
  Future<void> upsertPlantilla(Map<String, dynamic> plantilla) async {
    final payload = mapearPlantillaLocalARemoto(plantilla);
    await _client.from('catalogo_plantillas').upsert(payload, onConflict: 'id');
  }

  @override
  Future<void> upsertConfiguracionRecordatorio(
    Map<String, dynamic> config,
  ) async {
    final payload = mapearConfigRecordatorioLocalARemoto(config);
    await _client
        .from('configuracion_recordatorio')
        .upsert(payload, onConflict: 'ingeniero_id');
  }

  @override
  Future<CambiosRemotos> obtenerCambiosDesde(DateTime? ultimaSyncUtc) async {
    final isoCursor = ultimaSyncUtc?.toUtc().toIso8601String();

    final rolesRaw = await _client.from('roles').select('id, codigo, nombre');
    final roles = rolesRaw
        .map(
          (r) => {
            'id': r['id'] as String,
            'codigo': r['codigo'] as String,
            'nombre': r['nombre'] as String,
          },
        )
        .toList();

    // Directorio corporativo completo (tabla pequeña, como `roles`) para que
    // todos los capataces e ingenieros estén disponibles al asignar obras.
    final usuariosRaw = await _client
        .from('usuarios')
        .select('id, username, rol_id, nombre, telefono, updated_at');
    final usuarios = usuariosRaw.map(mapearUsuarioRemotoALocal).toList();

    final obrasQuery = _client.from('obras').select(
          'id, nombre, estado_semaforo, fecha_ultimo_reporte, responsable_id, '
          'ingeniero_id, tarea_actual_id, ubicacion_latitud, '
          'ubicacion_longitud, ubicacion_direccion, observaciones, con_foto, '
          'imagen, imagen_url, finalizada, updated_at, deleted_at, '
          'obra_materiales(nombre), '
          'tareas_obra!tareas_obra_obra_id_fkey('
          'id, obra_id, nombre, completada, orden, updated_at)',
        );
    final obrasRaw = isoCursor != null
        ? await obrasQuery.gt('updated_at', isoCursor)
        : await obrasQuery;
    final obras = <Map<String, dynamic>>[];
    for (final raw in obrasRaw) {
      final obraLocal = mapearObraRemotaALocal(raw);
      final idObra = obraLocal['id'] as String;
      final imagen = (obraLocal['imagen'] as String?) ?? '';
      final urlActual = (obraLocal['imagen_url'] as String?) ?? '';
      final esPortadaPersonalizada =
          (obraLocal['con_foto'] as int? ?? 0) == 1 &&
              imagen.isNotEmpty &&
              !imagen.startsWith('assets/');

      // Conserva la URL firmada existente (válida 7 días) para que ImageCache
      // de Flutter no invalide ni vuelva a descargar la foto en cada sync.
      final requiereNuevaFirma = urlActual.isEmpty ||
          _urlFirmadaProximaAVencer(obraLocal['updated_at']);

      if (esPortadaPersonalizada && requiereNuevaFirma) {
        try {
          obraLocal['imagen_url'] =
              await _client.storage.from(bucketFotos).createSignedUrl(
                    'portadas/$idObra.jpg',
                    duracionUrlFirmadaSegundos,
                  );
        } catch (_) {
          // Conserva la imagen_url ya existente si la portada aún no fue subida.
        }
      }
      obras.add(obraLocal);
    }

    final tareasQuery = _client
        .from('tareas_obra')
        .select('id, obra_id, nombre, completada, orden, updated_at');
    final tareasRaw = isoCursor != null
        ? await tareasQuery.gt('updated_at', isoCursor)
        : await tareasQuery;
    final tareas = tareasRaw.map(mapearTareaRemotaALocal).toList();

    final reportesQuery = _client.from('reportes_diarios').select(
          'id, obra_id, autor_id, fecha_creacion_local, fecha_sincronizacion, '
          'tarea_seleccionada, tarea_completada, observaciones, '
          'estado_semaforo, obra_finalizada, updated_at, '
          'reporte_materiales(nombre), '
          'reporte_fotos(ruta_local, origen, ancho_px, alto_px, calidad_pct, '
          'peso_kb, url_remota, storage_path)',
        );
    final reportesRaw = isoCursor != null
        ? await reportesQuery.gt('updated_at', isoCursor)
        : await reportesQuery;

    final reportes = <Map<String, dynamic>>[];
    for (final raw in reportesRaw) {
      final reporteLocal = mapearReporteRemotoALocal(raw);
      final fotos = (reporteLocal['fotos'] as List<Map<String, dynamic>>);
      for (final foto in fotos) {
        final storagePath = foto.remove('storage_path') as String?;
        final urlActual = foto['url_remota'] as String?;
        if ((urlActual == null || urlActual.isEmpty) &&
            storagePath != null &&
            storagePath.isNotEmpty) {
          try {
            foto['url_remota'] = await _client.storage
                .from(bucketFotos)
                .createSignedUrl(storagePath, duracionUrlFirmadaSegundos);
          } catch (_) {
            // Si no se puede firmar ahora, se conservará la ruta local.
          }
        }
      }
      reportes.add(reporteLocal);
    }

    final notifQuery = _client.from('notificaciones').select(
          'id, obra_id, emisor_id, titulo, mensaje, destinatario, fecha_hora, '
          'es_alerta_semaforo, updated_at',
        );
    final notifRaw = isoCursor != null
        ? await notifQuery.gt('updated_at', isoCursor)
        : await notifQuery;
    final notificaciones =
        notifRaw.map(mapearNotificacionRemotaALocal).toList();

    final plantillasQuery = _client
        .from('catalogo_plantillas')
        .select('id, usuario_id, tipo, nombre, updated_at, deleted_at');
    final plantillasRaw = isoCursor != null
        ? await plantillasQuery.gt('updated_at', isoCursor)
        : await plantillasQuery;
    final plantillas = plantillasRaw.map(mapearPlantillaRemotaALocal).toList();

    // Tabla pequeña (1 fila por ingeniero) filtrada por RLS: se descarga
    // completa en cada Pull para que un capataz recién asignado a una obra
    // obtenga de inmediato el horario vigente de su ingeniero.
    final recordatoriosRaw = await _client
        .from('configuracion_recordatorio')
        .select('ingeniero_id, activo, hora, minuto, updated_at');
    final configuracionesRecordatorio =
        recordatoriosRaw.map(mapearConfigRecordatorioRemotaALocal).toList();

    return CambiosRemotos(
      roles: roles,
      usuarios: usuarios,
      obras: obras,
      tareas: tareas,
      reportes: reportes,
      notificaciones: notificaciones,
      plantillas: plantillas,
      configuracionesRecordatorio: configuracionesRecordatorio,
    );
  }

  bool _urlFirmadaProximaAVencer(Object? updatedAtRaw) {
    if (updatedAtRaw is! String || updatedAtRaw.isEmpty) return false;
    final fecha = DateTime.tryParse(updatedAtRaw);
    if (fecha == null) return false;
    final antiguedad = DateTime.now().toUtc().difference(fecha.toUtc());
    return antiguedad.inDays >= 6;
  }

  @override
  Stream<String> escucharCambiosRemotos() {
    RealtimeChannel? canal;
    late final StreamController<String> controlador;

    controlador = StreamController<String>.broadcast(
      onListen: () {
        if (!estaDisponible) return;
        final nombreCanal =
            'constructora_realtime_${DateTime.now().microsecondsSinceEpoch}';
        final nuevoCanal = _client.channel(nombreCanal);
        for (final tabla in _tablasRealtime) {
          nuevoCanal.onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: tabla,
            callback: (_) {
              if (!controlador.isClosed) {
                controlador.add(tabla);
              }
            },
          );
        }
        nuevoCanal.subscribe();
        canal = nuevoCanal;
      },
      onCancel: () {
        final activo = canal;
        canal = null;
        if (activo != null) {
          unawaited(_client.removeChannel(activo));
        }
      },
    );

    return controlador.stream;
  }
}

/// Quita el prefijo del bucket (`fotos-obras/`) si ya vino incluido en el path.
String normalizarRutaEnBucket({
  required String destinoStorage,
  required String bucket,
}) {
  final prefijo = '$bucket/';
  if (destinoStorage.startsWith(prefijo)) {
    return destinoStorage.substring(prefijo.length);
  }
  return destinoStorage;
}

bool _aBooleano(Object? valor) =>
    valor is bool ? valor : (valor as int? ?? 0) == 1;

int _aEnteroSqlite(Object? valor) =>
    valor is bool ? (valor ? 1 : 0) : (valor as int? ?? 0);

/// Convierte una fila local de `usuarios` al payload seguro de `public.usuarios`
/// (sin `contrasenia` ni `sync_status`).
Map<String, dynamic> mapearUsuarioLocalARemoto(Map<String, dynamic> local) => {
      'id': local['id'],
      'username': local['username'],
      'rol_id': local['rol_id'],
      'nombre': local['nombre'],
      'telefono': (local['telefono'] as String?) ?? '',
    };

Map<String, dynamic> mapearUsuarioRemotoALocal(Map<String, dynamic> remoto) => {
      'id': remoto['id'],
      'username': remoto['username'],
      'rol_id': remoto['rol_id'],
      'nombre': remoto['nombre'],
      'contrasenia': '',
      'telefono': (remoto['telefono'] as String?) ?? '',
      'updated_at': remoto['updated_at'],
      'sync_status': 'synced',
    };

Map<String, dynamic> mapearObraLocalARemoto(Map<String, dynamic> local) => {
      'id': local['id'],
      'nombre': local['nombre'],
      'estado_semaforo': local['estado_semaforo'],
      'fecha_ultimo_reporte': local['fecha_ultimo_reporte'],
      'responsable_id': local['responsable_id'],
      'ingeniero_id': local['ingeniero_id'],
      'tarea_actual_id': local['tarea_actual_id'],
      'ubicacion_latitud': local['ubicacion_latitud'],
      'ubicacion_longitud': local['ubicacion_longitud'],
      'ubicacion_direccion': local['ubicacion_direccion'],
      'observaciones': (local['observaciones'] as String?) ?? '',
      'con_foto': _aBooleano(local['con_foto']),
      'imagen': local['imagen'],
      'imagen_url': local['imagen_url'],
      'finalizada': _aBooleano(local['finalizada']),
      'deleted_at': local['deleted_at'],
    };

Map<String, dynamic> mapearObraRemotaALocal(Map<String, dynamic> remoto) {
  final materialesRaw =
      (remoto['obra_materiales'] as List<dynamic>? ?? const []);
  final tareasRaw = (remoto['tareas_obra'] as List<dynamic>? ?? const []);

  return {
    'id': remoto['id'],
    'nombre': remoto['nombre'],
    'estado_semaforo': remoto['estado_semaforo'],
    'fecha_ultimo_reporte': remoto['fecha_ultimo_reporte'],
    'responsable_id': remoto['responsable_id'],
    'ingeniero_id': remoto['ingeniero_id'],
    'tarea_actual_id': remoto['tarea_actual_id'],
    'ubicacion_latitud': (remoto['ubicacion_latitud'] as num).toDouble(),
    'ubicacion_longitud': (remoto['ubicacion_longitud'] as num).toDouble(),
    'ubicacion_direccion': remoto['ubicacion_direccion'],
    'observaciones': (remoto['observaciones'] as String?) ?? '',
    'con_foto': _aEnteroSqlite(remoto['con_foto']),
    'imagen': remoto['imagen'],
    'imagen_url': remoto['imagen_url'],
    'finalizada': _aEnteroSqlite(remoto['finalizada']),
    'updated_at': remoto['updated_at'],
    'sync_status': 'synced',
    'deleted_at': remoto['deleted_at'],
    'materiales': materialesRaw
        .map((m) => (m as Map<String, dynamic>)['nombre'] as String)
        .toList(),
    'tareas': tareasRaw
        .map((t) => mapearTareaRemotaALocal(t as Map<String, dynamic>))
        .toList(),
  };
}

Map<String, dynamic> mapearTareaLocalARemoto(Map<String, dynamic> local) => {
      'id': local['id'],
      'obra_id': local['obra_id'],
      'nombre': local['nombre'],
      'completada': _aBooleano(local['completada']),
      'orden': local['orden'] ?? 0,
    };

Map<String, dynamic> mapearTareaRemotaALocal(Map<String, dynamic> remoto) => {
      'id': remoto['id'],
      'obra_id': remoto['obra_id'],
      'nombre': remoto['nombre'],
      'completada': _aEnteroSqlite(remoto['completada']),
      'orden': remoto['orden'] ?? 0,
      'updated_at': remoto['updated_at'],
      'sync_status': 'synced',
    };

Map<String, dynamic> mapearReporteLocalARemoto(Map<String, dynamic> local) => {
      'id': local['id'],
      'obra_id': local['obra_id'],
      'autor_id': local['autor_id'],
      'fecha_creacion_local': local['fecha_creacion_local'],
      'tarea_seleccionada': local['tarea_seleccionada'],
      'tarea_completada': _aBooleano(local['tarea_completada']),
      'observaciones': (local['observaciones'] as String?) ?? '',
      'estado_semaforo': local['estado_semaforo'],
      'obra_finalizada': _aBooleano(local['obra_finalizada']),
    };

Map<String, dynamic> mapearFotoLocalARemoto(
  Map<String, dynamic> local, {
  required String reporteId,
  required String storagePath,
}) =>
    {
      'reporte_id': reporteId,
      'ruta_local': local['ruta_local'],
      'origen': local['origen'],
      'ancho_px': local['ancho_px'],
      'alto_px': local['alto_px'],
      'calidad_pct': local['calidad_pct'],
      'peso_kb': ((local['peso_kb'] as int?) ?? 100).clamp(1, 200),
      'url_remota': local['url_remota'],
      'storage_path': storagePath,
    };

Map<String, dynamic> mapearReporteRemotoALocal(Map<String, dynamic> remoto) {
  final materialesRaw =
      (remoto['reporte_materiales'] as List<dynamic>? ?? const []);
  final fotosRaw = (remoto['reporte_fotos'] as List<dynamic>? ?? const []);

  return {
    'id': remoto['id'],
    'obra_id': remoto['obra_id'],
    'autor_id': remoto['autor_id'],
    'fecha_creacion_local': remoto['fecha_creacion_local'],
    'fecha_sincronizacion': remoto['fecha_sincronizacion'],
    'tarea_seleccionada': remoto['tarea_seleccionada'],
    'tarea_completada': _aEnteroSqlite(remoto['tarea_completada']),
    'observaciones': (remoto['observaciones'] as String?) ?? '',
    'estado_semaforo': remoto['estado_semaforo'],
    'sync_status': 'synced',
    'obra_finalizada': _aEnteroSqlite(remoto['obra_finalizada']),
    'updated_at': remoto['updated_at'],
    'materiales': materialesRaw
        .map((m) => (m as Map<String, dynamic>)['nombre'] as String)
        .toList(),
    'fotos': fotosRaw
        .map(
          (f) => {
            'reporte_id': remoto['id'],
            'ruta_local': (f as Map<String, dynamic>)['ruta_local'] as String,
            'origen': f['origen'] as String,
            'ancho_px': f['ancho_px'] as int,
            'alto_px': f['alto_px'] as int,
            'calidad_pct': f['calidad_pct'] as int,
            'peso_kb': f['peso_kb'] as int,
            'bytes_base64': null,
            'url_remota': f['url_remota'] as String?,
            'storage_path': f['storage_path'] as String?,
            'estado_subida': 'synced',
          },
        )
        .toList(),
  };
}

Map<String, dynamic> mapearNotificacionLocalARemoto(
  Map<String, dynamic> local,
) =>
    {
      'id': local['id'],
      'obra_id': local['obra_id'],
      'emisor_id': local['emisor_id'],
      'titulo': local['titulo'],
      'mensaje': local['mensaje'],
      'destinatario': local['destinatario'],
      'fecha_hora': local['fecha_hora'],
      'es_alerta_semaforo': _aBooleano(local['es_alerta_semaforo']),
    };

Map<String, dynamic> mapearNotificacionRemotaALocal(
  Map<String, dynamic> remoto,
) =>
    {
      'id': remoto['id'],
      'obra_id': remoto['obra_id'],
      'emisor_id': remoto['emisor_id'],
      'titulo': remoto['titulo'],
      'mensaje': remoto['mensaje'],
      'destinatario': remoto['destinatario'],
      'fecha_hora': remoto['fecha_hora'],
      'es_alerta_semaforo': _aEnteroSqlite(remoto['es_alerta_semaforo']),
      'updated_at': remoto['updated_at'],
      'sync_status': 'synced',
    };

Map<String, dynamic> mapearConfigRecordatorioLocalARemoto(
  Map<String, dynamic> local,
) =>
    {
      'ingeniero_id': local['ingeniero_id'],
      'activo': _aBooleano(local['activo']),
      'hora': local['hora'],
      'minuto': local['minuto'],
    };

Map<String, dynamic> mapearConfigRecordatorioRemotaALocal(
  Map<String, dynamic> remoto,
) =>
    {
      'ingeniero_id': remoto['ingeniero_id'],
      'activo': _aEnteroSqlite(remoto['activo']),
      'hora': remoto['hora'] as int? ?? 18,
      'minuto': remoto['minuto'] as int? ?? 0,
      'updated_at': remoto['updated_at'],
      'sync_status': 'synced',
    };

Map<String, dynamic> mapearPlantillaLocalARemoto(Map<String, dynamic> local) =>
    {
      'id': local['id'],
      'usuario_id': local['usuario_id'],
      'tipo': local['tipo'],
      'nombre': local['nombre'],
      'deleted_at': local['deleted_at'],
    };

Map<String, dynamic> mapearPlantillaRemotaALocal(Map<String, dynamic> remoto) =>
    {
      'id': remoto['id'],
      'usuario_id': remoto['usuario_id'],
      'tipo': remoto['tipo'],
      'nombre': remoto['nombre'],
      'updated_at': remoto['updated_at'],
      'sync_status': 'synced',
      'deleted_at': remoto['deleted_at'],
    };
