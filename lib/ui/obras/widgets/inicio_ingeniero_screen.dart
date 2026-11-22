import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/obra.dart';
import '../../../plataforma/capacidades.dart';
import '../../core/obra_card.dart';
import '../../core/semaforo.dart';
import '../view_models/obras_view_model.dart';
import 'crear_informe_screen.dart';
import 'detalle_obra_sheet.dart';

/// Vista de inicio del Ingeniero con chips de semáforo interactivos, filtro
/// de obras finalizadas y opción rápida para modificar el estado de las tareas
/// sin necesidad de crear un informe.
class InicioIngenieroScreen extends StatefulWidget {
  const InicioIngenieroScreen({
    super.key,
    required this.viewModel,
    required this.capacidades,
  });

  final ObrasViewModel viewModel;
  final Capacidades capacidades;

  @override
  State<InicioIngenieroScreen> createState() => _InicioIngenieroScreenState();
}

class _InicioIngenieroScreenState extends State<InicioIngenieroScreen> {
  final TextEditingController _controladorBusqueda = TextEditingController();

  @override
  void dispose() {
    _controladorBusqueda.dispose();
    super.dispose();
  }

  void _alSeleccionarObra(Obra obra) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${obra.nombre} · ${obra.estado.etiqueta} (${obra.porcentajeAvance}%)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Tarea actual: ${obra.tareaActual} · Resp: ${obra.responsableNombre}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilledButton.tonal(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    unawaited(
                      mostrarDialogoCambiarSemaforo(
                        context: context,
                        obra: obra,
                        viewModel: widget.viewModel,
                      ),
                    );
                  },
                  child: const Text('Semáforo', style: TextStyle(fontSize: 11)),
                ),
                FilledButton.tonal(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    unawaited(
                      mostrarDialogoModificarEstadoTareas(
                        context: context,
                        obra: obra,
                        viewModel: widget.viewModel,
                      ),
                    );
                  },
                  child: const Text(
                    'Estado de tareas',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    unawaited(
                      mostrarDialogoAgregarTarea(
                        context: context,
                        obra: obra,
                        viewModel: widget.viewModel,
                      ),
                    );
                  },
                  child: const Text('+ Tarea', style: TextStyle(fontSize: 11)),
                ),
                FilledButton.tonal(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    unawaited(
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CrearInformeScreen(
                            obra: obra,
                            viewModel: widget.viewModel,
                            capacidades: widget.capacidades,
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Informe', style: TextStyle(fontSize: 11)),
                ),
                FilledButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    _abrirPanelCompleto(obra);
                  },
                  child: const Text(
                    'Ver detalles e historial',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    _abrirPanelCompleto(obra);
  }

  void _abrirPanelCompleto(Obra obra) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DetalleObraEnriquecidoSheet(
          obraId: obra.id,
          viewModel: widget.viewModel,
          capacidades: widget.capacidades,
          permiteEdicion: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final visibles = widget.viewModel.obrasFiltradas;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _controladorBusqueda,
                onChanged: widget.viewModel.actualizarBusqueda,
                decoration: InputDecoration(
                  hintText: 'Buscar obra...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            ResumenSemaforoBar(
              cantidadATiempo:
                  widget.viewModel.cantidadPorEstado(EstadoObra.aTiempo),
              cantidadDemoradas:
                  widget.viewModel.cantidadPorEstado(EstadoObra.demorada),
              cantidadConProblemas:
                  widget.viewModel.cantidadPorEstado(EstadoObra.problemas),
              cantidadFinalizadas: widget.viewModel.cantidadFinalizadas,
              estadoSeleccionado: widget.viewModel.filtroEstadoSemaforo,
              mostrarSoloFinalizadas: widget.viewModel.mostrarSoloFinalizadas,
              onSeleccionarEstado: widget.viewModel.seleccionarFiltroSemaforo,
              onAlternarFinalizadas:
                  widget.viewModel.alternarFiltroFinalizadas,
            ),
            Expanded(
              child: visibles.isEmpty
                  ? Center(
                      child: Text(
                        widget.viewModel.mostrarSoloFinalizadas
                            ? 'Aún no hay obras marcadas como finalizadas'
                            : 'No hay obras que coincidan con el filtro',
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.76,
                      ),
                      itemCount: visibles.length,
                      itemBuilder: (context, i) => ObraCard(
                        obra: visibles[i],
                        onTap: () => _alSeleccionarObra(visibles[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
