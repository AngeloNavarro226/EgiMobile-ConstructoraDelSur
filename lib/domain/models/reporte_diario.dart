import 'dart:convert';
import 'dart:typed_data';

import 'estado_sincronizacion.dart';
import 'obra.dart';

export 'estado_sincronizacion.dart';

/// Representa una fotografía comprimida (< 200 KB) almacenada en disco local
/// (`rutaLocal`) y preparada para subirse a Supabase Storage (`urlRemota`).
class FotoComprimida {
  const FotoComprimida({
    required this.rutaLocal,
    required this.origen,
    required this.anchoPx,
    required this.altoPx,
    required this.calidadPct,
    required this.pesoKb,
    this.bytesBase64,
    this.urlRemota,
    this.estadoSubida = EstadoSincronizacion.pending,
  });

  /// Ruta de archivo local en disco o asset de ejemplo (`assets/images/...`).
  final String rutaLocal;

  /// Descripción del origen (`Cámara en obra` o `Galería del dispositivo`).
  final String origen;

  final int anchoPx;
  final int altoPx;
  final int calidadPct;
  final int pesoKb;

  /// Bytes JPEG en Base64 usados únicamente como respaldo en Web o tests.
  final String? bytesBase64;

  /// URL pública o firmada en Supabase Storage una vez sincronizada.
  final String? urlRemota;

  /// Estado de subida de la fotografía al bucket remoto.
  final EstadoSincronizacion estadoSubida;

  /// Devuelve los bytes decodificados si la foto conserva Base64 en memoria.
  Uint8List? get bytesImagen {
    final codificado = bytesBase64;
    if (codificado == null || codificado.isEmpty) return null;
    try {
      return base64Decode(codificado);
    } catch (_) {
      return null;
    }
  }

  /// Indica si la foto apunta a una imagen incluida en los `assets/` del proyecto.
  bool get esAsset => rutaLocal.startsWith('assets/');

  /// Indica si ya cuenta con una URL remota en Storage.
  bool get tieneUrlRemota =>
      urlRemota != null &&
      (urlRemota!.startsWith('http://') || urlRemota!.startsWith('https://'));

  /// Indica si apunta a un archivo persistido en disco local.
  bool get esArchivoLocal =>
      rutaLocal.isNotEmpty &&
      !esAsset &&
      !rutaLocal.startsWith('http://') &&
      !rutaLocal.startsWith('https://');

  /// Crea una copia actualizando la URL remota o estado de subida.
  FotoComprimida copyWith({
    String? rutaLocal,
    String? urlRemota,
    EstadoSincronizacion? estadoSubida,
    String? bytesBase64,
  }) =>
      FotoComprimida(
        rutaLocal: rutaLocal ?? this.rutaLocal,
        origen: origen,
        anchoPx: anchoPx,
        altoPx: altoPx,
        calidadPct: calidadPct,
        pesoKb: pesoKb,
        bytesBase64: bytesBase64 ?? this.bytesBase64,
        urlRemota: urlRemota ?? this.urlRemota,
        estadoSubida: estadoSubida ?? this.estadoSubida,
      );

  /// Convierte la foto a una fila compatible con la tabla `reporte_fotos`.
  Map<String, dynamic> toMap({required String reporteId}) => {
        'reporte_id': reporteId,
        'ruta_local': rutaLocal,
        'origen': origen,
        'ancho_px': anchoPx,
        'alto_px': altoPx,
        'calidad_pct': calidadPct,
        'peso_kb': pesoKb,
        'bytes_base64': bytesBase64,
        'url_remota': urlRemota,
        'estado_subida': estadoSubida.toStorage(),
      };

  /// Reconstruye una [FotoComprimida] desde una fila de `reporte_fotos`.
  factory FotoComprimida.fromMap(Map<String, dynamic> map) => FotoComprimida(
        rutaLocal: (map['ruta_local'] as String?) ?? 'assets/images/obra1.png',
        origen: (map['origen'] as String?) ?? 'Cámara',
        anchoPx: (map['ancho_px'] as int?) ?? 800,
        altoPx: (map['alto_px'] as int?) ?? 600,
        calidadPct: (map['calidad_pct'] as int?) ?? 70,
        pesoKb: (map['peso_kb'] as int?) ?? 145,
        bytesBase64: map['bytes_base64'] as String?,
        urlRemota: map['url_remota'] as String?,
        estadoSubida: EstadoSincronizacion.fromStorage(
          (map['estado_subida'] as String?) ?? 'pending',
        ),
      );

  Map<String, dynamic> toJson() => {
        'rutaLocal': rutaLocal,
        'origen': origen,
        'anchoPx': anchoPx,
        'altoPx': altoPx,
        'calidadPct': calidadPct,
        'pesoKb': pesoKb,
        'bytesBase64': bytesBase64,
        'urlRemota': urlRemota,
        'estadoSubida': estadoSubida.toStorage(),
      };

  factory FotoComprimida.fromJson(Map<String, dynamic> json) => FotoComprimida(
        rutaLocal: (json['rutaLocal'] as String?) ?? 'assets/images/obra1.png',
        origen: (json['origen'] as String?) ?? 'Cámara',
        anchoPx: (json['anchoPx'] as int?) ?? 800,
        altoPx: (json['altoPx'] as int?) ?? 600,
        calidadPct: (json['calidadPct'] as int?) ?? 70,
        pesoKb: (json['pesoKb'] as int?) ?? 145,
        bytesBase64: json['bytesBase64'] as String?,
        urlRemota: json['urlRemota'] as String?,
        estadoSubida: EstadoSincronizacion.fromStorage(
          (json['estadoSubida'] as String?) ?? 'pending',
        ),
      );
}

