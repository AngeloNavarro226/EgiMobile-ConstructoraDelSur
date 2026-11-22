import 'dart:async';

import 'package:flutter/material.dart';

import '../../autenticacion/view_models/autenticacion_view_model.dart';
import '../../obras/view_models/obras_view_model.dart';
import '../view_models/perfil_view_model.dart';

/// Pantalla de Perfil compartida por los 3 roles (Ingeniero, Capataz y Dueño).
///
/// Permite:
/// - Ver y modificar los datos del perfil activo en SQLite (nombre, teléfono
///   y contraseña).
/// - Alternar el modo oscuro y las notificaciones.
/// - Probar la detección de internet / sincronización manual.
/// - Cerrar sesión limpiando caché y sesión offline.
class PerfilScreen extends StatelessWidget {
  const PerfilScreen({
    super.key,
    required this.viewModel,
    required this.autenticacionViewModel,
    required this.obrasViewModel,
  });

  final PerfilViewModel viewModel;
  final AutenticacionViewModel autenticacionViewModel;
  final ObrasViewModel obrasViewModel;

  Future<void> _mostrarDialogoEditarPerfil(BuildContext context) async {
    final usuario = viewModel.usuarioActual;
    if (usuario == null) return;

    final ctrlNombre = TextEditingController(text: usuario.nombre);
    final ctrlTelefono = TextEditingController(text: usuario.telefono);
    final ctrlContrasenia = TextEditingController(text: usuario.contrasenia);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Modificar mi perfil'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('campo_perfil_nombre'),
                controller: ctrlNombre,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('campo_perfil_telefono'),
                controller: ctrlTelefono,
                decoration: const InputDecoration(
                  labelText: 'Teléfono de contacto',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('campo_perfil_contrasenia'),
                controller: ctrlContrasenia,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (ctrlNombre.text.trim().isNotEmpty &&
                  ctrlContrasenia.text.trim().isNotEmpty) {
                final ok = await viewModel.actualizarDatosPerfil(
                  nombre: ctrlNombre.text,
                  telefono: ctrlTelefono.text,
                  contrasenia: ctrlContrasenia.text,
                );
                if (ok) {
                  autenticacionViewModel.notificarPerfilActualizado();
                }
              }
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Guardar cambios'),
          ),
        ],
      ),
    );
  }

  void _confirmarCierreSesion(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Cerrar sesión?'),
          content: const Text(
            'Volverás a la pantalla de inicio de sesión para cambiar de usuario.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('confirmar_cerrar_sesion'),
              onPressed: () {
                Navigator.pop(dialogContext);
                unawaited(autenticacionViewModel.cerrarSesion());
              },
              child: const Text('Cerrar sesión'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        viewModel,
        autenticacionViewModel,
        obrasViewModel,
      ]),
      builder: (context, _) {
        final usuario = viewModel.usuarioActual;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 8),
            const Center(
              child: CircleAvatar(
                radius: 44,
                child: Icon(Icons.person, size: 48),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              usuario?.nombre ?? 'Usuario',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              usuario?.rol.etiqueta ?? '',
              textAlign: TextAlign.center,
            ),
            if (usuario != null && usuario.telefono.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  usuario.telefono,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (viewModel.mensajeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  viewModel.mensajeError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                onPressed: viewModel.guardando
                    ? null
                    : () => _mostrarDialogoEditarPerfil(context),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Modificar perfil'),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.business),
              title: Text('Constructora Del Sur'),
              subtitle: Text('Empresa'),
            ),
            ListTile(
              leading: const Icon(Icons.apartment),
              title: Text('${obrasViewModel.obrasVisiblesPorRol.length} obras'),
              subtitle: Text(
                'Obras visibles en este perfil (${obrasViewModel.cantidadReportesPendientes} informes pendientes de sync)',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.wifi_find),
              title: const Text('Simular detección de Internet'),
              subtitle: const Text(
                'Dispara la alerta de 2 segundos "Comenzando sincronización"',
              ),
              trailing: FilledButton.tonal(
                onPressed: viewModel.simularConexionInternet,
                child: const Text('Sincronizar'),
              ),
            ),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.notifications),
              title: const Text('Notificaciones'),
              subtitle: const Text(
                'Avisar cuando una obra cambie a amarillo o rojo',
              ),
              value: viewModel.notificacionesActivas,
              onChanged: viewModel.cambiarNotificaciones,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode),
              title: const Text('Modo oscuro'),
              value: viewModel.modoOscuro,
              onChanged: (_) => viewModel.alternarModoOscuro(),
            ),
            const Divider(),
            ListTile(
              key: const Key('boton_cerrar_sesion_perfil'),
              leading: const Icon(Icons.logout),
              title: const Text('Cerrar sesión'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _confirmarCierreSesion(context),
            ),
          ],
        );
      },
    );
  }
}
