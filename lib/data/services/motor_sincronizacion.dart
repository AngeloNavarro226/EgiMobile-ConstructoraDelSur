import 'dart:convert';
import 'dart:typed_data';

import '../../domain/models/evento_de_app.dart';
import 'base_datos_local_service.dart';
import 'bus_de_eventos.dart';
import 'fuente_datos_remota.dart';
import 'plataforma_io_stub.dart' if (dart.library.io) 'plataforma_io_real.dart'
    as plataforma_io;
import 'reloj.dart';

/// Resultado consolidado de un ciclo Push -> Pull del motor Offline-First.
class ResultadoSincronizacion {
  const ResultadoSincronizacion({
    required this.sincronizados,
    required this.fallidos,
    this.cambiosDescargados = 0,
    this.mensajeError,
    this.omitidoPorConcurrencia = false,
  });

  final int sincronizados;
  final int fallidos;
  final int cambiosDescargados;
  final String? mensajeError;
  final bool omitidoPorConcurrencia;

  bool get tuvoErrores => fallidos > 0 || mensajeError != null;
}

/// Motor bidireccional de sincronización Offline-First (Push -> Pull).
///
/// Garantiza:
/// - Exclusión mutua (`_enProgreso`) para evitar sincronizaciones solapadas.
/// - Subida de fotos comprimidas a Storage antes del `upsert` del reporte.
/// - Reintentos y trazabilidad por elemento en `cola_sincronizacion`.
/// - Estrategia *local-pending wins* en *Pull* para nunca pisar trabajo local
///   no sincronizado.
class MotorSincronizacion {
  MotorSincronizacion({
    required BaseDatosLocalService baseDatosLocal,
    FuenteDatosRemota fuenteRemota = const FuenteDatosRemotaOffline(),
    Reloj reloj = const RelojDelSistema(),
    BusDeEventos? busDeEventos,
  })  : _local = baseDatosLocal,
        _remoto = fuenteRemota,
        _reloj = reloj,
        _bus = busDeEventos;

  final BaseDatosLocalService _local;
  final FuenteDatosRemota _remoto;
  final Reloj _reloj;
  final BusDeEventos? _bus;

  bool _enProgreso = false;

  /// Indica si hay un ciclo de sincronización ejecutándose actualmente.
  bool get enProgreso => _enProgreso;

  /// Flujo en tiempo real de tablas modificadas en el servidor remoto.
  Stream<String> escucharCambiosRemotos() => _remoto.escucharCambiosRemotos();

