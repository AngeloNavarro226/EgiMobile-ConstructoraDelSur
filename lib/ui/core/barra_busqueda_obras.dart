import 'package:flutter/material.dart';

import '../obras/view_models/obras_view_model.dart';

/// Barra reutilizable de búsqueda ampliada (nombre, dirección, responsable o
/// tarea actual) con botón rápido de limpieza y selector de ordenamiento.
class BarraBusquedaObras extends StatefulWidget {
  const BarraBusquedaObras({
    super.key,
    required this.valorActual,
    required this.ordenActual,
    required this.onBuscar,
    required this.onCambiarOrden,
    this.hintText = 'Buscar obra, dirección, responsable...',
  });

  final String valorActual;
  final OrdenObras ordenActual;
  final ValueChanged<String> onBuscar;
  final ValueChanged<OrdenObras> onCambiarOrden;
  final String hintText;

  @override
  State<BarraBusquedaObras> createState() => _BarraBusquedaObrasState();
}

class _BarraBusquedaObrasState extends State<BarraBusquedaObras> {
  late final TextEditingController _controlador;

  @override
  void initState() {
    super.initState();
    _controlador = TextEditingController(text: widget.valorActual);
  }

  @override
  void didUpdateWidget(covariant BarraBusquedaObras oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.valorActual != _controlador.text) {
      _controlador.value = TextEditingValue(
        text: widget.valorActual,
        selection: TextSelection.collapsed(offset: widget.valorActual.length),
      );
    }
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  void _limpiar() {
    _controlador.clear();
    widget.onBuscar('');
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final hayTexto = _controlador.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('campo_busqueda_obras'),
              controller: _controlador,
              onChanged: (texto) {
                setState(() {});
                widget.onBuscar(texto);
              },
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.hintText,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: hayTexto
                    ? IconButton(
                        key: const Key('btn_limpiar_busqueda'),
                        tooltip: 'Limpiar búsqueda',
                        icon: const Icon(Icons.clear),
                        onPressed: _limpiar,
                      )
                    : null,
                filled: true,
                fillColor: colores.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<OrdenObras>(
            key: const Key('btn_ordenar_obras'),
            tooltip: 'Ordenar obras (${widget.ordenActual.etiqueta})',
            initialValue: widget.ordenActual,
            onSelected: widget.onCambiarOrden,
            itemBuilder: (context) => [
              for (final criterio in OrdenObras.values)
                PopupMenuItem<OrdenObras>(
                  value: criterio,
                  child: Row(
                    children: [
                      Icon(
                        criterio == widget.ordenActual
                            ? Icons.check
                            : Icons.sort,
                        size: 18,
                        color: criterio == widget.ordenActual
                            ? colores.primary
                            : colores.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        criterio.etiqueta,
                        style: TextStyle(
                          fontWeight: criterio == widget.ordenActual
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colores.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort, size: 20, color: colores.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: colores.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
