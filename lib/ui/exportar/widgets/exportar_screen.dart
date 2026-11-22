import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/obra.dart';
import '../../core/semaforo.dart';
import '../../obras/view_models/obras_view_model.dart';
import '../view_models/exportar_view_model.dart';

/// Pantalla compartida por los 3 perfiles para exportar y descargar en un
/// archivo (`.csv` o `.json`) los datos de todas las obras o de una obra puntual.
class ExportarScreen extends StatefulWidget {
  const ExportarScreen({
    super.key,
    required this.viewModel,
    required this.obrasViewModel,
  });

  final ExportarViewModel viewModel;
  final ObrasViewModel obrasViewModel;

  @override
  State<ExportarScreen> createState() => _ExportarScreenState();
}

class _ExportarScreenState extends State<ExportarScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.actualizarDatos());
    widget.obrasViewModel.addListener(_sincronizarConObras);
  }

  @override
  void dispose() {
    widget.obrasViewModel.removeListener(_sincronizarConObras);
    super.dispose();
  }

  void _sincronizarConObras() {
    unawaited(widget.viewModel.actualizarDatos());
  }

  Future<void> _copiarAlPortapapeles() async {
    await Clipboard.setData(
      ClipboardData(text: widget.viewModel.contenidoExportado),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado al portapapeles')),
    );
  }

  Future<void> _descargarArchivoExportado() async {
    final resultado = await widget.viewModel.exportarYDescargarArchivo();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(
          'Archivo descargado: ${resultado.nombreArchivo} (${resultado.rutaGuardada})',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final obrasDisponibles = widget.obrasViewModel.obrasVisiblesPorRol;
        final ultimaDescarga = widget.viewModel.ultimaDescarga;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exportar informe de obras',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.download_done_outlined),
                  title: const Text('Descarga de archivo CSV o JSON'),
                  subtitle: Text(
                    ultimaDescarga == null
                        ? 'Seleccioná la obra y el formato (CSV o JSON) y presioná "Exportar" para descargar el archivo.'
                        : 'Último archivo descargado: ${ultimaDescarga.nombreArchivo}\nUbicación: ${ultimaDescarga.rutaGuardada}',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final estado in EstadoObra.values)
                    Chip(
                      avatar: Semaforo(estado, size: 12),
                      label: Text(
                        '${widget.obrasViewModel.cantidadPorEstado(estado)} '
                        '${estado.etiqueta.toLowerCase()}',
                      ),
                    ),
                  Chip(
                    avatar: const Icon(
                      Icons.task_alt,
                      size: 14,
                      color: Colors.teal,
                    ),
                    label: Text(
                      '${widget.obrasViewModel.cantidadFinalizadas} finalizadas',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey(widget.viewModel.obraIdSeleccionada),
                      initialValue: widget.viewModel.obraIdSeleccionada,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Filtrar obra a exportar',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Todas las obras visibles'),
                        ),
                        for (final obra in obrasDisponibles)
                          DropdownMenuItem<String?>(
                            value: obra.id,
                            child: Text(
                              obra.nombre,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: widget.viewModel.seleccionarObraFiltro,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<FormatoExportacion>(
                    segments: const [
                      ButtonSegment(
                        value: FormatoExportacion.csv,
                        label: Text('CSV'),
                      ),
                      ButtonSegment(
                        value: FormatoExportacion.json,
                        label: Text('JSON'),
                      ),
                    ],
                    selected: {widget.viewModel.formato},
                    onSelectionChanged: (s) =>
                        widget.viewModel.cambiarFormato(s.first),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: SizedBox.expand(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        widget.viewModel.contenidoExportado,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.viewModel.descargando)
                const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copiarAlPortapapeles,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('boton_exportar_archivo'),
                      onPressed: widget.viewModel.descargando
                          ? null
                          : _descargarArchivoExportado,
                      icon: const Icon(Icons.download),
                      label: const Text('Exportar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