  /// Ejecuta el ciclo completo **Push -> Pull**.
  ///
  /// Cuando [_remoto] es [FuenteDatosRemotaOffline] (`estaDisponible == false`),
  /// si [permitirSimulacionLocal] es `true` marca los reportes pendientes
  /// localmente para preservar el flujo demo previo a la conexión con Supabase.
  Future<ResultadoSincronizacion> sincronizarTodo({
    bool permitirSimulacionLocal = false,
  }) async {
    if (_enProgreso) {
      return const ResultadoSincronizacion(
        sincronizados: 0,
        fallidos: 0,
        omitidoPorConcurrencia: true,
      );
    }

    _enProgreso = true;
    try {
      final ahoraUtc = _reloj.ahora().toUtc();

      if (!_remoto.estaDisponible) {
        if (!permitirSimulacionLocal) {
          return const ResultadoSincronizacion(
            sincronizados: 0,
            fallidos: 0,
          );
        }
        final cantidad = await _local.marcarReportesComoSincronizados(ahoraUtc);
        _bus?.emitir(SincronizacionCompletada(cantidad));
        return ResultadoSincronizacion(
          sincronizados: cantidad,
          fallidos: 0,
        );
      }

      var sincronizados = 0;
      var fallidos = 0;
      String? primerError;

      void registrarError(String detalle) {
        fallidos++;
        primerError ??= detalle;
      }

      // 1. Push usuarios pendientes
      for (final usuario in await _local.obtenerPendientesDeTabla('usuarios')) {
        final id = usuario['id'] as String;
        try {
          await _remoto.upsertUsuario(usuario);
          await _local.marcarEntidadSincronizada(tabla: 'usuarios', id: id);
          await _local.limpiarFalloSincronizacion(
            entidad: 'usuarios',
            entidadId: id,
          );
          sincronizados++;
        } catch (e) {
          await _local.registrarFalloSincronizacion(
            entidad: 'usuarios',
            entidadId: id,
            operacion: 'upsert',
            error: e.toString(),
          );
          registrarError('Error al sincronizar usuario $id: $e');
        }
      }

      // 2. Push obras pendientes (subiendo antes su foto de portada si es local)
      for (final obraCruda in await _local.obtenerPendientesDeTabla('obras')) {
        final obra = Map<String, dynamic>.from(obraCruda);
        final id = obra['id'] as String;
        try {
          final imagenLocal = (obra['imagen'] as String?) ?? '';
          final imagenUrlActual = (obra['imagen_url'] as String?) ?? '';
          final requiereSubidaPortada = imagenLocal.isNotEmpty &&
              !imagenLocal.startsWith('assets/') &&
              !imagenLocal.startsWith('http://') &&
              !imagenLocal.startsWith('https://') &&
              imagenUrlActual.isEmpty;

          if (requiereSubidaPortada) {
            final bytesPortada = await _resolverBytesPortada(imagenLocal);
            if (bytesPortada != null && bytesPortada.isNotEmpty) {
              final urlRemota = await _remoto.subirFoto(
                rutaLocal: imagenLocal,
                destinoStorage: 'fotos-obras/portadas/$id.jpg',
                bytes: bytesPortada,
              );
              await _local.actualizarImagenUrlObra(
                obraId: id,
                imagenUrl: urlRemota,
              );
              obra['imagen_url'] = urlRemota;
            }
          }

          final materiales = await _local.obtenerMaterialesDeObra(id);
          final tareasPendientesActuales =
              await _local.obtenerPendientesDeTabla('tareas_obra');
          final tareaActualId = obra['tarea_actual_id'] as String?;
          final tareaActualPendiente = tareaActualId != null &&
              tareasPendientesActuales.any((t) => t['id'] == tareaActualId);

          if (tareaActualPendiente) {
            final obraSinTareaActual = Map<String, dynamic>.from(obra)
              ..['tarea_actual_id'] = null;
            await _remoto.upsertObra(
              obra: obraSinTareaActual,
              materiales: materiales,
            );
            for (final tarea
                in tareasPendientesActuales.where((t) => t['obra_id'] == id)) {
              final tId = tarea['id'] as String;
              await _remoto.upsertTarea(tarea);
              await _local.marcarEntidadSincronizada(
                tabla: 'tareas_obra',
                id: tId,
              );
              await _local.limpiarFalloSincronizacion(
                entidad: 'tareas_obra',
                entidadId: tId,
              );
              sincronizados++;
            }
          }

          await _remoto.upsertObra(obra: obra, materiales: materiales);
          await _local.marcarEntidadSincronizada(tabla: 'obras', id: id);
          await _local.limpiarFalloSincronizacion(
            entidad: 'obras',
            entidadId: id,
          );
          sincronizados++;
        } catch (e) {
          await _local.registrarFalloSincronizacion(
            entidad: 'obras',
            entidadId: id,
            operacion: 'upsert',
            error: e.toString(),
          );
          registrarError('Error al sincronizar obra $id: $e');
        }
      }

      // 3. Push tareas individuales pendientes
      for (final tarea
          in await _local.obtenerPendientesDeTabla('tareas_obra')) {
        final id = tarea['id'] as String;
        try {
          await _remoto.upsertTarea(tarea);
          await _local.marcarEntidadSincronizada(tabla: 'tareas_obra', id: id);
          await _local.limpiarFalloSincronizacion(
            entidad: 'tareas_obra',
            entidadId: id,
          );
          sincronizados++;
        } catch (e) {
          await _local.registrarFalloSincronizacion(
            entidad: 'tareas_obra',
            entidadId: id,
            operacion: 'upsert',
            error: e.toString(),
          );
          registrarError('Error al sincronizar tarea $id: $e');
        }
      }

      // 4. Push reportes pendientes (subiendo primero sus fotos a Storage)
      for (final reporte
          in await _local.obtenerPendientesDeTabla('reportes_diarios')) {
        final id = reporte['id'] as String;
        final obraId = reporte['obra_id'] as String;
        try {
          final materiales = await _local.obtenerMaterialesDeReporte(id);
          final fotos = await _local.obtenerFotosDeReporte(id);
          final fotosActualizadas = <Map<String, dynamic>>[];

          for (var i = 0; i < fotos.length; i++) {
            final foto = Map<String, dynamic>.from(fotos[i]);
            final rutaLocal = (foto['ruta_local'] as String?) ?? '';
            final yaSubida = foto['estado_subida'] == 'synced' &&
                (foto['url_remota'] as String?)?.isNotEmpty == true;
            final esAsset = rutaLocal.startsWith('assets/');

            if (!yaSubida && !esAsset && rutaLocal.isNotEmpty) {
              final bytes = await _resolverBytesFoto(foto);
              final urlRemota = await _remoto.subirFoto(
                rutaLocal: rutaLocal,
                destinoStorage: 'fotos-obras/$obraId/${id}_$i.jpg',
                bytes: bytes,
              );
              await _local.actualizarFotoSincronizada(
                reporteId: id,
                rutaLocal: rutaLocal,
                urlRemota: urlRemota,
              );
              foto['url_remota'] = urlRemota;
              foto['estado_subida'] = 'synced';
              foto['bytes_base64'] = null;
            }
            fotosActualizadas.add(foto);
          }

          await _remoto.upsertReporte(
            reporte: reporte,
            materiales: materiales,
            fotos: fotosActualizadas,
          );
          await _local.marcarEntidadSincronizada(
            tabla: 'reportes_diarios',
            id: id,
            fechaSyncUtc: ahoraUtc,
          );
          await _local.limpiarFalloSincronizacion(
            entidad: 'reportes_diarios',
            entidadId: id,
          );
          sincronizados++;
        } catch (e) {
          await _local.registrarFalloSincronizacion(
            entidad: 'reportes_diarios',
            entidadId: id,
            operacion: 'upsert',
            error: e.toString(),
          );
          registrarError('Error al sincronizar reporte $id: $e');
        }
      }

      // 5. Push notificaciones pendientes
      for (final notif
          in await _local.obtenerPendientesDeTabla('notificaciones')) {
        final id = notif['id'] as String;
        try {
          await _remoto.upsertNotificacion(notif);
          await _local.marcarEntidadSincronizada(
            tabla: 'notificaciones',
            id: id,
          );
          await _local.limpiarFalloSincronizacion(
            entidad: 'notificaciones',
            entidadId: id,
          );
          sincronizados++;
        } catch (e) {
          await _local.registrarFalloSincronizacion(
            entidad: 'notificaciones',
            entidadId: id,
            operacion: 'upsert',
            error: e.toString(),
          );
          registrarError('Error al sincronizar notificación $id: $e');
        }
      }

      // 5b. Push catálogo de plantillas personales pendientes
      for (final plantilla
          in await _local.obtenerPendientesDeTabla('catalogo_plantillas')) {
        final id = plantilla['id'] as String;
        try {
          await _remoto.upsertPlantilla(plantilla);
          await _local.marcarEntidadSincronizada(
            tabla: 'catalogo_plantillas',
            id: id,
          );
          await _local.limpiarFalloSincronizacion(
            entidad: 'catalogo_plantillas',
            entidadId: id,
          );
          sincronizados++;
        } catch (e) {
          await _local.registrarFalloSincronizacion(
            entidad: 'catalogo_plantillas',
            entidadId: id,
            operacion: 'upsert',
            error: e.toString(),
          );
          registrarError('Error al sincronizar plantilla $id: $e');
        }
      }

      // 5c. Push configuraciones de recordatorio diario por ingeniero pendientes
      for (final config in await _local
          .obtenerPendientesDeTabla('configuracion_recordatorio')) {
        final ingenieroId = config['ingeniero_id'] as String;
        try {
          await _remoto.upsertConfiguracionRecordatorio(config);
          await _local.marcarEntidadSincronizada(
            tabla: 'configuracion_recordatorio',
            id: ingenieroId,
          );
          await _local.limpiarFalloSincronizacion(
            entidad: 'configuracion_recordatorio',
            entidadId: ingenieroId,
          );
          sincronizados++;
        } catch (e) {
          await _local.registrarFalloSincronizacion(
            entidad: 'configuracion_recordatorio',
            entidadId: ingenieroId,
            operacion: 'upsert',
            error: e.toString(),
          );
          registrarError(
            'Error al sincronizar recordatorio de $ingenieroId: $e',
          );
        }
      }

      // 6. Pull incremental respetando local-pending wins (con margen de 60 s
      // para absorber desfases de reloj entre dispositivos y PostgreSQL)
      var descargados = 0;
      try {
        final ultimaSync = await _local.obtenerUltimaSyncUtc();
        final cursorConMargen =
            ultimaSync?.subtract(const Duration(seconds: 60));
        final cambios = await _remoto.obtenerCambiosDesde(cursorConMargen);
        descargados = await _aplicarCambiosRemotos(cambios);
        if (fallidos == 0) {
          await _local.guardarUltimaSyncUtc(ahoraUtc);
        }
      } catch (e) {
        registrarError('Error al descargar cambios remotos: $e');
      }

      if (fallidos > 0 && primerError != null) {
        _bus?.emitir(ErrorSincronizacion(primerError!));
      } else {
        _bus?.emitir(SincronizacionCompletada(sincronizados));
      }

      return ResultadoSincronizacion(
        sincronizados: sincronizados,
        fallidos: fallidos,
        cambiosDescargados: descargados,
        mensajeError: primerError,
      );
    } finally {
      _enProgreso = false;
    }
  }

