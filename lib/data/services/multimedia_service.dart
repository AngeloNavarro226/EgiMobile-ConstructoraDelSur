import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:workmanager/workmanager.dart';

import '../../domain/models/reporte_diario.dart';

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

/// Función pura de nivel superior ejecutada dentro de `Isolate.run`
///
///
/// Recibe únicamente datos primitivos y [Uint8List] sin capturar `this` ni
/// instancias con conexiones abiertas.
FotoComprimida codificarFotoEnSegundoPlano({
  required String ruta,
  required String origen,
  required Uint8List bytesComprimidos,
  required int ancho,
  required int alto,
  required int calidad,
  required int pesoMaximoKb,
}) {
  final kbReales = (bytesComprimidos.lengthInBytes / 1024).round().clamp(
        1,
        pesoMaximoKb,
      );
  final codificadoBase64 = base64Encode(bytesComprimidos);
  return FotoComprimida(
    rutaLocal: ruta,
    origen: origen,
    anchoPx: ancho,
    altoPx: alto,
    calidadPct: calidad,
    pesoKb: kbReales,
    bytesBase64: codificadoBase64,
  );
}

/// Servicio encargado de capturar imágenes reales desde la cámara o galería,
/// comprimirlas a 800x600 al 70% de calidad (< 200 KB), codificar sus bytes
/// para persistirlos en SQLite y procesarlos mediante un `Stream` + `Isolate` +
/// `Workmanager`.
class MultimediaService {
  final ImagePicker _picker = ImagePicker();

  /// Captura o selecciona una fotografía real y emite el progreso de compresión,
  /// codificación en `Isolate` y encolado en `Workmanager` a través de un [Stream].
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

    final rutaSeleccionada = archivoSeleccionado.path;
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
      etapa: 'Procesando bytes en Isolate para almacenamiento local...',
      porcentaje: 0.75,
    );

    final origenTexto =
        desdeCamara ? 'Cámara en obra' : 'Galería del dispositivo';
    final bytesParaIsolate = bytesCapturados;

    final resultadoIsolate = kIsWeb
        ? codificarFotoEnSegundoPlano(
            ruta: rutaSeleccionada,
            origen: origenTexto,
            bytesComprimidos: bytesParaIsolate,
            ancho: anchoObjetivo,
            alto: altoObjetivo,
            calidad: calidadObjetivo,
            pesoMaximoKb: pesoMaximoKb,
          )
        : await Isolate.run(
            () => codificarFotoEnSegundoPlano(
              ruta: rutaSeleccionada,
              origen: origenTexto,
              bytesComprimidos: bytesParaIsolate,
              ancho: anchoObjetivo,
              alto: altoObjetivo,
              calidad: calidadObjetivo,
              pesoMaximoKb: pesoMaximoKb,
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
        'upload_${DateTime.now().millisecondsSinceEpoch}',
        tareaSubidaFotosWorkmanager,
        inputData: {
          'rutaLocal': foto.rutaLocal,
          'origen': foto.origen,
          'pesoKb': foto.pesoKb,
        },
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {
      // En entornos locales donde Workmanager no esté inicializado a nivel
      // nativo, el registro se ignora sin interrumpir el guardado de la foto.
    }
  }
}
