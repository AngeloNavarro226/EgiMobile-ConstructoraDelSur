import 'package:flutter/material.dart';

import '../../../domain/models/formato_fecha.dart';
import '../view_models/notificaciones_view_model.dart';

/// Apartado exclusivo del Ingeniero para:
/// 1. Programar el horario (formato 24hs) del recordatorio diario de
///    sincronización para su equipo de obra (se dispara únicamente si hay
///    informes sin sincronizar).
/// 2. Consultar el historial de alertas proactivas emitidas cuando una obra
///    pasa a estado Amarillo (Demorada) o Rojo (Con problemas).
class NotificacionesIngenieroScreen extends StatefulWidget {
  const NotificacionesIngenieroScreen({
    super.key,
    required this.viewModel,
  });

  final NotificacionesViewModel viewModel;

  @override
  State<NotificacionesIngenieroScreen> createState() =>
      _NotificacionesIngenieroScreenState();
}

class _NotificacionesIngenieroScreenState
    extends State<NotificacionesIngenieroScreen> {
  Future<void> _cambiarHorarioRecordatorio() async {
    final actual = widget.viewModel.recordatorio;
    final seleccionado = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: actual.hora, minute: actual.minuto),
      helpText: 'Horario del recordatorio diario (24 hs)',
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (seleccionado == null || !mounted) return;

    await widget.viewModel.actualizarRecordatorioSincronizacion(
      activo: actual.activo,
      hora: seleccionado.hour,
      minuto: seleccionado.minute,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Recordatorio diario programado a las ${widget.viewModel.recordatorio.horarioFormateado} hs',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final recordatorio = widget.viewModel.recordatorio;
        final historial = widget.viewModel.notificaciones;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Panel de Alertas y Recordatorio',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.schedule_send),
                      title: const Text(
                        'Recordatorio diario de sincronización',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Aplica a los capataces de tus obras a cargo y solo avisa si tienen informes sin sincronizar.',
                      ),
                      value: recordatorio.activo,
                      onChanged: (activo) =>
                          widget.viewModel.actualizarRecordatorioSincronizacion(
                        activo: activo,
                        hora: recordatorio.hora,
                        minuto: recordatorio.minuto,
                      ),
                    ),
                    const Divider(),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Horario programado: ${recordatorio.horarioFormateado} hs',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        FilledButton.tonalIcon(
                          key: const Key('btn_modificar_horario_recordatorio'),
                          onPressed: _cambiarHorarioRecordatorio,
                          icon: const Icon(Icons.access_time),
                          label: const Text('Modificar horario'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Historial de alertas de semáforo (${historial.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (historial.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('Sin alertas de semáforo registradas'),
                  subtitle: Text(
                    'Las alertas aparecen automáticamente cuando una obra pasa a Amarillo o Rojo.',
                  ),
                ),
              )
            else
              for (final item in historial)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      item.esAlertaSemaforo
                          ? Icons.warning_amber_rounded
                          : Icons.notifications_outlined,
                      color: item.esAlertaSemaforo ? Colors.red : null,
                    ),
                    title: Text(
                      item.titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      '${item.mensaje}\nPara: ${item.destinatario} · ${formatearFechaHoraCorta(item.fechaHora)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
