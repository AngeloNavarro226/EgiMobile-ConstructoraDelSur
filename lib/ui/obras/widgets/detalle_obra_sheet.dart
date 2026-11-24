import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/formato_fecha.dart';
import '../../../domain/models/obra.dart';
import '../../../plataforma/capacidades.dart';
import '../../core/semaforo.dart';
import '../../core/visor_foto_informe.dart';
import '../view_models/obras_view_model.dart';
import 'crear_informe_screen.dart';

/// Diálogo para agregar rápidamente una nueva tarea a una obra, recalculando
/// automáticamente el porcentaje de avance.
Future<void> mostrarDialogoAgregarTarea({
  required BuildContext context,
  required Obra obra,
  required ObrasViewModel viewModel,
}) async {
  if (obra.finalizada) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _DialogoAgregarTarea(
      obra: obra,
      viewModel: viewModel,
    ),
  );
}

class _DialogoAgregarTarea extends StatefulWidget {
  const _DialogoAgregarTarea({
    required this.obra,
    required this.viewModel,
  });

  final Obra obra;
  final ObrasViewModel viewModel;

  @override
  State<_DialogoAgregarTarea> createState() => _DialogoAgregarTareaState();
}

class _DialogoAgregarTareaState extends State<_DialogoAgregarTarea> {
  final TextEditingController _controlador = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    final texto = _controlador.text.trim();
    if (texto.isNotEmpty) {
      setState(() => _guardando = true);
      await widget.viewModel.agregarTareaAObra(widget.obra.id, texto);
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Agregar tarea a "${widget.obra.nombre}"'),
      content: TextField(
        controller: _controlador,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => unawaited(_guardar()),
        decoration: const InputDecoration(
          labelText: 'Nombre de la nueva tarea',
          hintText: 'Ej. Revoque fino planta baja',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : () => unawaited(_guardar()),
          child: const Text('Agregar tarea'),
        ),
      ],
    );
  }
}

/// Diálogo para añadir un nuevo material a una obra en curso (permite escribir
/// uno libre o elegir en un toque desde el catálogo personal del ingeniero).
Future<void> mostrarDialogoAgregarMaterial({
  required BuildContext context,
  required Obra obra,
  required ObrasViewModel viewModel,
}) async {
  if (obra.finalizada) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _DialogoAgregarMaterial(
      obra: obra,
      viewModel: viewModel,
    ),
  );
}

class _DialogoAgregarMaterial extends StatefulWidget {
  const _DialogoAgregarMaterial({
    required this.obra,
    required this.viewModel,
  });

  final Obra obra;
  final ObrasViewModel viewModel;

  @override
  State<_DialogoAgregarMaterial> createState() =>
      _DialogoAgregarMaterialState();
}

class _DialogoAgregarMaterialState extends State<_DialogoAgregarMaterial> {
  final TextEditingController _controlador = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _guardar(String obraId) async {
    if (_guardando) return;
    final texto = _controlador.text.trim();
    if (texto.isNotEmpty) {
      setState(() => _guardando = true);
      _controlador.clear();
      await widget.viewModel.agregarMaterialAObra(obraId, texto);
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final obraActualizada =
            widget.viewModel.obtenerObraPorId(widget.obra.id) ?? widget.obra;
        final materialesExistentesLower = obraActualizada.materiales
            .map((m) => m.trim().toLowerCase())
            .toSet();
        final sugerencias = widget.viewModel.materialesGuardados
            .where(
              (p) => !materialesExistentesLower
                  .contains(p.nombre.trim().toLowerCase()),
            )
            .toList();

        return AlertDialog(
          title: Text('Añadir material · ${obraActualizada.nombre}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _controlador,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => unawaited(_guardar(obraActualizada.id)),
                    decoration: const InputDecoration(
                      labelText: 'Nombre del material',
                      hintText: 'Ej. Hormigón H-21',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (sugerencias.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Tus materiales guardados (tocar para añadir):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final plantilla in sugerencias)
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(plantilla.nombre),
                            onPressed: _guardando
                                ? null
                                : () {
                                    unawaited(
                                      widget.viewModel.agregarMaterialAObra(
                                        obraActualizada.id,
                                        plantilla.nombre,
                                      ),
                                    );
                                  },
                          ),
                      ],
                    ),
                  ],
                  if (obraActualizada.materiales.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Materiales en la obra (${obraActualizada.materiales.length}):',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      obraActualizada.materiales.join(', '),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _guardando ? null : () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
            FilledButton(
              onPressed: _guardando
                  ? null
                  : () => unawaited(_guardar(obraActualizada.id)),
              child: const Text('Añadir material'),
            ),
          ],
        );
      },
    );
  }
}

