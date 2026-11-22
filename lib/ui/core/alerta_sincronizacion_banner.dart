import 'package:flutter/material.dart';

/// Banner flotante que se muestra durante 2 segundos en todas las vistas
/// cuando el servicio de conectividad detecta internet y comienza la
/// sincronización simulada de los reportes locales pendientes.
class AlertaSincronizacionBanner extends StatelessWidget {
  const AlertaSincronizacionBanner({
    super.key,
    required this.visible,
  });

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final colores = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      color: colores.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colores.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Comenzando sincronización',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colores.onPrimaryContainer,
                ),
              ),
            ),
            Icon(Icons.cloud_sync, color: colores.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}
