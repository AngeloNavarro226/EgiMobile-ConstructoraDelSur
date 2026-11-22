import 'package:flutter/material.dart';

import '../../domain/models/obra.dart';
import 'imagen_local_o_remota.dart';
import 'semaforo.dart';

/// Tarjeta de obra para la vista en grilla (Ingeniero y Dueño) y tarjeta
/// expandida para la vista en columna de alta accesibilidad (Capataz).
class ObraCard extends StatelessWidget {
  const ObraCard({
    super.key,
    required this.obra,
    required this.onTap,
  });

  final Obra obra;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 1,
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
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  Text(
                    '${obra.porcentajeAvance}% (${obra.tareasCompletas.length}/${obra.tareas.length})',
                    style: const TextStyle(fontSize: 11),
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

/// Tarjeta de obra adaptada al terreno para la vista del Capataz, alineada
/// en un `Column` (una debajo de otra) con botones e indicadores grandes.
class ObraItemCapataz extends StatelessWidget {
  const ObraItemCapataz({
    super.key,
    required this.obra,
    required this.onTap,
  });

  final Obra obra;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
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
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Chip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: const Icon(Icons.task_alt, size: 14),
                                  label: const Text(
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
                    'Progreso automático: ${obra.porcentajeAvance}%',
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
