import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/models/reporte_diario.dart';
import 'imagen_local_o_remota.dart';

/// Renderiza una miniatura interactiva de una [FotoComprimida] almacenada en la
/// aplicación (tanto si proviene de `bytesBase64` tomados con cámara/galería
/// como de `assets/images/`) y permite ampliarla a pantalla completa al tocarla.
class MiniaturaFotoInforme extends StatelessWidget {
  const MiniaturaFotoInforme({
    super.key,
    required this.foto,
    this.indice,
    this.onEliminar,
  });

  final FotoComprimida foto;
  final int? indice;
  final VoidCallback? onEliminar;

  void _abrirVistaCompleta(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppBar(
                  title: Text(
                    indice != null
                        ? 'Fotografía #${indice! + 1} (${foto.origen})'
                        : 'Fotografía de informe (${foto.origen})',
                    style: const TextStyle(fontSize: 15),
                  ),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ],
                ),
                Flexible(
                  child: Container(
                    color: Colors.black,
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4.0,
                      child: Center(
                        child: _ImagenDesdeFotoComprimida(
                          foto: foto,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Resolución: ${foto.anchoPx}x${foto.altoPx} px · '
                    'Calidad JPEG: ${foto.calidadPct}% · '
                    'Tamaño: ${foto.pesoKb} KB (< 200 KB)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _abrirVistaCompleta(context),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: _ImagenDesdeFotoComprimida(
                    foto: foto,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      indice != null
                          ? 'Foto #${indice! + 1} · ${foto.origen}'
                          : foto.origen,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${foto.anchoPx}x${foto.altoPx} px · Calidad ${foto.calidadPct}% · ${foto.pesoKb} KB',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tocá para ver la foto completa',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEliminar != null)
                IconButton(
                  tooltip: 'Quitar foto',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onEliminar,
                )
              else
                const Icon(Icons.zoom_in_outlined),
            ],
          ),
        ),
      ),
    );
  }
}

/// Galería horizontal de miniaturas para visualizar las fotografías adjuntas
/// dentro del informe completo y del historial de informes.
class GaleriaFotosInforme extends StatelessWidget {
  const GaleriaFotosInforme({
    super.key,
    required this.fotos,
  });

  final List<FotoComprimida> fotos;

  @override
  Widget build(BuildContext context) {
    if (fotos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Sin fotografías adjuntas en este informe.',
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < fotos.length; i++)
          MiniaturaFotoInforme(
            foto: fotos[i],
            indice: i,
          ),
      ],
    );
  }
}

class _ImagenDesdeFotoComprimida extends StatelessWidget {
  const _ImagenDesdeFotoComprimida({
    required this.foto,
    required this.fit,
  });

  final FotoComprimida foto;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return ImagenLocalORemota(
      bytesMemoria: foto.bytesImagen,
      rutaLocal: foto.rutaLocal,
      urlRemota: foto.urlRemota,
      fit: fit,
      placeholder: const _PlaceholderFotoError(),
    );
  }
}

class _PlaceholderFotoError extends StatelessWidget {
  const _PlaceholderFotoError();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: Icon(Icons.broken_image_outlined, size: 32),
      ),
    );
  }
}
