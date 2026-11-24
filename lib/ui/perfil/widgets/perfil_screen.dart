import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/usuario.dart';
import '../../autenticacion/view_models/autenticacion_view_model.dart';
import '../../obras/view_models/obras_view_model.dart';
import '../view_models/perfil_view_model.dart';

/// Pantalla de Perfil compartida por los 3 roles (Ingeniero, Capataz y Dueño).
///
/// Permite:
/// - Ver y modificar los datos del perfil activo (nombre, teléfono y contraseña).
/// - Ejecutar una sincronización manual real con el servidor.
/// - Alternar el modo oscuro y las notificaciones.
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

    final actualizado = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoEditarPerfil(
        usuario: usuario,
        viewModel: viewModel,
        autenticacionViewModel: autenticacionViewModel,
      ),
    );

    if (actualizado == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil actualizado correctamente')),
      );
    }
  }

  Future<void> _ejecutarSincronizacionManual(BuildContext context) async {
    await obrasViewModel.iniciarSincronizacionConAlerta();
    if (!context.mounted) return;
    final error = obrasViewModel.mensajeErrorSincronizacion;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? 'Sincronización finalizada correctamente.',
        ),
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
        final pendientes = obrasViewModel.cantidadReportesPendientes;
        final sincronizando = obrasViewModel.sincronizando;

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
                    : () => unawaited(_mostrarDialogoEditarPerfil(context)),
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
                pendientes == 0
                    ? 'Obras visibles en este perfil (sin informes pendientes)'
                    : 'Obras visibles en este perfil ($pendientes pendientes de sincronizar)',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Sincronización manual'),
              subtitle: Text(
                sincronizando
                    ? 'Sincronizando datos con el servidor...'
                    : (pendientes > 0
                        ? 'Tenés $pendientes informe(s) pendiente(s) de subir.'
                        : 'Todo al día. Tocá para buscar cambios en la nube.'),
              ),
              trailing: FilledButton.tonal(
                key: const Key('btn_sincronizar_manual_perfil'),
                onPressed: sincronizando
                    ? null
                    : () => unawaited(_ejecutarSincronizacionManual(context)),
                child: sincronizando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sincronizar'),
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

class _DialogoEditarPerfil extends StatefulWidget {
  const _DialogoEditarPerfil({
    required this.usuario,
    required this.viewModel,
    required this.autenticacionViewModel,
  });

  final Usuario usuario;
  final PerfilViewModel viewModel;
  final AutenticacionViewModel autenticacionViewModel;

  @override
  State<_DialogoEditarPerfil> createState() => _DialogoEditarPerfilState();
}

class _DialogoEditarPerfilState extends State<_DialogoEditarPerfil> {
  late final TextEditingController _ctrlNombre;
  late final TextEditingController _ctrlTelefono;
  late final TextEditingController _ctrlContrasenia;
  bool _ocultarContrasenia = true;
  bool _guardando = false;
  String? _errorNombre;

  @override
  void initState() {
    super.initState();
    _ctrlNombre = TextEditingController(text: widget.usuario.nombre);
    _ctrlTelefono = TextEditingController(text: widget.usuario.telefono);
    _ctrlContrasenia = TextEditingController();
  }

  @override
  void dispose() {
    _ctrlNombre.dispose();
    _ctrlTelefono.dispose();
    _ctrlContrasenia.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    if (_ctrlNombre.text.trim().isEmpty) {
      setState(() => _errorNombre = 'Ingresá tu nombre completo');
      return;
    }

    setState(() => _guardando = true);
    final ok = await widget.viewModel.actualizarDatosPerfil(
      nombre: _ctrlNombre.text,
      telefono: _ctrlTelefono.text,
      contrasenia: _ctrlContrasenia.text,
    );
    if (ok) {
      widget.autenticacionViewModel.notificarPerfilActualizado();
    }
    if (!mounted) return;
    setState(() => _guardando = false);
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modificar mi perfil'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('campo_perfil_nombre'),
              controller: _ctrlNombre,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_errorNombre != null) {
                  setState(() => _errorNombre = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: const Icon(Icons.person_outline),
                border: const OutlineInputBorder(),
                errorText: _errorNombre,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('campo_perfil_telefono'),
              controller: _ctrlTelefono,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Teléfono de contacto',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('campo_perfil_contrasenia'),
              controller: _ctrlContrasenia,
              obscureText: _ocultarContrasenia,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => unawaited(_guardar()),
              decoration: InputDecoration(
                labelText: 'Nueva contraseña (opcional)',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _ocultarContrasenia
                      ? 'Mostrar contraseña'
                      : 'Ocultar contraseña',
                  icon: Icon(
                    _ocultarContrasenia
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () {
                    setState(
                      () => _ocultarContrasenia = !_ocultarContrasenia,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : () => unawaited(_guardar()),
          child: Text(_guardando ? 'Guardando...' : 'Guardar cambios'),
        ),
      ],
    );
  }
}
