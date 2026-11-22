import 'package:flutter/material.dart';

import '../../domain/models/obra.dart';

/// Devuelve el color de semáforo correspondiente al [EstadoObra].
Color colorSemaforo(EstadoObra estado) => switch (estado) {
      EstadoObra.aTiempo => Colors.green,
      EstadoObra.demorada => Colors.amber,
      EstadoObra.problemas => Colors.red,
    };

/// Indicador circular de estado con tooltip descriptivo.
class Semaforo extends StatelessWidget {
  const Semaforo(this.estado, {super.key, this.size = 16});

  final EstadoObra estado;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: estado.etiqueta,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorSemaforo(estado),
          border: Border.all(color: Colors.black26),
        ),
      ),
    );
  }
}

/// Barra horizontal de chips de semáforo interactivos más el filtro de obras
/// finalizadas.
///
/// - Las obras marcadas como finalizadas permanecen ocultas por defecto en las
///   vistas principales y solo se muestran cuando se activa el chip `"Finalizadas"`.
/// - Al presionar cualquiera de los chips de semáforo se filtran las obras
///   activas de ese estado.
class ResumenSemaforoBar extends StatelessWidget {
  const ResumenSemaforoBar({
    super.key,
    required this.cantidadATiempo,
    required this.cantidadDemoradas,
    required this.cantidadConProblemas,
    this.cantidadFinalizadas = 0,
    this.estadoSeleccionado,
    this.mostrarSoloFinalizadas = false,
    this.onSeleccionarEstado,
    this.onAlternarFinalizadas,
  });

  final int cantidadATiempo;
  final int cantidadDemoradas;
  final int cantidadConProblemas;
  final int cantidadFinalizadas;
  final EstadoObra? estadoSeleccionado;
  final bool mostrarSoloFinalizadas;
  final ValueChanged<EstadoObra?>? onSeleccionarEstado;
  final ValueChanged<bool>? onAlternarFinalizadas;

  int _cantidadPara(EstadoObra estado) => switch (estado) {
        EstadoObra.aTiempo => cantidadATiempo,
        EstadoObra.demorada => cantidadDemoradas,
        EstadoObra.problemas => cantidadConProblemas,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          for (final estado in EstadoObra.values)
            FilterChip(
              key: Key('chip_filtro_${estado.name}'),
              selected: !mostrarSoloFinalizadas && estadoSeleccionado == estado,
              showCheckmark: false,
              avatar: Semaforo(estado, size: 12),
              label: Text(
                '${_cantidadPara(estado)} ${estado.etiqueta.toLowerCase()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      !mostrarSoloFinalizadas && estadoSeleccionado == estado
                          ? FontWeight.bold
                          : FontWeight.normal,
                ),
              ),
              onSelected: onSeleccionarEstado == null
                  ? null
                  : (activo) {
                      onSeleccionarEstado!(activo ? estado : null);
                    },
            ),
          if (onAlternarFinalizadas != null)
            FilterChip(
              key: const Key('chip_filtro_finalizadas'),
              selected: mostrarSoloFinalizadas,
              showCheckmark: false,
              avatar: Icon(
                Icons.task_alt,
                size: 15,
                color: mostrarSoloFinalizadas
                    ? Theme.of(context).colorScheme.primary
                    : Colors.teal,
              ),
              label: Text(
                '$cantidadFinalizadas finalizadas',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: mostrarSoloFinalizadas
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              onSelected: onAlternarFinalizadas,
            ),
          if ((estadoSeleccionado != null || mostrarSoloFinalizadas) &&
              onSeleccionarEstado != null)
            ActionChip(
              avatar: const Icon(Icons.filter_alt_off, size: 14),
              label: const Text('Ver activas', style: TextStyle(fontSize: 11)),
              onPressed: () => onSeleccionarEstado!(null),
            ),
        ],
      ),
    );
  }
}
