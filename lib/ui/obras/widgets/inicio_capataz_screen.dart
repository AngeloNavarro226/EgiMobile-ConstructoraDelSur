import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/obra.dart';
import '../../../plataforma/capacidades.dart';
import '../../core/obra_card.dart';
import '../../core/semaforo.dart';
import '../view_models/obras_view_model.dart';
import 'crear_informe_screen.dart';
import 'detalle_obra_sheet.dart';

/// Vista de inicio del Capataz adaptada al terreno con filtrado por chips de
/// semáforo, filtro de obras finalizadas, modificación directa del estado de
/// las tareas y carga de informes.
class InicioCapatazScreen extends StatelessWidget {
  const InicioCapatazScreen({
    super.key,
    required this.viewModel,
    required this.capacidades,
  });

  final ObrasViewModel viewModel;
  final Capacidades capacidades;

  void _mostrarSnackbarObraCapataz(BuildContext context, Obra obra) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 9),
        behavior: SnackBarBehavior.floating,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Semaforo(obra.estado, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${obra.nombre} — Estado: ${obra.estado.etiqueta} (${obra.porcentajeAvance}%)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
                    unawaited(
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => DetalleObraEnriquecidoSheet(
                          obraId: obra.id,
                          viewModel: viewModel,
                          capacidades: capacidades,
                          permiteEdicion: true,
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Ver informes/fotos',
                    style: TextStyle(fontSize: 11, color: Colors.amberAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Tarea en curso: ${obra.tareaActual}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilledButton.tonal(
                  key: const Key('btn_snackbar_cambiar_semaforo'),
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
                    unawaited(
                      mostrarDialogoCambiarSemaforo(
                        context: context,
                        obra: obra,
                        viewModel: viewModel,
                      ),
                    );
                  },
                  child: const Text(
                    'Cambiar semáforo',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                FilledButton.tonal(
                  key: const Key('btn_snackbar_estado_tareas'),
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
                    unawaited(
                      mostrarDialogoModificarEstadoTareas(
                        context: context,
                        obra: obra,
                        viewModel: viewModel,
                      ),
                    );
                  },
                  child: const Text(
                    'Estado de tareas',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                FilledButton.tonal(
                  key: const Key('btn_snackbar_agregar_tarea'),
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
                    unawaited(
                      mostrarDialogoAgregarTarea(
                        context: context,
                        obra: obra,
                        viewModel: viewModel,
                      ),
                    );
                  },
                  child: const Text(
                    'Agregar tarea',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                FilledButton(
                  key: const Key('btn_snackbar_realizar_informe'),
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
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
                  child: const Text(
                    'Realizar informe',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
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
        final obrasDelCapataz = viewModel.obrasFiltradas;

        return Column(
          children: [
            ResumenSemaforoBar(
              cantidadATiempo: viewModel.cantidadPorEstado(EstadoObra.aTiempo),
              cantidadDemoradas:
                  viewModel.cantidadPorEstado(EstadoObra.demorada),
              cantidadConProblemas:
                  viewModel.cantidadPorEstado(EstadoObra.problemas),
              cantidadFinalizadas: viewModel.cantidadFinalizadas,
              estadoSeleccionado: viewModel.filtroEstadoSemaforo,
              mostrarSoloFinalizadas: viewModel.mostrarSoloFinalizadas,
              onSeleccionarEstado: viewModel.seleccionarFiltroSemaforo,
              onAlternarFinalizadas: viewModel.alternarFiltroFinalizadas,
            ),
            Expanded(
              child: viewModel.estado == EstadoCargaObras.cargando
                  ? const Center(child: CircularProgressIndicator())
                  : viewModel.estado == EstadoCargaObras.error
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                viewModel.mensajeError ??
                                    'No se pudieron cargar tus obras.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.tonal(
                                onPressed: () =>
                                    viewModel.cargar(forzarRecarga: true),
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: viewModel.refrescarManual,
                          child: obrasDelCapataz.isEmpty
                              ? ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  children: [
                                    SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height *
                                              0.45,
                                      child: Center(
                                        child: Text(
                                          viewModel.mostrarSoloFinalizadas
                                              ? 'No hay obras finalizadas asignadas a tu perfil.'
                                              : 'No hay obras asignadas con el estado de semáforo seleccionado.',
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final obra in obrasDelCapataz)
                                        ObraItemCapataz(
                                          obra: obra,
                                          onTap: () =>
                                              _mostrarSnackbarObraCapataz(
                                            context,
                                            obra,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                        ),
            ),
          ],
        );
      },
    );
  }
}