  Future<Uint8List?> _resolverBytesPortada(String imagen) async {
    final desdeArchivo = await plataforma_io.leerBytesDeArchivoLocal(imagen);
    if (desdeArchivo != null && desdeArchivo.isNotEmpty) {
      return desdeArchivo;
    }
    if (!imagen.contains('/') && !imagen.contains(r'\')) {
      try {
        return base64Decode(imagen);
      } catch (_) {}
    }
    return null;
  }

  Future<Uint8List?> _resolverBytesFoto(Map<String, dynamic> foto) async {
    final base64Str = foto['bytes_base64'] as String?;
    if (base64Str != null && base64Str.isNotEmpty) {
      try {
        return base64Decode(base64Str);
      } catch (_) {}
    }
    final rutaLocal = foto['ruta_local'] as String?;
    if (rutaLocal != null && rutaLocal.isNotEmpty) {
      return plataforma_io.leerBytesDeArchivoLocal(rutaLocal);
    }
    return null;
  }

  Future<int> _aplicarCambiosRemotos(CambiosRemotos cambios) async {
    if (cambios.estaVacio) return 0;
    var aplicados = 0;

    for (final rol in cambios.roles) {
      await _local.guardarRolCrudo(rol);
      aplicados++;
    }

    for (final usuario in cambios.usuarios) {
      final id = usuario['id'] as String;
      if (await _local.estaPendienteLocal(tabla: 'usuarios', id: id)) {
        continue;
      }
      await _local.guardarUsuarioCrudo({...usuario, 'sync_status': 'synced'});
      aplicados++;
    }

    for (final obraRemota in cambios.obras) {
      final id = obraRemota['id'] as String;
      if (await _local.estaPendienteLocal(tabla: 'obras', id: id)) {
        continue;
      }
      final materiales =
          (obraRemota['materiales'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList();
      final tareas = (obraRemota['tareas'] as List<dynamic>? ?? const [])
          .map((t) => Map<String, dynamic>.from(t as Map<String, dynamic>))
          .toList();
      final filaObra = Map<String, dynamic>.from(obraRemota)
        ..remove('materiales')
        ..remove('tareas')
        ..['sync_status'] = 'synced';
      await _local.guardarObraCruda(
        obra: filaObra,
        tareas: tareas,
        materiales: materiales,
      );
      aplicados++;
    }

    for (final tarea in cambios.tareas) {
      final id = tarea['id'] as String;
      if (await _local.estaPendienteLocal(tabla: 'tareas_obra', id: id)) {
        continue;
      }
      await _local.insertarTareaCruda({...tarea, 'sync_status': 'synced'});
      aplicados++;
    }

    for (final reporteRemoto in cambios.reportes) {
      final id = reporteRemoto['id'] as String;
      if (await _local.estaPendienteLocal(tabla: 'reportes_diarios', id: id)) {
        continue;
      }
      final materiales =
          (reporteRemoto['materiales'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList();
      final fotos = (reporteRemoto['fotos'] as List<dynamic>? ?? const [])
          .map((f) => Map<String, dynamic>.from(f as Map<String, dynamic>))
          .toList();
      final filaReporte = Map<String, dynamic>.from(reporteRemoto)
        ..remove('materiales')
        ..remove('fotos')
        ..['sync_status'] = 'synced';
      await _local.guardarReporteCrudo(
        reporte: filaReporte,
        materiales: materiales,
        fotos: fotos,
      );
      aplicados++;
    }

    for (final notif in cambios.notificaciones) {
      final id = notif['id'] as String;
      if (await _local.estaPendienteLocal(tabla: 'notificaciones', id: id)) {
        continue;
      }
      await _local
          .guardarNotificacionCruda({...notif, 'sync_status': 'synced'});
      aplicados++;
    }

    for (final plantilla in cambios.plantillas) {
      final id = plantilla['id'] as String;
      if (await _local.estaPendienteLocal(
        tabla: 'catalogo_plantillas',
        id: id,
      )) {
        continue;
      }
      await _local
          .guardarPlantillaCruda({...plantilla, 'sync_status': 'synced'});
      aplicados++;
    }

    for (final config in cambios.configuracionesRecordatorio) {
      final ingenieroId = config['ingeniero_id'] as String;
      if (await _local.estaPendienteLocal(
        tabla: 'configuracion_recordatorio',
        id: ingenieroId,
      )) {
        continue;
      }
      await _local.guardarConfiguracionRecordatorioCruda({
        ...config,
        'sync_status': 'synced',
      });
      aplicados++;
    }

    return aplicados;
  }
}