/// Representa un informe diario cargado en terreno (`reportes_diarios`).
class ReporteDiario {
  const ReporteDiario({
    required this.id,
    required this.obraId,
    required this.obraNombre,
    required this.autorId,
    required this.autorNombre,
    required this.fechaCreacionLocal,
    this.fechaSincronizacion,
    required this.tareaSeleccionada,
    required this.tareaCompletadaEnInforme,
    required this.materialesUsados,
    required this.observaciones,
    required this.urlFotos,
    required this.estadoSemaforo,
    this.syncStatus = EstadoSincronizacion.pending,
    this.obraFinalizada = false,
    this.updatedAt,
  });

  final String id;
  final String obraId;
  final String obraNombre;
  final String autorId;
  final String autorNombre;
  final DateTime fechaCreacionLocal;
  final DateTime? fechaSincronizacion;
  final String tareaSeleccionada;
  final bool tareaCompletadaEnInforme;
  final List<String> materialesUsados;
  final String observaciones;
  final List<FotoComprimida> urlFotos;
  final EstadoObra estadoSemaforo;
  final EstadoSincronizacion syncStatus;

  /// Indica si en este informe diario se marcó la obra como finalizada.
  final bool obraFinalizada;

  /// Última marca de actualización en UTC para sincronización incremental.
  final DateTime? updatedAt;

  /// Crea una copia del reporte actualizando su estado de sincronización.
  ReporteDiario copyWith({
    DateTime? fechaSincronizacion,
    EstadoSincronizacion? syncStatus,
    bool? obraFinalizada,
    List<FotoComprimida>? urlFotos,
    DateTime? updatedAt,
  }) =>
      ReporteDiario(
        id: id,
        obraId: obraId,
        obraNombre: obraNombre,
        autorId: autorId,
        autorNombre: autorNombre,
        fechaCreacionLocal: fechaCreacionLocal,
        fechaSincronizacion: fechaSincronizacion ?? this.fechaSincronizacion,
        tareaSeleccionada: tareaSeleccionada,
        tareaCompletadaEnInforme: tareaCompletadaEnInforme,
        materialesUsados: materialesUsados,
        observaciones: observaciones,
        urlFotos: urlFotos ?? this.urlFotos,
        estadoSemaforo: estadoSemaforo,
        syncStatus: syncStatus ?? this.syncStatus,
        obraFinalizada: obraFinalizada ?? this.obraFinalizada,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Convierte el reporte a una fila normalizada para `reportes_diarios`.
  Map<String, dynamic> toMap() => {
        'id': id,
        'obra_id': obraId,
        'autor_id': autorId,
        'fecha_creacion_local': fechaCreacionLocal.toUtc().toIso8601String(),
        'fecha_sincronizacion': fechaSincronizacion?.toUtc().toIso8601String(),
        'tarea_seleccionada': tareaSeleccionada,
        'tarea_completada': tareaCompletadaEnInforme ? 1 : 0,
        'observaciones': observaciones,
        'estado_semaforo': estadoSemaforo.toStorage(),
        'sync_status': syncStatus.toStorage(),
        'obra_finalizada': obraFinalizada ? 1 : 0,
        'updated_at':
            (updatedAt ?? fechaCreacionLocal).toUtc().toIso8601String(),
      };

  /// Reconstruye un [ReporteDiario] desde una fila normalizada de SQLite
  /// enriquecida con `obra_nombre`, `autor_nombre`, `materiales` y `fotos`.
  factory ReporteDiario.fromMap(Map<String, dynamic> map) {
    final materialesLista = (map['materiales'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();
    final fotosLista = (map['fotos'] as List<dynamic>? ?? const [])
        .map((e) => FotoComprimida.fromMap(e as Map<String, dynamic>))
        .toList();
    final updatedAtRaw = map['updated_at'] as String?;

    return ReporteDiario(
      id: map['id'] as String,
      obraId: map['obra_id'] as String,
      obraNombre: (map['obra_nombre'] as String?) ?? '',
      autorId: map['autor_id'] as String,
      autorNombre: (map['autor_nombre'] as String?) ?? 'Capataz',
      fechaCreacionLocal: DateTime.parse(map['fecha_creacion_local'] as String),
      fechaSincronizacion: map['fecha_sincronizacion'] != null
          ? DateTime.parse(map['fecha_sincronizacion'] as String)
          : null,
      tareaSeleccionada: map['tarea_seleccionada'] as String,
      tareaCompletadaEnInforme: (map['tarea_completada'] as int? ?? 0) == 1,
      materialesUsados: materialesLista,
      observaciones: (map['observaciones'] as String?) ?? '',
      urlFotos: fotosLista,
      estadoSemaforo: EstadoObra.fromStorage(
        (map['estado_semaforo'] as String?) ?? 'aTiempo',
      ),
      syncStatus: EstadoSincronizacion.fromStorage(
        (map['sync_status'] as String?) ?? 'pending',
      ),
      obraFinalizada: (map['obra_finalizada'] as int? ?? 0) == 1,
      updatedAt: updatedAtRaw != null ? DateTime.parse(updatedAtRaw) : null,
    );
  }
}
