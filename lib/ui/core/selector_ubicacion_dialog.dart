import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as osm;

import '../../domain/models/ubicacion_obra.dart';

/// Motor de renderizado del mapa dentro del selector de ubicación.
enum MotorMapaSelector {
  /// Mapa real de calles con tiles de OpenStreetMap (funciona de inmediato en
  /// Android, iOS y Web sin necesidad de configurar una API Key de pago).
  mapaCallesSinApiKey,

  /// Widget nativo `GoogleMap` de `google_maps_flutter` (requiere colocar la
  /// API Key en `AndroidManifest.xml` / `web/index.html`).
  googleMapsNativo,
}

/// Diálogo interactivo que ofrece ambas opciones de mapa (Mapa de Calles sin
/// API Key y Google Maps SDK con API Key) y transcribe automáticamente el
/// nombre del lugar al que apuntan las coordenadas seleccionadas.
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
  final MapController _controladorOsm = MapController();
  gmaps.GoogleMapController? _controladorGoogleMap;

  late double _latitud;
  late double _longitud;
  late TextEditingController _controladorDireccion;
  MotorMapaSelector _motor = MotorMapaSelector.mapaCallesSinApiKey;
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
    _controladorGoogleMap?.dispose();
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

    if (_motor == MotorMapaSelector.mapaCallesSinApiKey) {
      try {
        _controladorOsm.move(osm.LatLng(_latitud, _longitud), 14.5);
      } catch (_) {}
    } else {
      unawaited(
        _controladorGoogleMap?.animateCamera(
          gmaps.CameraUpdate.newLatLng(gmaps.LatLng(_latitud, _longitud)),
        ),
      );
    }

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
              SegmentedButton<MotorMapaSelector>(
                segments: const [
                  ButtonSegment(
                    value: MotorMapaSelector.mapaCallesSinApiKey,
                    icon: Icon(Icons.map_outlined, size: 16),
                    label: Text(
                      'Mapa de Calles (Sin API Key)',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  ButtonSegment(
                    value: MotorMapaSelector.googleMapsNativo,
                    icon: Icon(Icons.pin_drop_outlined, size: 16),
                    label: Text(
                      'Google Maps SDK (Con API Key)',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
                selected: {_motor},
                onSelectionChanged: (s) => setState(() => _motor = s.first),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 250,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    children: [
                      if (_motor == MotorMapaSelector.mapaCallesSinApiKey)
                        FlutterMap(
                          mapController: _controladorOsm,
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
                              userAgentPackageName:
                                  'com.constructoradelsur.app',
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
                        )
                      else
                        gmaps.GoogleMap(
                          initialCameraPosition: gmaps.CameraPosition(
                            target: gmaps.LatLng(_latitud, _longitud),
                            zoom: 14,
                          ),
                          onMapCreated: (ctrl) => _controladorGoogleMap = ctrl,
                          markers: {
                            gmaps.Marker(
                              markerId:
                                  const gmaps.MarkerId('obra_seleccionada'),
                              position: gmaps.LatLng(_latitud, _longitud),
                              draggable: true,
                              onDragEnd: (pos) {
                                unawaited(
                                  _actualizarCoordenadas(
                                    pos.latitude,
                                    pos.longitude,
                                  ),
                                );
                              },
                              infoWindow: gmaps.InfoWindow(
                                title: _controladorDireccion.text,
                                snippet:
                                    '${_latitud.toStringAsFixed(4)}, ${_longitud.toStringAsFixed(4)}',
                              ),
                            ),
                          },
                          onTap: (pos) {
                            unawaited(
                              _actualizarCoordenadas(
                                pos.latitude,
                                pos.longitude,
                              ),
                            );
                          },
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: true,
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
                'Tocá cualquier punto en el mapa para transcribir el nombre del lugar o elegí una zona rápida:',
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
                  labelText: 'Lugar / Dirección transcrita de las coordenadas',
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
