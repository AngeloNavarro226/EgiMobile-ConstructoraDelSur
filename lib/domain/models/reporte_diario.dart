import 'dart:convert';
import 'dart:typed_data';

import 'obra.dart';

/// Estado de sincronización local-remoto para el flujo Offline-First.
enum EstadoSincronizacion {
  pending,
  synced;

  String get etiqueta => switch (this) {
        EstadoSincronizacion.pending => 'Pendiente de sincronizar',
        EstadoSincronizacion.synced => 'Sincronizado',
      };

  String toStorage() => name;

  static EstadoSincronizacion fromStorage(String valor) =>
      valor == 'synced'
          ? EstadoSincronizacion.synced
          : EstadoSincronizacion.pending;
}

/// Representa una fotografía comprimida (< 200 KB) y almacenada localmente
/// en la aplicación para que pueda visualizarse en cualquier informe diario.
class FotoComprimida {
  const FotoComprimida({
    required this.rutaLocal,
    required this.origen,
    required this.anchoPx,
    required this.altoPx,
    required this.calidadPct,
    required this.pesoKb,
    this.bytesBase64,
  });

  /// Ruta del asset de ejemplo (ej. `assets/images/obra1.png`) o ruta de archivo.
  final String rutaLocal;

  /// Descripción del origen (`Cámara en obra` o `Galería del dispositivo`).
  final String origen;

  final int anchoPx;
  final int altoPx;
  final int calidadPct;
  final int pesoKb;

  /// Bytes JPEG comprimidos codificados en Base64 para persistencia real en
  /// SQLite local y visualización directa mediante `Image.memory` en móvil y web.
  final String? bytesBase64;

  /// Devuelve los bytes decodificados si la foto fue tomada o cargada por el usuario.
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

  Map<String, dynamic> toJson() => {
        'rutaLocal': rutaLocal,
        'origen': origen,
        'anchoPx': anchoPx,
        'altoPx': altoPx,
        'calidadPct': calidadPct,
        'pesoKb': pesoKb,
        'bytesBase64': bytesBase64,
      };

  factory FotoComprimida.fromJson(Map<String, dynamic> json) => FotoComprimida(
        rutaLocal: (json['rutaLocal'] as String?) ?? 'assets/images/obra1.png',
        origen: (json['origen'] as String?) ?? 'Cámara',
        anchoPx: (json['anchoPx'] as int?) ?? 800,
        altoPx: (json['altoPx'] as int?) ?? 600,
        calidadPct: (json['calidadPct'] as int?) ?? 70,
        pesoKb: (json['pesoKb'] as int?) ?? 145,
        bytesBase64: json['bytesBase64'] as String?,
      );
}

/// Representa un informe diario cargado en terreno (`reportes_diarios`).
class ReporteDiario {
  const ReporteDiario({
    required this.id,
    required this.obraId,
    required this.obraNombre,
    required this.fechaCreacionLocal,
    this.fechaSincronizacion,
    required this.tareaSeleccionada,
    required this.tareaCompletadaEnInforme,
    required this.materialesUsados,
    required this.observaciones,
    required this.urlFotos,
    required this.estadoSemaforo,
    required this.autorNombre,
    this.syncStatus = EstadoSincronizacion.pending,
    this.obraFinalizada = false,
  });

  final String id;
  final String obraId;
  final String obraNombre;
  final DateTime fechaCreacionLocal;
  final DateTime? fechaSincronizacion;
  final String tareaSeleccionada;
  final bool tareaCompletadaEnInforme;
  final List<String> materialesUsados;
  final String observaciones;
  final List<FotoComprimida> urlFotos;
  final EstadoObra estadoSemaforo;
  final String autorNombre;
  final EstadoSincronizacion syncStatus;

  /// Indica si en este informe diario se marcó la obra como finalizada.
  final bool obraFinalizada;

  /// Crea una copia del reporte actualizando su estado de sincronización.
  ReporteDiario copyWith({
    DateTime? fechaSincronizacion,
    EstadoSincronizacion? syncStatus,
    bool? obraFinalizada,
  }) =>
      ReporteDiario(
        id: id,
        obraId: obraId,
        obraNombre: obraNombre,
        fechaCreacionLocal: fechaCreacionLocal,
        fechaSincronizacion: fechaSincronizacion ?? this.fechaSincronizacion,
        tareaSeleccionada: tareaSeleccionada,
        tareaCompletadaEnInforme: tareaCompletadaEnInforme,
        materialesUsados: materialesUsados,
        observaciones: observaciones,
        urlFotos: urlFotos,
        estadoSemaforo: estadoSemaforo,
        autorNombre: autorNombre,
        syncStatus: syncStatus ?? this.syncStatus,
        obraFinalizada: obraFinalizada ?? this.obraFinalizada,
      );

  /// Convierte el reporte a un mapa compatible con la tabla `reportes_diarios` de SQLite.
  Map<String, dynamic> toMap() => {
        'id': id,
        'obra_id': obraId,
        'obra_nombre': obraNombre,
        'fecha_creacion_local': fechaCreacionLocal.toIso8601String(),
        'fecha_sincronizacion': fechaSincronizacion?.toIso8601String(),
        'tareas': tareaSeleccionada,
        'tarea_completada': tareaCompletadaEnInforme ? 1 : 0,
        'materiales': jsonEncode(materialesUsados),
        'observaciones': observaciones,
        'url_fotos': jsonEncode(urlFotos.map((f) => f.toJson()).toList()),
        'estado_semaforo': estadoSemaforo.toStorage(),
        'autor_nombre': autorNombre,
        'sync_status': syncStatus.toStorage(),
        'obra_finalizada': obraFinalizada ? 1 : 0,
      };

  /// Reconstruye un [ReporteDiario] desde un registro de SQLite.
  factory ReporteDiario.fromMap(Map<String, dynamic> map) {
    final materialesLista =
        (jsonDecode(map['materiales'] as String) as List<dynamic>)
            .map((e) => e.toString())
            .toList();
    final fotosLista = (jsonDecode(map['url_fotos'] as String) as List<dynamic>)
        .map((e) => FotoComprimida.fromJson(e as Map<String, dynamic>))
        .toList();

    return ReporteDiario(
      id: map['id'] as String,
      obraId: map['obra_id'] as String,
      obraNombre: (map['obra_nombre'] as String?) ?? '',
      fechaCreacionLocal: DateTime.parse(map['fecha_creacion_local'] as String),
      fechaSincronizacion: map['fecha_sincronizacion'] != null
          ? DateTime.parse(map['fecha_sincronizacion'] as String)
          : null,
      tareaSeleccionada: map['tareas'] as String,
      tareaCompletadaEnInforme: (map['tarea_completada'] as int? ?? 0) == 1,
      materialesUsados: materialesLista,
      observaciones: (map['observaciones'] as String?) ?? '',
      urlFotos: fotosLista,
      estadoSemaforo: EstadoObra.fromStorage(
        (map['estado_semaforo'] as String?) ?? 'aTiempo',
      ),
      autorNombre: (map['autor_nombre'] as String?) ?? 'Capataz',
      syncStatus: EstadoSincronizacion.fromStorage(
        (map['sync_status'] as String?) ?? 'pending',
      ),
      obraFinalizada: (map['obra_finalizada'] as int? ?? 0) == 1,
    );
  }
}
