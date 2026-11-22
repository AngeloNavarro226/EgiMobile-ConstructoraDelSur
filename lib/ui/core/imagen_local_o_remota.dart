import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/services/plataforma_io_stub.dart'
    if (dart.library.io) '../../data/services/plataforma_io_real.dart'
    as plataforma_io;

/// Renderiza una imagen soportando múltiples fuentes Offline-First en cascada:
/// 1. Bytes en memoria ([bytesMemoria], ej. compatibilidad Web / Base64).
/// 2. Archivo local en disco ([rutaLocal] no-asset y no-URL).
/// 3. URL remota HTTP/HTTPS ([urlRemota], ej. Supabase Storage).
/// 4. Asset empaquetado (`assets/...`).
/// 5. [placeholder] ante ausencia o error de lectura.
class ImagenLocalORemota extends StatefulWidget {
  const ImagenLocalORemota({
    super.key,
    this.bytesMemoria,
    this.rutaLocal,
    this.urlRemota,
    this.fit = BoxFit.cover,
    required this.placeholder,
  });

  final Uint8List? bytesMemoria;
  final String? rutaLocal;
  final String? urlRemota;
  final BoxFit fit;
  final Widget placeholder;

  @override
  State<ImagenLocalORemota> createState() => _ImagenLocalORemotaState();
}

class _ImagenLocalORemotaState extends State<ImagenLocalORemota> {
  Future<Uint8List?>? _cargaLocal;

  bool get _esArchivoLocal {
    final ruta = widget.rutaLocal;
    if (ruta == null || ruta.isEmpty) return false;
    return !ruta.startsWith('assets/') &&
        !ruta.startsWith('http://') &&
        !ruta.startsWith('https://');
  }

  @override
  void initState() {
    super.initState();
    _prepararCargaLocal();
  }

  @override
  void didUpdateWidget(covariant ImagenLocalORemota oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rutaLocal != widget.rutaLocal) {
      _prepararCargaLocal();
    }
  }

  void _prepararCargaLocal() {
    if (widget.bytesMemoria == null && _esArchivoLocal) {
      _cargaLocal = plataforma_io.leerBytesDeArchivoLocal(widget.rutaLocal!);
    } else {
      _cargaLocal = null;
    }
  }

  Widget _construirRemotaOAsset() {
    final url = widget.urlRemota;
    if (url != null &&
        (url.startsWith('http://') || url.startsWith('https://'))) {
      return Image.network(
        url,
        fit: widget.fit,
        loadingBuilder: (context, child, progreso) {
          if (progreso == null) return child;
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        },
        errorBuilder: (_, __, ___) => widget.placeholder,
      );
    }

    final ruta = widget.rutaLocal;
    if (ruta != null && ruta.startsWith('assets/')) {
      return Image.asset(
        ruta,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => widget.placeholder,
      );
    }

    return widget.placeholder;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.bytesMemoria;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => _construirRemotaOAsset(),
      );
    }

    final carga = _cargaLocal;
    if (carga != null) {
      return FutureBuilder<Uint8List?>(
        future: carga,
        builder: (context, snapshot) {
          final bytesArchivo = snapshot.data;
          if (bytesArchivo != null && bytesArchivo.isNotEmpty) {
            return Image.memory(
              bytesArchivo,
              fit: widget.fit,
              errorBuilder: (_, __, ___) => _construirRemotaOAsset(),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          return _construirRemotaOAsset();
        },
      );
    }

    return _construirRemotaOAsset();
  }
}
