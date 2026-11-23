import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/obra.dart';
import '../../../domain/models/reporte_diario.dart';
import '../../../plataforma/capacidades.dart';
import '../../core/semaforo.dart';
import '../../core/visor_foto_informe.dart';
import '../view_models/obras_view_model.dart';

/// Pantalla para crear un informe diario sobre una obra utilizando opciones
/// rápidas (`DropdownButtonFormField` con `initialValue` para la tarea y
/// `FilterChip` para los materiales gastados), dictado por voz real
/// (`speech_to_text`), opción para finalizar la obra, guardado automático de
/// borrador en `AppLifecycleListener(onHide)`, y
/// carga/toma de fotos comprimidas mediante `Isolate` + `Stream` + `Workmanager`.
class CrearInformeScreen extends StatefulWidget {
  const CrearInformeScreen({
    super.key,
    required this.obra,
    required this.viewModel,
    required this.capacidades,
  });

  final Obra obra;
  final ObrasViewModel viewModel;
  final Capacidades capacidades;

  @override
  State<CrearInformeScreen> createState() => _CrearInformeScreenState();
}

class _CrearInformeScreenState extends State<CrearInformeScreen> {
  final TextEditingController _controladorObservaciones =
      TextEditingController();

  late final AppLifecycleListener _lifecycleListener;
  late String _tareaSeleccionada;
  late EstadoObra _estadoSemaforo;
  bool _marcarTareaCompletada = true;
  bool _finalizarObra = false;
  bool _guardando = false;
  final Set<String> _materialesSeleccionados = {};
  final List<FotoComprimida> _fotosAdjuntas = [];
  String _textoPrevioAlDictado = '';

  List<String> get _opcionesTareas {
    final nombres = widget.obra.tareas.map((t) => t.nombre).toSet().toList();
    if (nombres.isEmpty) return ['Tarea general de obra'];
    return nombres;
  }

  List<String> get _opcionesMateriales {
    if (widget.obra.materiales.isNotEmpty) {
      return widget.obra.materiales.toSet().toList();
    }
    return const [
      'Cemento Portland',
      'Hormigón H-21',
      'Hierro nervado 12mm',
      'Arena gruesa',
    ];
  }

  @override
  void initState() {
    super.initState();
    _tareaSeleccionada = widget.obra.tareaActual;
    if (!_opcionesTareas.contains(_tareaSeleccionada)) {
      _tareaSeleccionada = _opcionesTareas.first;
    }
    _estadoSemaforo = widget.obra.estado;
    _finalizarObra = widget.obra.finalizada;
    if (_opcionesMateriales.isNotEmpty) {
      _materialesSeleccionados.add(_opcionesMateriales.first);
    }

    // Guarda el borrador de observaciones si el usuario minimiza la aplicación
    // en terreno
    _lifecycleListener = AppLifecycleListener(
      onHide: () {
        unawaited(
          widget.viewModel.guardarBorradorInforme(
            _controladorObservaciones.text,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _controladorObservaciones.dispose();
    super.dispose();
  }

  Future<void> _alternarDictadoPorVoz() async {
    if (!widget.viewModel.escuchandoDictadoVoz) {
      _textoPrevioAlDictado = _controladorObservaciones.text.trim();
    }

    await widget.viewModel.alternarDictadoPorVoz(
      onTextoReconocido: (palabrasReconocidas) {
        if (!mounted) return;
        setState(() {
          if (_textoPrevioAlDictado.isEmpty) {
            _controladorObservaciones.text = palabrasReconocidas;
          } else {
            _controladorObservaciones.text =
                '$_textoPrevioAlDictado $palabrasReconocidas';
          }
        });
      },
      onErrorMicrofono: (mensajeError) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensajeError)),
        );
      },
    );
  }

  Future<void> _agregarFoto({required bool desdeCamara}) async {
    final foto = await widget.viewModel.adjuntarFotoComprimida(
      desdeCamara: desdeCamara,
    );
    if (!mounted || foto == null) return;
    setState(() {
      _fotosAdjuntas.add(foto);
    });
  }

