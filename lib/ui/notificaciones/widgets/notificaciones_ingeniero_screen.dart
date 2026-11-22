import 'package:flutter/material.dart';

import '../view_models/notificaciones_view_model.dart';

/// Apartado exclusivo del Ingeniero para:
/// 1. Programar el horario de la notificación automática diaria (recordatorio
///    de abrir la aplicación para sincronizar los datos una vez al día).
/// 2. Enviar notificaciones manuales mediante la aplicación a los responsables.
/// 3. Consultar las alertas proactivas disparadas cuando una obra pasa a
///    estado Amarillo o Rojo.
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
  final TextEditingController _controladorTitulo = TextEditingController();
  final TextEditingController _controladorMensaje = TextEditingController();
  String _destinatario = 'Todos los Capataces';

  static const _destinatariosDisponibles = [
    'Todos los Capataces',
    'Carlos Méndez (Capataz)',
    'Roberto Del Sur (Dueño)',
    'Todo el equipo de obra',
  ];

  @override
  void dispose() {
    _controladorTitulo.dispose();
    _controladorMensaje.dispose();
    super.dispose();
  }

  Future<void> _cambiarHorarioRecordatorio() async {
    final actual = widget.viewModel.recordatorio;
    final seleccionado = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: actual.hora, minute: actual.minuto),
      helpText: 'Horario del recordatorio diario de sincronización',
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

  Future<void> _enviarNotificacion() async {
    if (_controladorTitulo.text.trim().isEmpty ||
        _controladorMensaje.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completá el título y el mensaje de la notificación'),
        ),
      );
      return;
    }

    await widget.viewModel.enviarNotificacion(
      titulo: _controladorTitulo.text,
      mensaje: _controladorMensaje.text,
      destinatario: _destinatario,
    );
    if (!mounted) return;
    _controladorTitulo.clear();
    _controladorMensaje.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Notificación enviada a $_destinatario en la barra de estado',
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
              'Panel de Notificaciones y Alertas',
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
                        'Recordatorio automático de abrir la aplicación para sincronizar los datos una vez al día.',
                      ),
                      value: recordatorio.activo,
                      onChanged: (activo) => widget.viewModel
                          .actualizarRecordatorioSincronizacion(
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enviar notificación mediante la aplicación',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_destinatario),
                      initialValue: _destinatario,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Destinatario',
                        prefixIcon: Icon(Icons.group_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final dest in _destinatariosDisponibles)
                          DropdownMenuItem(
                            value: dest,
                            child: Text(
                              dest,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (valor) {
                        if (valor != null) {
                          setState(() => _destinatario = valor);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _controladorTitulo,
                      decoration: const InputDecoration(
                        labelText: 'Título de la notificación',
                        prefixIcon: Icon(Icons.notifications_active_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _controladorMensaje,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Mensaje',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _enviarNotificacion,
                        icon: const Icon(Icons.send),
                        label: const Text('Enviar notificación push'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Historial de alertas proactivas y envíos (${historial.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
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
                    '${item.mensaje}\nPara: ${item.destinatario} · ${item.fechaHora.toIso8601String().substring(0, 16)}',
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
