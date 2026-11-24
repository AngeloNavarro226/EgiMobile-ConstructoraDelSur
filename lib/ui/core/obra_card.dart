import 'package:flutter/material.dart';

import '../../domain/models/formato_fecha.dart';
import '../../domain/models/obra.dart';
import 'imagen_local_o_remota.dart';
import 'semaforo.dart';

/// Tarjeta de obra para la vista en grilla (Ingeniero y Dueño) con ripple
/// táctil, antigüedad relativa del último reporte e indicador de sync pendiente.
class ObraCard extends StatelessWidget {
  const ObraCard({
    super.key,
    required this.obra,
    required this.onTap,
    this.ahora,
    this.reportesPendientes = 0,
  });

  final Obra obra;
  final VoidCallback onTap;
  final DateTime? ahora;
  final int reportesPendientes;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final etiquetaFecha = ahora != null
        ? formatearTiempoRelativo(obra.fechaUltimoReporte, ahora: ahora!)
        : formatearFechaCorta(obra.fechaUltimoReporte);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: ImagenPortadaObra(obra: obra),
                    ),
                    if (obra.finalizada)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade700,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.task_alt,
                                size: 12,
                                color: Colors.white,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Finalizada',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (reportesPendientes > 0)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Tooltip(
                          message:
                              '$reportesPendientes informe(s) pendiente(s) de sincronizar',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 12,
                                  color: Colors.orangeAccent,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$reportesPendientes',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                obra.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                obra.tareaActual,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: colores.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: obra.avance,
                minHeight: 5,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Semaforo(obra.estado, size: 14),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${obra.porcentajeAvance}% (${obra.tareasCompletas.length}/${obra.tareas.length})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                etiquetaFecha,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: colores.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de obra adaptada al terreno para la vista del Capataz, alineada
/// en una columna de alta accesibilidad con botones rápidos directos cuando la
/// obra está activa y modo solo lectura cuando está finalizada.
class ObraItemCapataz extends StatelessWidget {
  const ObraItemCapataz({
    super.key,
    required this.obra,
    required this.onTap,
    this.ahora,
    this.reportesPendientes = 0,
    this.onRealizarInforme,
    this.onModificarTareas,
    this.onCambiarSemaforo,
  });

  final Obra obra;
  final VoidCallback onTap;
  final DateTime? ahora;
  final int reportesPendientes;
  final VoidCallback? onRealizarInforme;
  final VoidCallback? onModificarTareas;
  final VoidCallback? onCambiarSemaforo;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final etiquetaFecha = ahora != null
        ? formatearTiempoRelativo(obra.fechaUltimoReporte, ahora: ahora!)
        : formatearFechaCorta(obra.fechaUltimoReporte);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 76,
                      height: 76,
                      child: ImagenPortadaObra(obra: obra),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                obra.nombre,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (obra.finalizada)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Chip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(Icons.task_alt, size: 14),
                                  label: Text(
                                    'Finalizada',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                ),
                              ),
                            Semaforo(obra.estado, size: 22),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tarea actual: ${obra.tareaActual}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 15),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                obra.ubicacion.direccion,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: colores.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Último reporte: $etiquetaFecha',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colores.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (reportesPendientes > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colores.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.cloud_upload_outlined,
                                      size: 12,
                                      color: colores.onTertiaryContainer,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '$reportesPendientes pend.',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: colores.onTertiaryContainer,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Progreso: ${obra.porcentajeAvance}%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${obra.tareasCompletas.length} de ${obra.tareas.length} tareas completas',
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
              const SizedBox(height: 12),
              if (obra.finalizada)
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: colores.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Solo lectura · Tocá para ver historial o reabrir',
                        style: TextStyle(
                          fontSize: 12,
                          color: colores.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (onRealizarInforme != null)
                      FilledButton.icon(
                        key: Key('btn_capataz_informe_${obra.id}'),
                        onPressed: onRealizarInforme,
                        icon: const Icon(Icons.assignment_add, size: 18),
                        label: const Text('Nuevo informe'),
                      ),
                    if (onModificarTareas != null)
                      FilledButton.tonalIcon(
                        key: Key('btn_capataz_tareas_${obra.id}'),
                        onPressed: onModificarTareas,
                        icon: const Icon(Icons.checklist, size: 18),
                        label: const Text('Tareas'),
                      ),
                    if (onCambiarSemaforo != null)
                      OutlinedButton.icon(
                        key: Key('btn_capataz_semaforo_${obra.id}'),
                        onPressed: onCambiarSemaforo,
                        icon: const Icon(Icons.traffic_outlined, size: 18),
                        label: const Text('Semáforo'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dibuja la foto de portada de una obra soportando archivos locales en disco,
/// URLs remotas de Storage, Base64 (web) y assets predefinidos.
class ImagenPortadaObra extends StatelessWidget {
  const ImagenPortadaObra({super.key, required this.obra});

  final Obra obra;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.apartment, size: 48, color: Colors.black38),
    );

    final urlRemota =
        obra.imagenUrl ?? (obra.esImagenRemota ? obra.imagen : null);

    return ImagenLocalORemota(
      bytesMemoria: obra.bytesImagenPortada,
      rutaLocal: obra.imagen,
      urlRemota: urlRemota,
      fit: BoxFit.cover,
      placeholder: placeholder,
    );
  }
}
