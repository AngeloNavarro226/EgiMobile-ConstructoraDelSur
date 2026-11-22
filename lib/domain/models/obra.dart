import 'dart:convert';
import 'dart:typed_data';

import 'estado_sincronizacion.dart';
import 'tarea_obra.dart';
import 'ubicacion_obra.dart';

/// Estado del sistema de semáforos para el monitoreo gerencial en tiempo real.
enum EstadoObra {
  aTiempo,
  demorada,
  problemas;

  /// Etiqueta legible para mostrar en los indicadores de estado.
  String get etiqueta => switch (this) {
        EstadoObra.aTiempo => 'A tiempo',
        EstadoObra.demorada => 'Demorada',
        EstadoObra.problemas => 'Con problemas',
      };

  /// Nombre del color del semáforo para alertas y reportes.
  String get nombreColor => switch (this) {
        EstadoObra.aTiempo => 'Verde',
        EstadoObra.demorada => 'Amarillo',
        EstadoObra.problemas => 'Rojo',
      };

  /// Indica si este estado requiere disparar una alerta proactiva a gerencia.
  bool get requiereAlertaProactiva =>
      this == EstadoObra.demorada || this == EstadoObra.problemas;

  String toStorage() => name;

  static EstadoObra fromStorage(String valor) => switch (valor) {
        'aTiempo' => EstadoObra.aTiempo,
        'demorada' => EstadoObra.demorada,
        _ => EstadoObra.problemas,
      };
}

/// Modelo de dominio de una Obra en ejecución.
///
/// Calcula automáticamente su porcentaje de [avance] en función de la
/// cantidad de tareas completadas dentro de [tareas], o 1.0 (100%) si la
/// obra fue marcada como [finalizada].
class Obra {
  const Obra({
    required this.id,
    required this.nombre,
    required this.estado,
    required this.fechaUltimoReporte,
    required this.responsableId,
    required this.responsableNombre,
    this.ingenieroId,
    this.ingenieroNombre,
    this.tareaActualId,
    required this.tareas,
    required this.materiales,
    required this.ubicacion,
    this.observaciones = '',
    this.conFoto = false,
    this.imagen,
    this.imagenUrl,
    this.finalizada = false,
    this.updatedAt,
    this.syncStatus = EstadoSincronizacion.synced,
    this.deletedAt,
  });

  final String id;
  final String nombre;
  final EstadoObra estado;
  final DateTime fechaUltimoReporte;
  final String responsableId;
  final String responsableNombre;

  /// Identificador (`FK -> usuarios.id`) del Ingeniero Jefe a cargo de la obra.
  final String? ingenieroId;

  /// Nombre resuelto vía `LEFT JOIN usuarios` del Ingeniero Jefe a cargo.
  final String? ingenieroNombre;

  /// Identificador opcional (`FK -> tareas_obra.id`) de la tarea elegida
  /// manualmente como "Tarea actual en curso".
  final String? tareaActualId;
  final List<TareaObra> tareas;
  final List<String> materiales;
  final UbicacionObra ubicacion;
  final String observaciones;
  final bool conFoto;

  /// Ruta local en disco, ruta de asset (`assets/images/obra1.png`) o cadena
  /// Base64 (compatibilidad web) de la foto de portada de la obra.
  final String? imagen;

  /// URL remota de Supabase Storage cuando la portada ya fue sincronizada.
  final String? imagenUrl;

  /// Indica si la obra fue marcada como finalizada.
  final bool finalizada;

  /// Última marca de tiempo de modificación en UTC para sincronización incremental.
  final DateTime? updatedAt;

  /// Estado de sincronización local-remoto de la obra.
  final EstadoSincronizacion syncStatus;

  /// Marca de borrado lógico en UTC (soft delete sincronizable).
  final DateTime? deletedAt;

