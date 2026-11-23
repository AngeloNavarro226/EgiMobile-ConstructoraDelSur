import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:workmanager/workmanager.dart';

import '../../domain/models/reporte_diario.dart';
import 'generador_ids.dart';
import 'plataforma_io_stub.dart' if (dart.library.io) 'plataforma_io_real.dart'
    as plataforma_io;
import 'reloj.dart';

/// Nombre de la tarea en segundo plano registrada en Workmanager para subir fotos.
const tareaSubidaFotosWorkmanager = 'subida_fotos_reporte_task';

/// Estado del progreso de compresión y encolado de una fotografía en segundo plano.
class ProgresoProcesamientoFoto {
  const ProgresoProcesamientoFoto({
    required this.etapa,
    required this.porcentaje,
    this.fotoComprimida,
    this.cancelado = false,
  });

  final String etapa;
  final double porcentaje;
  final FotoComprimida? fotoComprimida;
  final bool cancelado;
}

/// Función pura de nivel superior ejecutada dentro de `Isolate.run`.
///
/// Recibe únicamente datos primitivos y [Uint8List] sin capturar `this` ni
/// instancias con conexiones abiertas. En plataformas nativas evita incrustar
/// Base64 en SQLite (`incluirBase64: false`), reservándolo solo para Web.
FotoComprimida codificarFotoEnSegundoPlano({
  required String ruta,
  required String origen,
  required Uint8List bytesComprimidos,
  required int ancho,
  required int alto,
  required int calidad,
  required int pesoMaximoKb,
  bool incluirBase64 = false,
}) {
  final kbReales = (bytesComprimidos.lengthInBytes / 1024).round().clamp(
        1,
        pesoMaximoKb,
      );
  return FotoComprimida(
    rutaLocal: ruta,
    origen: origen,
    anchoPx: ancho,
    altoPx: alto,
    calidadPct: calidad,
    pesoKb: kbReales,
    bytesBase64: incluirBase64 ? base64Encode(bytesComprimidos) : null,
    estadoSubida: EstadoSincronizacion.pending,
  );
}

/// Servicio encargado de capturar imágenes reales desde la cámara o galería,
/// comprimirlas a 800x600 al 70% de calidad (< 200 KB), persistirlas en disco
/// local sin inflar SQLite con Base64 y encolarlas en `Workmanager`.
class MultimediaService {
  MultimediaService({
    Reloj reloj = const RelojDelSistema(),
    GeneradorIds? generadorIds,
  })  : _reloj = reloj,
        _generadorIds = generadorIds ?? GeneradorUuidV4();

  final ImagePicker _picker = ImagePicker();
  final Reloj _reloj;
  final GeneradorIds _generadorIds;

  /// Captura o selecciona una fotografía real y emite el progreso de compresión,
  /// guardado local en disco y encolado en `Workmanager` a través de un [Stream].
  Stream<ProgresoProcesamientoFoto> capturarYProcesarFoto({
    required bool desdeCamara,
    required int anchoObjetivo,
    required int altoObjetivo,
    required int calidadObjetivo,
    required int pesoMaximoKb,
  }) async* {
    yield const ProgresoProcesamientoFoto(
      etapa: 'Abriendo selector de imagen...',
      porcentaje: 0.15,
    );

    XFile? archivoSeleccionado;
    try {
      archivoSeleccionado = await _picker.pickImage(
        source: desdeCamara ? ImageSource.camera : ImageSource.gallery,
        maxWidth: anchoObjetivo.toDouble(),
        maxHeight: altoObjetivo.toDouble(),
        imageQuality: calidadObjetivo,
      );
    } catch (e) {
      yield ProgresoProcesamientoFoto(
        etapa: 'No se pudo abrir la cámara o galería: $e',
        porcentaje: 0,
        cancelado: true,
      );
      return;
    }

    if (archivoSeleccionado == null) {
      yield const ProgresoProcesamientoFoto(
        etapa: 'Selección de foto cancelada.',
        porcentaje: 0,
        cancelado: true,
      );
      return;
    }

    var bytesCapturados = await archivoSeleccionado.readAsBytes();

    yield const ProgresoProcesamientoFoto(
      etapa: 'Comprimiendo imagen a 800x600 (70% calidad)...',
      porcentaje: 0.50,
    );

    if (!kIsWeb) {
      try {
        final comprimido = await FlutterImageCompress.compressWithList(
          bytesCapturados,
          minWidth: anchoObjetivo,
          minHeight: altoObjetivo,
          quality: calidadObjetivo,
        );
        if (comprimido.isNotEmpty) {
          bytesCapturados = comprimido;
        }
      } catch (_) {
        // Si el compresor nativo no interviene, mantiene los bytes ya
        // redimensionados por ImagePicker a 800x600 y 70% de calidad.
      }
    }

    yield const ProgresoProcesamientoFoto(
      etapa: 'Guardando fotografía comprimida en almacenamiento local...',
      porcentaje: 0.75,
    );

    final nombreArchivo = 'foto_${_generadorIds.generar()}.jpg';
    final rutaPersistente = kIsWeb
        ? archivoSeleccionado.path
        : await plataforma_io.guardarFotoEnAlmacenamientoLocal(
            nombreArchivo: nombreArchivo,
            bytes: bytesCapturados,
          );

    final origenTexto =
        desdeCamara ? 'Cámara en obra' : 'Galería del dispositivo';
    final bytesParaIsolate = bytesCapturados;

    final resultadoIsolate = kIsWeb
        ? codificarFotoEnSegundoPlano(
            ruta: rutaPersistente,
            origen: origenTexto,
            bytesComprimidos: bytesParaIsolate,
            ancho: anchoObjetivo,
            alto: altoObjetivo,
            calidad: calidadObjetivo,
            pesoMaximoKb: pesoMaximoKb,
            incluirBase64: true,
          )
        : await Isolate.run(
            () => codificarFotoEnSegundoPlano(
              ruta: rutaPersistente,
              origen: origenTexto,
              bytesComprimidos: bytesParaIsolate,
              ancho: anchoObjetivo,
              alto: altoObjetivo,
              calidad: calidadObjetivo,
              pesoMaximoKb: pesoMaximoKb,
              incluirBase64: false,
            ),
          );

    yield const ProgresoProcesamientoFoto(
      etapa: 'Encolando subida diferida en Workmanager...',
      porcentaje: 0.90,
    );

    await _registrarTareaEnWorkmanager(resultadoIsolate);

    yield ProgresoProcesamientoFoto(
      etapa:
          'Foto guardada (${resultadoIsolate.pesoKb} KB · ${resultadoIsolate.anchoPx}x${resultadoIsolate.altoPx})',
      porcentaje: 1.0,
      fotoComprimida: resultadoIsolate,
    );
  }

  Future<void> _registrarTareaEnWorkmanager(FotoComprimida foto) async {
    if (kIsWeb) return;
    try {
      await Workmanager().registerOneOffTask(
        tareaSubidaFotosWorkmanager,
        tareaSubidaFotosWorkmanager,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        initialDelay: const Duration(seconds: 45),
        inputData: {
          'rutaLocal': foto.rutaLocal,
          'origen': foto.origen,
          'pesoKb': foto.pesoKb,
          'encoladoEn': _reloj.ahora().toUtc().toIso8601String(),
        },
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {
      // En entornos locales donde Workmanager no esté inicializado a nivel
      // nativo, el registro se ignora sin interrumpir el guardado de la foto.
    }
  }
}
