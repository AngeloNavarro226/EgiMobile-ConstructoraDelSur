import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/obra.dart';
import '../../../domain/models/reporte_diario.dart';
import '../../../domain/models/tarea_obra.dart';
import '../../../plataforma/capacidades.dart';
import '../../core/semaforo.dart';
import '../../core/visor_foto_informe.dart';
import '../view_models/obras_view_model.dart';

/// Pantalla para crear un informe diario sobre una obra utilizando opciones
/// rápidas (selector de tarea con indicador de estado completa/en curso/pendiente,
/// chips de materiales + carga ad-hoc), dictado por voz real (`speech_to_text`),
/// recuperación de borrador y protección contra salida accidental (`PopScope`),
/// y carga/toma de fotos comprimidas.
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
  final TextEditingController _controladorMaterialAdHoc =
      TextEditingController();

  late final AppLifecycleListener _lifecycleListener;
  late String _tareaSeleccionada;
  late EstadoObra _estadoSemaforo;
  bool _marcarTareaCompletada = true;
  bool _finalizarObra = false;
  bool _guardando = false;
  bool _guardadoExitoso = false;
  bool _borradorRecuperado = false;
  final List<String> _materialesAdHoc = [];
  final Set<String> _materialesSeleccionados = {};
  final List<FotoComprimida> _fotosAdjuntas = [];
  String _textoPrevioAlDictado = '';

  List<TareaObra> get _tareasUnicas {
    final vistas = <String>{};
    final resultado = <TareaObra>[];
    for (final tarea in widget.obra.tareas) {
      if (vistas.add(tarea.nombre)) {
        resultado.add(tarea);
      }
    }
    if (resultado.isEmpty) {
      return const [
        TareaObra(
          id: 'general',
          nombre: 'Tarea general de obra',
          completada: false,
        ),
      ];
    }
    return resultado;
  }

  TareaObra? _buscarTareaPorNombre(String nombre) {
    for (final t in _tareasUnicas) {
      if (t.nombre == nombre) return t;
    }
    return null;
  }

  List<String> get _opcionesMateriales {
    final base = widget.obra.materiales.isNotEmpty
        ? widget.obra.materiales
        : const [
            'Cemento Portland',
            'Hormigón H-21',
            'Hierro nervado 12mm',
            'Arena gruesa',
          ];
    final combinados = <String>[...base, ..._materialesAdHoc];
    final vistos = <String>{};
    return [
      for (final m in combinados)
        if (vistos.add(m.trim().toLowerCase())) m.trim(),
    ];
  }

  bool get _tieneCambiosSinGuardar =>
      !_guardadoExitoso &&
      !_guardando &&
      (_controladorObservaciones.text.trim().isNotEmpty ||
          _fotosAdjuntas.isNotEmpty ||
          _materialesAdHoc.isNotEmpty);

  @override
  void initState() {
    super.initState();
    final nombresTareas = _tareasUnicas.map((t) => t.nombre).toList();
    _tareaSeleccionada = widget.obra.tareaActual;
    if (!nombresTareas.contains(_tareaSeleccionada)) {
      _tareaSeleccionada = nombresTareas.first;
    }
    _estadoSemaforo = widget.obra.estado;
    _finalizarObra = widget.obra.finalizada;
    if (_opcionesMateriales.isNotEmpty) {
      _materialesSeleccionados.add(_opcionesMateriales.first);
    }

    final borrador = widget.viewModel.borradorObservaciones.trim();
    if (borrador.isNotEmpty) {
      _controladorObservaciones.text = borrador;
      _borradorRecuperado = true;
    }

    // Guarda el borrador de observaciones si el usuario minimiza la aplicación
    // en terreno.
    _lifecycleListener = AppLifecycleListener(
      onHide: () {
        if (!_guardadoExitoso) {
          unawaited(
            widget.viewModel.guardarBorradorInforme(
              _controladorObservaciones.text,
            ),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _controladorObservaciones.dispose();
    _controladorMaterialAdHoc.dispose();
    super.dispose();
  }

  Future<void> _descartarBorrador() async {
    _controladorObservaciones.clear();
    setState(() => _borradorRecuperado = false);
    await widget.viewModel.descartarBorradorInforme();
  }

  void _agregarMaterialAdHoc() {
    final limpio = _controladorMaterialAdHoc.text.trim();
    if (limpio.isEmpty) return;
    final existente = _opcionesMateriales.cast<String?>().firstWhere(
          (m) => m != null && m.toLowerCase() == limpio.toLowerCase(),
          orElse: () => null,
        );
    setState(() {
      if (existente != null) {
        _materialesSeleccionados.add(existente);
      } else {
        _materialesAdHoc.add(limpio);
        _materialesSeleccionados.add(limpio);
      }
      _controladorMaterialAdHoc.clear();
    });
  }

  Future<void> _manejarIntentoSalida() async {
    final accion = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Salir sin guardar el informe?'),
        content: const Text(
          'Tenés observaciones o fotos cargadas. Podés guardar las observaciones como borrador para retomarlas después.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'seguir'),
            child: const Text('Seguir editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'descartar'),
            child: const Text('Descartar y salir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'borrador'),
            child: const Text('Guardar borrador'),
          ),
        ],
      ),
    );

    if (!mounted || accion == null || accion == 'seguir') return;

    if (accion == 'borrador') {
      await widget.viewModel.guardarBorradorInforme(
        _controladorObservaciones.text,
      );
    } else if (accion == 'descartar') {
      await widget.viewModel.descartarBorradorInforme();
    }

    if (!mounted) return;
    setState(() => _guardadoExitoso = true);
    Navigator.pop(context, false);
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

    if (_finalizarObra) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Finalizar esta obra?'),
          content: const Text(
            'Al finalizarla, la obra pasará a modo solo lectura bajo el filtro "Finalizadas". Podrás reabrirla más adelante si hace falta.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirmar y guardar'),
            ),
          ],
        ),
      );
      if (confirmar != true || !mounted) return;
    }

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
      _guardadoExitoso = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _finalizarObra
                ? 'Informe guardado y obra marcada como finalizada (visible en el filtro "Finalizadas").'
                : 'Informe guardado. Se sincronizará automáticamente cuando haya conexión.',
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

  Widget _construirItemTarea(
    BuildContext context,
    TareaObra tarea, {
    required bool compacto,
  }) {
    final esActual = !tarea.completada &&
        widget.obra.tareaActualObj != null &&
        tarea.id == widget.obra.tareaActualObj!.id;
    final colores = Theme.of(context).colorScheme;

    final IconData icono;
    final Color colorIcono;
    final String etiquetaEstado;
    if (tarea.completada) {
      icono = Icons.check_circle;
      colorIcono = Colors.green.shade700;
      etiquetaEstado = 'Completa';
    } else if (esActual) {
      icono = Icons.flag;
      colorIcono = colores.primary;
      etiquetaEstado = 'En curso';
    } else {
      icono = Icons.radio_button_unchecked;
      colorIcono = colores.onSurfaceVariant;
      etiquetaEstado = 'Pendiente';
    }

    return Row(
      children: [
        Icon(icono, size: 18, color: colorIcono),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            tarea.nombre,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              decoration: tarea.completada ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: compacto ? 6 : 8,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: colorIcono.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            etiquetaEstado,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorIcono,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tareaElegida = _buscarTareaPorNombre(_tareaSeleccionada);
    final tareaYaCompleta = tareaElegida?.completada ?? false;

    return PopScope(
      canPop: !_tieneCambiosSinGuardar,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tieneCambiosSinGuardar) {
          unawaited(_manejarIntentoSalida());
        }
      },
      child: Scaffold(
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
                if (_borradorRecuperado) ...[
                  Card(
                    key: const Key('banner_borrador_recuperado'),
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.restore_outlined),
                      title: const Text(
                        'Borrador de observaciones recuperado',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: TextButton(
                        key: const Key('btn_descartar_borrador'),
                        onPressed: () => unawaited(_descartarBorrador()),
                        child: const Text('Descartar'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text(
                  '1. Tarea del informe',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('dropdown_tarea_informe'),
                  initialValue: _tareaSeleccionada,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  selectedItemBuilder: (context) => [
                    for (final tarea in _tareasUnicas)
                      _construirItemTarea(context, tarea, compacto: true),
                  ],
                  items: [
                    for (final tarea in _tareasUnicas)
                      DropdownMenuItem<String>(
                        value: tarea.nombre,
                        child: _construirItemTarea(
                          context,
                          tarea,
                          compacto: false,
                        ),
                      ),
                  ],
                  onChanged: (valor) {
                    if (valor != null) {
                      final elegida = _buscarTareaPorNombre(valor);
                      setState(() {
                        _tareaSeleccionada = valor;
                        if (elegida != null && elegida.completada) {
                          _marcarTareaCompletada = true;
                        }
                      });
                    }
                  },
                ),
                if (tareaYaCompleta)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.green.shade700,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Esta tarea ya figura como completada.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Marcar esta tarea como completada (actualiza % de progreso)',
                  ),
                  value: _marcarTareaCompletada,
                  onChanged: tareaYaCompleta
                      ? null
                      : (valor) => setState(
                            () => _marcarTareaCompletada = valor ?? false,
                          ),
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
                    'Marca todas las tareas como completas y pasa la obra a solo lectura en "Finalizadas".',
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
                  '2. Materiales gastados en la jornada',
                  style: TextStyle(fontWeight: FontWeight.bold),
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('campo_material_ad_hoc'),
                        controller: _controladorMaterialAdHoc,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _agregarMaterialAdHoc(),
                        decoration: const InputDecoration(
                          labelText: 'Agregar otro material usado hoy',
                          hintText: 'Ej. Cal hidratada, alambre...',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      key: const Key('btn_agregar_material_ad_hoc'),
                      onPressed: _agregarMaterialAdHoc,
                      icon: const Icon(Icons.add),
                      label: const Text('Sumar'),
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
                        '4. Observaciones de obra',
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
                  key: const Key('campo_observaciones_informe'),
                  controller: _controladorObservaciones,
                  maxLines: 3,
                  onChanged: (_) {
                    if (_borradorRecuperado) {
                      setState(() => _borradorRecuperado = false);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: escuchando
                        ? 'Hablá ahora cerca del micrófono...'
                        : 'Escribí o usá el micrófono para dictar las observaciones...',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const Divider(height: 24),
                const Text(
                  '5. Fotografías del informe',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'Se optimizan automáticamente (< 200 KB) para subir rápido desde obra.',
                  style: Theme.of(context).textTheme.bodySmall,
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
                    onEliminar: () =>
                        setState(() => _fotosAdjuntas.removeAt(i)),
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
      ),
    );
  }
}
