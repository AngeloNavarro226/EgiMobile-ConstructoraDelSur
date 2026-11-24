import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/obra.dart';
import '../../../plataforma/capacidades.dart';
import '../../core/barra_busqueda_obras.dart';
import '../../core/estado_vacio_obras.dart';
import '../../core/obra_card.dart';
import '../../core/semaforo.dart';
import '../view_models/obras_view_model.dart';
import 'crear_informe_screen.dart';
import 'detalle_obra_sheet.dart';

/// Vista de inicio del Capataz adaptada al terreno con búsqueda, ordenamiento,
/// chips de semáforo, filtro de obras finalizadas y botones rápidos directos en
/// cada tarjeta de obra.
class InicioCapatazScreen extends StatelessWidget {
  const InicioCapatazScreen({
    super.key,
    required this.viewModel,
    required this.capacidades,
  });

  final ObrasViewModel viewModel;
  final Capacidades capacidades;

  void _abrirDetalleObra(BuildContext context, Obra obra) {
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

  void _abrirCrearInforme(BuildContext context, Obra obra) {
    if (obra.finalizada) return;
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
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final obrasDelCapataz = viewModel.obrasFiltradas;
        final tieneAlgunaObraAsignada =
            viewModel.obrasVisiblesPorRol.isNotEmpty;

        return Column(
          children: [
            BarraBusquedaObras(
              valorActual: viewModel.textoBusqueda,
              ordenActual: viewModel.ordenObras,
              onBuscar: viewModel.actualizarBusqueda,
              onCambiarOrden: viewModel.cambiarOrdenObras,
              hintText: 'Buscar en mis obras...',
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
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: viewModel.refrescarManual,
                          child: obrasDelCapataz.isEmpty
                              ? EstadoVacioObras(
                                  icono: viewModel.mostrarSoloFinalizadas
                                      ? Icons.task_alt
                                      : Icons.construction_outlined,
                                  mensaje: viewModel.mostrarSoloFinalizadas
                                      ? 'No hay obras finalizadas asignadas a tu perfil.'
                                      : (!tieneAlgunaObraAsignada
                                          ? 'No tenés obras asignadas en este momento.'
                                          : 'No hay obras asignadas que coincidan con el filtro seleccionado.'),
                                  subtitulo: viewModel.tieneFiltrosActivos
                                      ? 'Limpiá el filtro o deslizá hacia abajo para actualizar.'
                                      : 'Deslizá hacia abajo para buscar nuevas asignaciones.',
                                  onLimpiarFiltros:
                                      viewModel.tieneFiltrosActivos
                                          ? viewModel.limpiarFiltrosYBusqueda
                                          : null,
                                )
                              : ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(16),
                                  itemCount: obrasDelCapataz.length,
                                  itemBuilder: (context, index) {
                                    final obra = obrasDelCapataz[index];
                                    return ObraItemCapataz(
                                      obra: obra,
                                      ahora: viewModel.ahora,
                                      reportesPendientes: viewModel
                                          .cantidadReportesPendientesDeObra(
                                        obra.id,
                                      ),
                                      onTap: () =>
                                          _abrirDetalleObra(context, obra),
                                      onRealizarInforme: obra.finalizada
                                          ? null
                                          : () => _abrirCrearInforme(
                                                context,
                                                obra,
                                              ),
                                      onModificarTareas: obra.finalizada
                                          ? null
                                          : () {
                                              unawaited(
                                                mostrarDialogoModificarEstadoTareas(
                                                  context: context,
                                                  obra: obra,
                                                  viewModel: viewModel,
                                                  permiteEdicion: true,
                                                ),
                                              );
                                            },
                                      onCambiarSemaforo: obra.finalizada
                                          ? null
                                          : () {
                                              unawaited(
                                                mostrarDialogoCambiarSemaforo(
                                                  context: context,
                                                  obra: obra,
                                                  viewModel: viewModel,
                                                ),
                                              );
                                            },
                                    );
                                  },
                                ),
                        ),
            ),
          ],
        );
      },
    );
  }
}