  Future<void> _guardarInforme() async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      await widget.viewModel.guardarInformeDiario(
        obra: widget.obra,
        tareaSeleccionada: _tareaSeleccionada,
        marcarTareaComoCompletada: _marcarTareaCompletada,
        materialesGastados: _materialesSeleccionados.toList(),
        observaciones: _controladorObservaciones.text,
        estadoSemaforo: _estadoSemaforo,
        fotosAdjuntas: _fotosAdjuntas,
        finalizarObra: _finalizarObra,
      );
      if (!mounted) return;
      final error = widget.viewModel.mensajeError;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _finalizarObra
                ? 'Informe guardado y obra marcada como finalizada (visible bajo el filtro "Finalizadas")'
                : 'Informe guardado en SQLite local (sync_status = pending)',
          ),
        ),
      );
      Navigator.pop(context, true);
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Nuevo informe: ${widget.obra.nombre}'),
      ),
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) {
          final escuchando = widget.viewModel.escuchandoDictadoVoz;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                '1. Tarea sobre la cual es el informe (opción rápida)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('dropdown_tarea_informe'),
                initialValue: _tareaSeleccionada,
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.construction),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final nombreTarea in _opcionesTareas)
                    DropdownMenuItem(
                      value: nombreTarea,
                      child: Text(
                        nombreTarea,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (valor) {
                  if (valor != null) {
                    setState(() => _tareaSeleccionada = valor);
                  }
                },
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Marcar esta tarea como completada (actualiza % de progreso)',
                ),
                value: _marcarTareaCompletada,
                onChanged: (valor) =>
                    setState(() => _marcarTareaCompletada = valor ?? false),
              ),
              SwitchListTile(
                key: const Key('switch_finalizar_obra_informe'),
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.task_alt, color: Colors.teal),
                title: const Text(
                  'Finalizar la obra con este informe',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Marca todas las tareas como completas y mueve la obra al filtro "Finalizadas".',
                ),
                value: _finalizarObra,
                onChanged: (valor) {
                  setState(() {
                    _finalizarObra = valor;
                    if (valor) {
                      _marcarTareaCompletada = true;
                      _estadoSemaforo = EstadoObra.aTiempo;
                    }
                  });
                },
              ),
              const Divider(height: 24),
              const Text(
                '2. Materiales gastados en la jornada (selección rápida)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('dropdown_material_rapido'),
                hint: const Text('Seleccionar material rápido...'),
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final material in _opcionesMateriales)
                    DropdownMenuItem(
                      value: material,
                      child: Text(material),
                    ),
                ],
                onChanged: (material) {
                  if (material != null) {
                    setState(() => _materialesSeleccionados.add(material));
                  }
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final material in _opcionesMateriales)
                    FilterChip(
                      label: Text(material),
                      selected: _materialesSeleccionados.contains(material),
                      onSelected: (seleccionado) {
                        setState(() {
                          if (seleccionado) {
                            _materialesSeleccionados.add(material);
                          } else {
                            _materialesSeleccionados.remove(material);
                          }
                        });
                      },
                    ),
                ],
              ),
              const Divider(height: 24),
              const Text(
                '3. Estado del semáforo de la obra',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SegmentedButton<EstadoObra>(
                showSelectedIcon: false,
                segments: [
                  for (final estado in EstadoObra.values)
                    ButtonSegment(
                      value: estado,
                      icon: Semaforo(estado, size: 12),
                      label: Text(
                        estado.etiqueta,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
                selected: {_estadoSemaforo},
                onSelectionChanged: (seleccion) =>
                    setState(() => _estadoSemaforo = seleccion.first),
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      '4. Observaciones de obra (texto o micrófono real)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: widget.capacidades.tieneMicrofono
                        ? _alternarDictadoPorVoz
                        : null,
                    icon: Icon(
                      escuchando ? Icons.stop_circle_outlined : Icons.mic,
                      color: escuchando ? Colors.red : null,
                    ),
                    label: Text(
                      escuchando ? 'Detener micrófono' : 'Dictar por voz',
                    ),
                  ),
                ],
              ),
              if (widget.viewModel.errorVozATexto != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    widget.viewModel.errorVozATexto!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _controladorObservaciones,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: escuchando
                      ? 'Hablá ahora cerca del micrófono...'
                      : 'Escribí o usá el micrófono para dictar las observaciones...',
                  border: const OutlineInputBorder(),
                ),
              ),
              const Divider(height: 24),
              const Text(
                '5. Fotografías del informe (compresión 800x600 70% < 200 KB via Isolate + Workmanager)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _agregarFoto(desdeCamara: false),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Cargar foto'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: widget.capacidades.tieneCamara
                          ? () => _agregarFoto(desdeCamara: true)
                          : null,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(
                        widget.capacidades.tieneCamara
                            ? 'Tomar con cámara'
                            : 'Cámara no disp.',
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.viewModel.mensajeProgresoFoto != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    widget.viewModel.mensajeProgresoFoto!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              for (var i = 0; i < _fotosAdjuntas.length; i++)
                MiniaturaFotoInforme(
                  foto: _fotosAdjuntas[i],
                  indice: i,
                  onEliminar: () => setState(() => _fotosAdjuntas.removeAt(i)),
                ),
              const SizedBox(height: 24),
              SafeArea(
                top: false,
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    key: const Key('btn_guardar_informe_diario'),
                    onPressed: _guardando ? null : _guardarInforme,
                    icon: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _guardando
                          ? 'Guardando informe...'
                          : (_finalizarObra
                              ? 'Guardar informe y finalizar obra'
                              : 'Guardar informe diario'),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
