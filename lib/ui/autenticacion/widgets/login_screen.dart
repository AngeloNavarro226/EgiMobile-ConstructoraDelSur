import 'package:flutter/material.dart';

import '../view_models/autenticacion_view_model.dart';

/// Pantalla de inicio de sesión simple con usuario, contraseña y botón de
/// ingreso. Si las credenciales son incorrectas, muestra el mensaje
/// `"Usuario o contraseña inválidos"` exactamente debajo del campo de
/// contraseña, entre el TextField y el botón para iniciar sesión.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.viewModel,
  });

  final AutenticacionViewModel viewModel;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _controladorUsuario = TextEditingController();
  final TextEditingController _controladorContrasenia = TextEditingController();

  @override
  void dispose() {
    _controladorUsuario.dispose();
    _controladorContrasenia.dispose();
    super.dispose();
  }

  Future<void> _intentarIngreso() async {
    await widget.viewModel.iniciarSesion(
      usuario: _controladorUsuario.text,
      contrasenia: _controladorContrasenia.text,
    );
  }

  void _autocompletarCredencialPrueba(String usuario, String contrasenia) {
    _controladorUsuario.text = usuario;
    _controladorContrasenia.text = contrasenia;
    widget.viewModel.limpiarError();
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListenableBuilder(
                listenable: widget.viewModel,
                builder: (context, _) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.engineering,
                        size: 64,
                        color: colores.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Constructora Del Sur',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sistema Offline-First de Gestión de Obras',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        key: const Key('campo_usuario'),
                        controller: _controladorUsuario,
                        onChanged: (_) => widget.viewModel.limpiarError(),
                        decoration: const InputDecoration(
                          labelText: 'Usuario',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('campo_contrasenia'),
                        controller: _controladorContrasenia,
                        obscureText: true,
                        onChanged: (_) => widget.viewModel.limpiarError(),
                        onSubmitted: (_) => _intentarIngreso(),
                        decoration: const InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Mensaje de error situado justo debajo del campo de contraseña,
                      // entre medio de la textbar y el botón para iniciar sesión.
                      if (widget.viewModel.credencialesInvalidas)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Usuario o contraseña inválidos',
                            key: const Key('mensaje_credenciales_invalidas'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colores.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          key: const Key('boton_iniciar_sesion'),
                          onPressed: widget.viewModel.estaCargando
                              ? null
                              : _intentarIngreso,
                          icon: const Icon(Icons.login),
                          label: const Text('Entrar'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _TarjetaUsuariosPrueba(
                        onSeleccionar: _autocompletarCredencialPrueba,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TarjetaUsuariosPrueba extends StatelessWidget {
  const _TarjetaUsuariosPrueba({required this.onSeleccionar});

  final void Function(String usuario, String contrasenia) onSeleccionar;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Usuarios de prueba en BD SQLite local (contraseña: 1234):',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.engineering, size: 16),
                  label: const Text('ingeniero / 1234'),
                  onPressed: () => onSeleccionar('ingeniero', '1234'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.construction, size: 16),
                  label: const Text('capataz / 1234'),
                  onPressed: () => onSeleccionar('capataz', '1234'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.business_center, size: 16),
                  label: const Text('dueno / 1234'),
                  onPressed: () => onSeleccionar('dueno', '1234'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
