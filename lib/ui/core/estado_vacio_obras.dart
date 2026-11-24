import 'package:flutter/material.dart';

/// Estado vacío centrado compatible con [RefreshIndicator] para las vistas de
/// listado y grilla de obras (Ingeniero, Capataz y Dueño).
class EstadoVacioObras extends StatelessWidget {
  const EstadoVacioObras({
    super.key,
    required this.mensaje,
    this.subtitulo,
    this.icono = Icons.apartment_outlined,
    this.onLimpiarFiltros,
  });

  final String mensaje;
  final String? subtitulo;
  final IconData icono;
  final VoidCallback? onLimpiarFiltros;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    constraints.maxHeight > 220 ? constraints.maxHeight : 260,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        icono,
                        size: 48,
                        color: colores.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        mensaje,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (subtitulo != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitulo!,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colores.onSurfaceVariant,
                                  ),
                        ),
                      ],
                      if (onLimpiarFiltros != null) ...[
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          key: const Key('btn_limpiar_filtros_vacio'),
                          onPressed: onLimpiarFiltros,
                          icon: const Icon(Icons.filter_alt_off, size: 18),
                          label: const Text('Limpiar filtros y búsqueda'),
                        ),
                      ],
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