  /// Indica si la portada apunta a un recurso remoto HTTP/HTTPS.
  bool get esImagenRemota {
    final url = imagenUrl ?? imagen;
    if (url == null || url.isEmpty) return false;
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// Indica si [imagen] apunta a un asset empaquetado de la aplicación.
  bool get esImagenAsset => imagen != null && imagen!.startsWith('assets/');

  /// Indica si [imagen] apunta a un archivo local en disco.
  bool get esArchivoLocal {
    final valor = imagen;
    if (valor == null || valor.isEmpty) return false;
    if (valor.startsWith('assets/') ||
        valor.startsWith('http://') ||
        valor.startsWith('https://')) {
      return false;
    }
    return bytesImagenPortada == null;
  }

  /// Si [imagen] contiene una fotografía personalizada codificada en Base64,
  /// devuelve sus bytes listos para renderizar con `Image.memory`.
  Uint8List? get bytesImagenPortada {
    final valor = imagen;
    if (valor == null ||
        valor.isEmpty ||
        valor.startsWith('assets/') ||
        valor.startsWith('http://') ||
        valor.startsWith('https://') ||
        valor.contains('/') ||
        valor.contains(r'\')) {
      return null;
    }
    try {
      return base64Decode(valor);
    } catch (_) {
      return null;
    }
  }

  /// Porcentaje de avance entre 0.0 y 1.0 calculado automáticamente
  /// según la proporción de tareas completadas (o 1.0 si está finalizada).
  double get avance {
    if (finalizada) return 1.0;
    if (tareas.isEmpty) return 0.0;
    final completadas = tareas.where((t) => t.completada).length;
    return completadas / tareas.length;
  }

  /// Porcentaje entero (0 a 100) listo para mostrar en etiquetas y reportes.
  int get porcentajeAvance => (avance * 100).round();

  /// Devuelve la tarea pendiente actualmente en curso: prioriza [tareaActualId]
  /// si existe y continúa pendiente, o cae a la primera tarea pendiente.
  TareaObra? get tareaActualObj {
    if (finalizada || tareas.isEmpty) return null;
    if (tareaActualId != null) {
      for (final tarea in tareas) {
        if (tarea.id == tareaActualId && !tarea.completada) {
          return tarea;
        }
      }
    }
    for (final tarea in tareas) {
      if (!tarea.completada) return tarea;
    }
    return null;
  }

  /// Devuelve el nombre de la tarea actualmente en curso (la elegida en
  /// [tareaActualId], o la primera pendiente, o el estado finalizado).
  String get tareaActual {
    if (finalizada) return 'Obra finalizada';
    if (tareas.isEmpty) return 'Sin tareas asignadas';
    final activa = tareaActualObj;
    if (activa != null) return activa.nombre;
    return '${tareas.last.nombre} (Finalizada)';
  }

  /// Lista de tareas que ya fueron completadas.
  List<TareaObra> get tareasCompletas =>
      tareas.where((t) => t.completada).toList();

  /// Lista de tareas que aún están pendientes de finalización.
  List<TareaObra> get tareasPendientes =>
      tareas.where((t) => !t.completada).toList();

  /// Crea una copia inmutable de la obra con los campos modificados.
  Obra copyWith({
    String? nombre,
    EstadoObra? estado,
    DateTime? fechaUltimoReporte,
    String? responsableId,
    String? responsableNombre,
    String? ingenieroId,
    String? ingenieroNombre,
    String? tareaActualId,
    bool limpiarTareaActual = false,
    List<TareaObra>? tareas,
    List<String>? materiales,
    UbicacionObra? ubicacion,
    String? observaciones,
    bool? conFoto,
    String? imagen,
    String? imagenUrl,
    bool? finalizada,
    DateTime? updatedAt,
    EstadoSincronizacion? syncStatus,
    DateTime? deletedAt,
  }) =>
      Obra(
        id: id,
        nombre: nombre ?? this.nombre,
        estado: estado ?? this.estado,
        fechaUltimoReporte: fechaUltimoReporte ?? this.fechaUltimoReporte,
        responsableId: responsableId ?? this.responsableId,
        responsableNombre: responsableNombre ?? this.responsableNombre,
        ingenieroId: ingenieroId ?? this.ingenieroId,
        ingenieroNombre: ingenieroNombre ?? this.ingenieroNombre,
        tareaActualId:
            limpiarTareaActual ? null : (tareaActualId ?? this.tareaActualId),
        tareas: tareas ?? this.tareas,
        materiales: materiales ?? this.materiales,
        ubicacion: ubicacion ?? this.ubicacion,
        observaciones: observaciones ?? this.observaciones,
        conFoto: conFoto ?? this.conFoto,
        imagen: imagen ?? this.imagen,
        imagenUrl: imagenUrl ?? this.imagenUrl,
        finalizada: finalizada ?? this.finalizada,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  /// Convierte la obra a una fila normalizada para la tabla `obras` de SQLite.
  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'estado_semaforo': estado.toStorage(),
        'fecha_ultimo_reporte': fechaUltimoReporte.toUtc().toIso8601String(),
        'responsable_id': responsableId,
        'ingeniero_id': ingenieroId,
        'tarea_actual_id': tareaActualId,
        'ubicacion_latitud': ubicacion.latitud,
        'ubicacion_longitud': ubicacion.longitud,
        'ubicacion_direccion': ubicacion.direccion,
        'observaciones': observaciones,
        'con_foto': conFoto ? 1 : 0,
        'imagen': imagen,
        'imagen_url': imagenUrl,
        'finalizada': finalizada ? 1 : 0,
        'updated_at':
            (updatedAt ?? fechaUltimoReporte).toUtc().toIso8601String(),
        'sync_status': syncStatus.toStorage(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      };

  /// Reconstruye una instancia de [Obra] desde un registro normalizado de SQLite
  /// enriquecido con `responsable_nombre`, `ingeniero_nombre`, `tareas` y
  /// `materiales`.
  factory Obra.fromMap(Map<String, dynamic> map) {
    final tareasLista = (map['tareas'] as List<dynamic>? ?? const [])
        .map((item) => TareaObra.fromMap(item as Map<String, dynamic>))
        .toList();
    final materialesLista = (map['materiales'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();

    final ubicacionDecodificada = UbicacionObra(
      latitud: (map['ubicacion_latitud'] as num).toDouble(),
      longitud: (map['ubicacion_longitud'] as num).toDouble(),
      direccion: map['ubicacion_direccion'] as String,
    );

    final updatedAtRaw = map['updated_at'] as String?;
    final deletedAtRaw = map['deleted_at'] as String?;

    return Obra(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      estado: EstadoObra.fromStorage(map['estado_semaforo'] as String),
      fechaUltimoReporte: DateTime.parse(map['fecha_ultimo_reporte'] as String),
      responsableId: map['responsable_id'] as String,
      responsableNombre: (map['responsable_nombre'] as String?) ?? 'Capataz',
      ingenieroId: map['ingeniero_id'] as String?,
      ingenieroNombre: map['ingeniero_nombre'] as String?,
      tareaActualId: map['tarea_actual_id'] as String?,
      tareas: tareasLista,
      materiales: materialesLista,
      ubicacion: ubicacionDecodificada,
      observaciones: (map['observaciones'] as String?) ?? '',
      conFoto: (map['con_foto'] as int? ?? 0) == 1,
      imagen: map['imagen'] as String?,
      imagenUrl: map['imagen_url'] as String?,
      finalizada: (map['finalizada'] as int? ?? 0) == 1,
      updatedAt: updatedAtRaw != null ? DateTime.parse(updatedAtRaw) : null,
      syncStatus: EstadoSincronizacion.fromStorage(
        (map['sync_status'] as String?) ?? 'synced',
      ),
      deletedAt: deletedAtRaw != null ? DateTime.parse(deletedAtRaw) : null,
    );
  }
}
