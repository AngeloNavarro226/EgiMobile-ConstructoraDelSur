import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as osm;

import '../../domain/models/ubicacion_obra.dart';

/// Diálogo interactivo de mapa de calles (OpenStreetMap) que permite marcar
/// la ubicación de una obra y transcribe automáticamente el nombre del lugar
/// a partir de las coordenadas seleccionadas.
class SelectorUbicacionMapaDialog extends StatefulWidget {
  const SelectorUbicacionMapaDialog({
    super.key,
    required this.ubicacionInicial,
    required this.ubicacionesSugeridas,
    required this.onResolverNombreLugar,
  });

  final UbicacionObra ubicacionInicial;
  final List<UbicacionObra> ubicacionesSugeridas;
  final Future<String> Function(double latitud, double longitud)
      onResolverNombreLugar;

  @override
  State<SelectorUbicacionMapaDialog> createState() =>
      _SelectorUbicacionMapaDialogState();
}

class _SelectorUbicacionMapaDialogState
    extends State<SelectorUbicacionMapaDialog> {
  final MapController _controladorMapa = MapController();

  late double _latitud;
  late double _longitud;
  late TextEditingController _controladorDireccion;
  bool _transcribiendoLugar = false;

  @override
  void initState() {
    super.initState();
    _latitud = widget.ubicacionInicial.latitud;
    _longitud = widget.ubicacionInicial.longitud;
    _controladorDireccion = TextEditingController(
      text: widget.ubicacionInicial.direccion,
    );
  }

  @override
  void dispose() {
    _controladorDireccion.dispose();
    super.dispose();
  }

  Future<void> _actualizarCoordenadas(
    double nuevaLat,
    double nuevaLng, {
    String? direccionFija,
  }) async {
    setState(() {
      _latitud = nuevaLat;
      _longitud = nuevaLng;
      if (direccionFija != null) {
        _controladorDireccion.text = direccionFija;
      } else {
        _transcribiendoLugar = true;
      }
    });

    try {
      _controladorMapa.move(osm.LatLng(_latitud, _longitud), 14.5);
    } catch (_) {}

    if (direccionFija == null) {
      try {
        final nombreLugar = await widget.onResolverNombreLugar(
          nuevaLat,
          nuevaLng,
        );
        if (!mounted) return;
        setState(() {
          _controladorDireccion.text = nombreLugar;
        });
      } finally {
        if (mounted) {
          setState(() {
            _transcribiendoLugar = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Seleccionar ubicación de la obra'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _controladorMapa,
                        options: MapOptions(
                          initialCenter: osm.LatLng(_latitud, _longitud),
                          initialZoom: 14.0,
                          onTap: (_, punto) {
                            unawaited(
                              _actualizarCoordenadas(
                                punto.latitude,
                                punto.longitude,
                              ),
                            );
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.constructoradelsur.app',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: osm.LatLng(_latitud, _longitud),
                                width: 48,
                                height: 48,
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.red,
                                  size: 42,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.pin_drop,
                                color: Colors.orangeAccent,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${_controladorDireccion.text} '
                                  '(${_latitud.toStringAsFixed(4)}, ${_longitud.toStringAsFixed(4)})',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_transcribiendoLugar) ...[
                const SizedBox(height: 6),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 10),
              const Text(
                'Tocá cualquier punto en el mapa para obtener la dirección o elegí una zona rápida:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final sugerencia in widget.ubicacionesSugeridas)
                    ActionChip(
                      avatar: const Icon(Icons.place, size: 16),
                      label: Text(
                        sugerencia.direccion.split(',').first,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () {
                        unawaited(
                          _actualizarCoordenadas(
                            sugerencia.latitud,
                            sugerencia.longitud,
                            direccionFija: sugerencia.direccion,
                          ),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controladorDireccion,
                decoration: const InputDecoration(
                  labelText: 'Dirección o referencia de la obra',
                  prefixIcon: Icon(Icons.map),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () {
            final direccion = _controladorDireccion.text.trim().isEmpty
                ? 'Mendoza (${_latitud.toStringAsFixed(4)}, ${_longitud.toStringAsFixed(4)})'
                : _controladorDireccion.text.trim();
            Navigator.pop(
              context,
              UbicacionObra(
                latitud: _latitud,
                longitud: _longitud,
                direccion: direccion,
              ),
            );
          },
          icon: const Icon(Icons.check),
          label: const Text('Confirmar ubicación'),
        ),
      ],
    );
  }
}