/// Diálogo para que el capataz responsable o el ingeniero a cargo elijan
/// explícitamente cuál de las tareas pendientes es la "Tarea actual en curso".
Future<void> mostrarDialogoElegirTareaActual({
  required BuildContext context,
  required Obra obra,
  required ObrasViewModel viewModel,
}) async {
  final pendientes = obra.tareasPendientes;
  if (pendientes.isEmpty) return;

  final tareaActivaId = obra.tareaActualObj?.id;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Elegir tarea actual · ${obra.nombre}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final tarea in pendientes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    tarea.id == tareaActivaId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: tarea.id == tareaActivaId
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(tarea.nombre),
                  subtitle: tarea.id == tareaActivaId
                      ? const Text('Tarea actual en curso')
                      : null,
                  onTap: () async {
                    await viewModel.cambiarTareaActual(obra.id, tarea.id);
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancelar'),
        ),
      ],
    ),
  );
}

/// Diálogo directo para que tanto el Capataz como el Ingeniero puedan
/// modificar el estado de las tareas (marcarlas como completadas o pendientes)
/// y sumar nuevas tareas sin necesidad de crear un informe diario.
Future<void> mostrarDialogoModificarEstadoTareas({
  required BuildContext context,
  required Obra obra,
  required ObrasViewModel viewModel,
  bool permiteEdicion = true,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final obraActualizada = viewModel.obtenerObraPorId(obra.id) ?? obra;
        final edicionHabilitada = permiteEdicion && !obraActualizada.finalizada;
        final completas = obraActualizada.tareasCompletas;
        final pendientes = obraActualizada.tareasPendientes;

        return AlertDialog(
          title: Text('Estado de tareas · ${obraActualizada.nombre}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Progreso automático: ${obraActualizada.porcentajeAvance}% '
                    '(${completas.length} de ${obraActualizada.tareas.length} completas)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: obraActualizada.avance),
                  const SizedBox(height: 16),
                  Text(
                    'Tareas pendientes (${pendientes.length}):',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (pendientes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('No hay tareas pendientes.'),
                    ),
                  for (final t in pendientes)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Checkbox(
                        value: t.completada,
                        onChanged: edicionHabilitada
                            ? (_) {
                                unawaited(
                                  viewModel.alternarTareaCompletada(
                                    obraActualizada.id,
                                    t.id,
                                  ),
                                );
                              }
                            : null,
                      ),
                      title: Text(t.nombre),
                      subtitle: Text(
                        t.id == obraActualizada.tareaActualObj?.id
                            ? 'Tarea actual en curso'
                            : (edicionHabilitada
                                ? 'Tocá el casillero para marcar como completada'
                                : 'Pendiente'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: t.id == obraActualizada.tareaActualObj?.id
                              ? FontWeight.w600
                              : null,
                        ),
                      ),
                      trailing: edicionHabilitada &&
                              viewModel.puedeElegirTareaActual(obraActualizada)
                          ? IconButton(
                              tooltip:
                                  t.id == obraActualizada.tareaActualObj?.id
                                      ? 'Tarea actual en curso'
                                      : 'Marcar como tarea actual',
                              icon: Icon(
                                t.id == obraActualizada.tareaActualObj?.id
                                    ? Icons.flag
                                    : Icons.flag_outlined,
                                color:
                                    t.id == obraActualizada.tareaActualObj?.id
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                              ),
                              onPressed:
                                  t.id == obraActualizada.tareaActualObj?.id
                                      ? null
                                      : () {
                                          unawaited(
                                            viewModel.cambiarTareaActual(
                                              obraActualizada.id,
                                              t.id,
                                            ),
                                          );
                                        },
                            )
                          : null,
                    ),
                  const Divider(),
                  Text(
                    'Tareas completas (${completas.length}):',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (completas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Aún no hay tareas completadas.'),
                    ),
                  for (final t in completas)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: t.completada,
                      title: Text(
                        t.nombre,
                        style: const TextStyle(
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      subtitle: edicionHabilitada
                          ? const Text(
                              'Tocá para volver a pendiente',
                              style: TextStyle(fontSize: 11),
                            )
                          : null,
                      onChanged: edicionHabilitada
                          ? (_) {
                              unawaited(
                                viewModel.alternarTareaCompletada(
                                  obraActualizada.id,
                                  t.id,
                                ),
                              );
                            }
                          : null,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (edicionHabilitada)
              TextButton.icon(
                onPressed: () {
                  unawaited(
                    mostrarDialogoAgregarTarea(
                      context: dialogContext,
                      obra: obraActualizada,
                      viewModel: viewModel,
                    ),
                  );
                },
                icon: const Icon(Icons.add_task),
                label: const Text('Añadir tarea'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Listo'),
            ),
          ],
        );
      },
    ),
  );
}

/// Diálogo rápido para cambiar el estado del semáforo de una obra.
Future<void> mostrarDialogoCambiarSemaforo({
  required BuildContext context,
  required Obra obra,
  required ObrasViewModel viewModel,
}) async {
  if (obra.finalizada) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Cambiar semáforo: ${obra.nombre}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final estado in EstadoObra.values)
            ListTile(
              leading: Semaforo(estado, size: 20),
              title: Text(estado.etiqueta),
              trailing: obra.estado == estado
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
              onTap: () async {
                unawaited(HapticFeedback.selectionClick());
                await viewModel.cambiarEstadoSemaforo(obra.id, estado);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Semáforo actualizado a ${estado.etiqueta}',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
        ],
      ),
    ),
  );
}

