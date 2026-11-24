import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/obra.dart';
import '../../../plataforma/capacidades.dart';
import '../../core/barra_busqueda_obras.dart';
import '../../core/estado_vacio_obras.dart';
import '../../core/obra_card.dart';
import '../../core/semaforo.dart';
import '../view_models/obras_view_model.dart';
import 'detalle_obra_sheet.dart';

/// Vista de inicio del Ingeniero con búsqueda ampliada, ordenamiento, chips de
/// semáforo interactivos, filtro de obras finalizadas y apertura directa del
/// panel de detalle de obra.
class InicioIngenieroScreen extends StatelessWidget {
  const InicioIngenieroScreen({
    super.key,
    required this.viewModel,
    required this.capacidades,
  });

  final ObrasViewModel viewModel;
  final Capacidades capacidades;

  void _abrirPanelCompleto(BuildContext context, Obra obra) {
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
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final visibles = viewModel.obrasFiltradas;

        return Column(
          children: [
            BarraBusquedaObras(
              valorActual: viewModel.textoBusqueda,
              ordenActual: viewModel.ordenObras,
              onBuscar: viewModel.actualizarBusqueda,
              onCambiarOrden: viewModel.cambiarOrdenObras,
              hintText: 'Buscar obra, dirección, responsable...',
            ),
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
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  viewModel.mensajeError ??
                                      'No se pudieron cargar las obras.',
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
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: viewModel.refrescarManual,
                          child: visibles.isEmpty
                              ? EstadoVacioObras(
                                  icono: viewModel.mostrarSoloFinalizadas
                                      ? Icons.task_alt
                                      : Icons.apartment_outlined,
                                  mensaje: viewModel.mostrarSoloFinalizadas
                                      ? 'Aún no hay obras marcadas como finalizadas.'
                                      : (viewModel.tieneFiltrosActivos
                                          ? 'No hay obras que coincidan con el filtro aplicado.'
                                          : 'Todavía no hay obras registradas.'),
                                  subtitulo: viewModel.tieneFiltrosActivos
                                      ? 'Probá limpiar la búsqueda o cambiar el estado de semáforo.'
                                      : 'Podés crear una nueva obra desde la pestaña "Agregar Obras".',
                                  onLimpiarFiltros:
                                      viewModel.tieneFiltrosActivos
                                          ? viewModel.limpiarFiltrosYBusqueda
                                          : null,
                                )
                              : GridView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(16),
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 240,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                    childAspectRatio: 0.72,
                                  ),
                                  itemCount: visibles.length,
                                  itemBuilder: (context, i) => ObraCard(
                                    obra: visibles[i],
                                    ahora: viewModel.ahora,
                                    reportesPendientes: viewModel
                                        .cantidadReportesPendientesDeObra(
                                      visibles[i].id,
                                    ),
                                    onTap: () => _abrirPanelCompleto(
                                        context, visibles[i]),
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
