import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/obra.dart';
import '../../../plataforma/capacidades.dart';
import '../../core/obra_card.dart';
import '../../core/semaforo.dart';
import '../view_models/obras_view_model.dart';
import 'detalle_obra_sheet.dart';

/// Vista de inicio del Dueño / Gerencia con chips de semáforo interactivos
/// y filtro de obras finalizadas.
class InicioDuenioScreen extends StatefulWidget {
  const InicioDuenioScreen({
    super.key,
    required this.viewModel,
    required this.capacidades,
  });

  final ObrasViewModel viewModel;
  final Capacidades capacidades;

  @override
  State<InicioDuenioScreen> createState() => _InicioDuenioScreenState();
}

class _InicioDuenioScreenState extends State<InicioDuenioScreen> {
  final TextEditingController _controladorBusqueda = TextEditingController();

  @override
  void dispose() {
    _controladorBusqueda.dispose();
    super.dispose();
  }

  void _abrirDetalleSoloLectura(Obra obra) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DetalleObraEnriquecidoSheet(
          obraId: obra.id,
          viewModel: widget.viewModel,
          capacidades: widget.capacidades,
          permiteEdicion: false,
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
                  hintText: 'Buscar obra en monitoreo gerencial...',
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
                        onTap: () => _abrirDetalleSoloLectura(visibles[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