/// Modal enriquecido que muestra el estado completo de una obra, ubicación,
/// responsable, barra porcentual calculada automáticamente según tareas
/// completas, botones para acceder al informe completo (con galería de fotos),
/// al historial de informes pasados (con fotos desplegables) y al diálogo de
/// estado de tareas completas y pendientes.
class DetalleObraEnriquecidoSheet extends StatefulWidget {
  const DetalleObraEnriquecidoSheet({
    super.key,
    required this.obraId,
    required this.viewModel,
    required this.capacidades,
    required this.permiteEdicion,
  });

  final String obraId;
  final ObrasViewModel viewModel;
  final Capacidades capacidades;
  final bool permiteEdicion;

  @override
  State<DetalleObraEnriquecidoSheet> createState() =>
      _DetalleObraEnriquecidoSheetState();
}

class _DetalleObraEnriquecidoSheetState
    extends State<DetalleObraEnriquecidoSheet> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.cargarReportesDeObra(widget.obraId));
  }

  ObrasViewModel get viewModel => widget.viewModel;
  String get obraId => widget.obraId;
  Capacidades get capacidades => widget.capacidades;
  bool get permiteEdicion => widget.permiteEdicion;

  void _mostrarInformeCompleto(BuildContext context, Obra obra) {
    final ultimo = viewModel.ultimoInformeDeObra(obra.id);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Informe completo · ${obra.nombre}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FilaDato(
                    etiqueta: 'Estado de obra',
                    valor: obra.finalizada
                        ? 'Finalizada'
                        : 'En ejecución (${obra.estado.etiqueta})',
                  ),
                  _FilaDato(
                    etiqueta: 'Responsable asignado',
                    valor: obra.responsableNombre,
                  ),
                  if (obra.ingenieroNombre != null &&
                      obra.ingenieroNombre!.isNotEmpty)
                    _FilaDato(
                      etiqueta: 'Ingeniero a cargo',
                      valor: obra.ingenieroNombre!,
                    ),
                  _FilaDato(
                    etiqueta: 'Ubicación',
                    valor: obra.ubicacion.etiquetaCompleta,
                  ),
                  _FilaDato(
                    etiqueta: 'Tarea actual',
                    valor: obra.tareaActual,
                  ),
                  _FilaDato(
                    etiqueta: 'Avance calculado',
                    valor:
                        '${obra.porcentajeAvance}% (${obra.tareasCompletas.length} de ${obra.tareas.length} tareas completas)',
                  ),
                  _FilaDato(
                    etiqueta: 'Materiales de la obra',
                    valor: obra.materiales.isEmpty
                        ? 'Sin materiales cargados'
                        : obra.materiales.join(', '),
                  ),
                  _FilaDato(
                    etiqueta: 'Observaciones actuales',
                    valor: obra.observaciones.isEmpty
                        ? 'Sin observaciones'
                        : obra.observaciones,
                  ),
                  if (ultimo != null) ...[
                    const Divider(),
                    Text(
                      'Último reporte diario (${formatearFechaHoraCorta(ultimo.fechaCreacionLocal)}):',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('• Autor: ${ultimo.autorNombre}'),
                    Text('• Tarea reportada: ${ultimo.tareaSeleccionada}'),
                    Text(
                      '• Materiales gastados: ${ultimo.materialesUsados.join(", ")}',
                    ),
                    Text('• Sincronización: ${ultimo.syncStatus.etiqueta}'),
                    const SizedBox(height: 10),
                    Text(
                      'Fotografías del informe (${ultimo.urlFotos.length}):',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    GaleriaFotosInforme(fotos: ultimo.urlFotos),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarHistorialInformes(BuildContext context, Obra obra) {
    final historial = viewModel.informesDeObra(obra.id);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Historial de informes · ${obra.nombre}'),
          content: SizedBox(
            width: 480,
            child: historial.isEmpty
                ? const Text('Aún no se registraron informes para esta obra.')
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final rep in historial)
                          Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Semaforo(rep.estadoSemaforo, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${rep.tareaSeleccionada} · ${formatearFechaHoraCorta(rep.fechaCreacionLocal)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Autor: ${rep.autorNombre}\n'
                                    'Materiales: ${rep.materialesUsados.join(", ")}\n'
                                    'Observaciones: ${rep.observaciones.isEmpty ? "Sin observaciones" : rep.observaciones}\n'
                                    'Estado Sync: ${rep.syncStatus.etiqueta}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Fotografías adjuntas (${rep.urlFotos.length}):',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  GaleriaFotosInforme(fotos: rep.urlFotos),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copiarDireccion(BuildContext context, Obra obra) async {
    await Clipboard.setData(ClipboardData(text: obra.ubicacion.direccion));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dirección copiada al portapapeles'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmarReabrirObra(BuildContext context, Obra obra) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Reabrir "${obra.nombre}"?'),
        content: const Text(
          'La obra dejará de estar finalizada, volverá a la vista de obras activas y permitirá modificar semáforos, tareas y cargar nuevos informes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            key: const Key('btn_confirmar_reabrir_obra'),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.lock_open_outlined, size: 18),
            label: const Text('Reabrir obra'),
          ),
        ],
      ),
    );
    if (confirmar != true || !context.mounted) return;
    final ok = await viewModel.cambiarObraFinalizada(
      obra.id,
      finalizada: false,
    );
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('"${obra.nombre}" fue reabierta y volvió a obras activas.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final obra = viewModel.obtenerObraPorId(obraId);
        if (obra == null) {
          return const SizedBox(
            height: 200,
            child: Center(child: Text('Obra no encontrada')),
          );
        }

        final puedeEditarObra = permiteEdicion && !obra.finalizada;
        final colores = Theme.of(context).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          obra.nombre,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (obra.finalizada)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Chip(
                            avatar: Icon(Icons.task_alt, size: 16),
                            label: Text('Finalizada'),
                          ),
                        ),
                      Semaforo(obra.estado, size: 22),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Responsable: ${obra.responsableNombre} · ${obra.ubicacion.direccion}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copiar dirección',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        onPressed: () =>
                            unawaited(_copiarDireccion(context, obra)),
                      ),
                    ],
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.construction),
                    title: Text(obra.tareaActual),
                    subtitle: const Text('Tarea actual en curso'),
                    trailing: puedeEditarObra &&
                            viewModel.puedeElegirTareaActual(obra)
                        ? TextButton.icon(
                            onPressed: () {
                              unawaited(
                                mostrarDialogoElegirTareaActual(
                                  context: context,
                                  obra: obra,
                                  viewModel: viewModel,
                                ),
                              );
                            },
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            label: const Text('Cambiar'),
                          )
                        : null,
                    onTap: puedeEditarObra &&
                            viewModel.puedeElegirTareaActual(obra)
                        ? () {
                            unawaited(
                              mostrarDialogoElegirTareaActual(
                                context: context,
                                obra: obra,
                                viewModel: viewModel,
                              ),
                            );
                          }
                        : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notes),
                    title: Text(
                      obra.observaciones.isEmpty
                          ? 'Sin observaciones'
                          : obra.observaciones,
                    ),
                    subtitle: Text(
                      'Último reporte: ${formatearFechaHoraCorta(obra.fechaUltimoReporte)}',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Avance automático: ${obra.porcentajeAvance}%',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${obra.tareasCompletas.length}/${obra.tareas.length} tareas completas',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: obra.avance,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _mostrarInformeCompleto(context, obra),
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: const Text('Informe completo y fotos'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _mostrarHistorialInformes(context, obra),
                        icon: const Icon(Icons.history, size: 18),
                        label: Text(
                          'Historial de informes (${viewModel.informesDeObra(obra.id).length})',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          unawaited(
                            mostrarDialogoModificarEstadoTareas(
                              context: context,
                              obra: obra,
                              viewModel: viewModel,
                              permiteEdicion: puedeEditarObra,
                            ),
                          );
                        },
                        icon: const Icon(Icons.checklist, size: 18),
                        label: Text(
                          puedeEditarObra
                              ? 'Modificar estado de tareas'
                              : 'Ver tareas completas y pendientes',
                        ),
                      ),
                    ],
                  ),
                  if (obra.finalizada) ...[
                    const Divider(height: 28),
                    Card(
                      key: const Key('card_obra_finalizada_solo_lectura'),
                      margin: EdgeInsets.zero,
                      color: colores.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.lock_outline,
                                  size: 20,
                                  color: colores.primary,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Obra finalizada (modo solo lectura)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              permiteEdicion
                                  ? 'No se pueden cambiar el semáforo, modificar tareas ni cargar informes nuevos mientras esté finalizada. Si necesitás retomarla, podés reabrirla.'
                                  : 'Esta obra se encuentra finalizada y solo admite consulta de historial e informes.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (permiteEdicion) ...[
                              const SizedBox(height: 12),
                              FilledButton.tonalIcon(
                                key: const Key('btn_reabrir_obra'),
                                onPressed: viewModel.guardando
                                    ? null
                                    : () => unawaited(
                                          _confirmarReabrirObra(context, obra),
                                        ),
                                icon: const Icon(Icons.lock_open_outlined),
                                label: const Text('Reabrir obra'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ] else if (puedeEditarObra) ...[
                    const Divider(height: 28),
                    const Text(
                      'Acciones operativas sobre la obra',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<EstadoObra>(
                        key: const Key('segmented_semaforo_detalle'),
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
                        selected: {obra.estado},
                        onSelectionChanged: (s) {
                          final elegido = s.first;
                          unawaited(HapticFeedback.selectionClick());
                          unawaited(
                            viewModel
                                .cambiarEstadoSemaforo(obra.id, elegido)
                                .then((_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Semáforo actualizado a ${elegido.etiqueta}',
                                    ),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            }),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            unawaited(
                              mostrarDialogoAgregarTarea(
                                context: context,
                                obra: obra,
                                viewModel: viewModel,
                              ),
                            );
                          },
                          icon: const Icon(Icons.add_task),
                          label: const Text('Añadir tarea'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            unawaited(
                              mostrarDialogoAgregarMaterial(
                                context: context,
                                obra: obra,
                                viewModel: viewModel,
                              ),
                            );
                          },
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('Añadir material'),
                        ),
                        FilledButton.icon(
                          key: const Key('btn_detalle_realizar_informe'),
                          onPressed: () {
                            unawaited(
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => CrearInformeScreen(
                                    obra: obra,
                                    viewModel: viewModel,
                                    capacidades: capacidades,
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.assignment_add),
                          label: const Text('Realizar informe'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FilaDato extends StatelessWidget {
  const _FilaDato({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$etiqueta: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: valor),
          ],
        ),
      ),
    );
  }
}
