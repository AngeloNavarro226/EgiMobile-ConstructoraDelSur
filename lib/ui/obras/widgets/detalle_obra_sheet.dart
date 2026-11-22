import 'dart:async';

import 'package:flutter/material.dart';

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
  final controlador = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Agregar tarea a "${obra.nombre}"'),
      content: TextField(
        controller: controlador,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Nombre de la nueva tarea',
          hintText: 'Ej. Revoque fino planta baja',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            if (controlador.text.trim().isNotEmpty) {
              await viewModel.agregarTareaAObra(obra.id, controlador.text);
            }
            if (dialogContext.mounted) {
              Navigator.pop(dialogContext);
            }
          },
          child: const Text('Agregar tarea'),
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
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: t.completada,
                      title: Text(t.nombre),
                      subtitle: permiteEdicion
                          ? const Text(
                              'Tocá para marcar como completada',
                              style: TextStyle(fontSize: 11),
                            )
                          : null,
                      onChanged: permiteEdicion
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
                      subtitle: permiteEdicion
                          ? const Text(
                              'Tocá para volver a pendiente',
                              style: TextStyle(fontSize: 11),
                            )
                          : null,
                      onChanged: permiteEdicion
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
            if (permiteEdicion)
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
                await viewModel.cambiarEstadoSemaforo(obra.id, estado);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
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
class DetalleObraEnriquecidoSheet extends StatelessWidget {
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
                  _FilaDato(
                    etiqueta: 'Ubicación (Google Maps)',
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
                    valor: obra.materiales.join(', '),
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
                      'Último reporte diario (${ultimo.fechaCreacionLocal.toIso8601String().substring(0, 16)}):',
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
                                          '${rep.tareaSeleccionada} (${rep.fechaCreacionLocal.toIso8601String().substring(0, 10)})',
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
                  Text(
                    'Responsable: ${obra.responsableNombre} · ${obra.ubicacion.direccion}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.construction),
                    title: Text(obra.tareaActual),
                    subtitle: const Text('Tarea actual en curso'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notes),
                    title: Text(
                      obra.observaciones.isEmpty
                          ? 'Sin observaciones'
                          : obra.observaciones,
                    ),
                    subtitle: const Text('Observaciones del último reporte'),
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
                              permiteEdicion: permiteEdicion,
                            ),
                          );
                        },
                        icon: const Icon(Icons.checklist, size: 18),
                        label: Text(
                          permiteEdicion
                              ? 'Modificar estado de tareas'
                              : 'Ver tareas completas y pendientes',
                        ),
                      ),
                    ],
                  ),
                  if (permiteEdicion) ...[
                    const Divider(height: 28),
                    const Text(
                      'Acciones operativas sobre la obra',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<EstadoObra>(
                        showSelectedIcon: false,
                        segments: [
                          for (final estado in EstadoObra.values)
                            ButtonSegment(
                              value: estado,
                              label: Text(
                                estado.etiqueta,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                        selected: {obra.estado},
                        onSelectionChanged: (s) {
                          unawaited(
                            viewModel.cambiarEstadoSemaforo(obra.id, s.first),
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
                              mostrarDialogoModificarEstadoTareas(
                                context: context,
                                obra: obra,
                                viewModel: viewModel,
                              ),
                            );
                          },
                          icon: const Icon(Icons.task_alt),
                          label: const Text('Estado de tareas'),
                        ),
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
                        FilledButton.icon(
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
