import 'dart:async';

import 'package:flutter/material.dart';

import '../view_models/autenticacion_view_model.dart';

/// Pantalla de inicio de sesión limpia para producción con usuario/correo,
/// contraseña con opción de mostrar/ocultar, navegación con teclado y spinner
/// de carga.
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
  final FocusNode _focoContrasenia = FocusNode();
  bool _ocultarContrasenia = true;

  @override
  void dispose() {
    _controladorUsuario.dispose();
    _controladorContrasenia.dispose();
    _focoContrasenia.dispose();
    super.dispose();
  }

  Future<void> _intentarIngreso() async {
    await widget.viewModel.iniciarSesion(
      usuario: _controladorUsuario.text,
      contrasenia: _controladorContrasenia.text,
    );
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
                  return AutofillGroup(
                    child: Column(
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
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Gestión de Obras e Informes Diarios',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 28),
                        TextField(
                          key: const Key('campo_usuario'),
                          controller: _controladorUsuario,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          onChanged: (_) => widget.viewModel.limpiarError(),
                          onSubmitted: (_) => _focoContrasenia.requestFocus(),
                          decoration: const InputDecoration(
                            labelText: 'Usuario o correo electrónico',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          key: const Key('campo_contrasenia'),
                          controller: _controladorContrasenia,
                          focusNode: _focoContrasenia,
                          obscureText: _ocultarContrasenia,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onChanged: (_) => widget.viewModel.limpiarError(),
                          onSubmitted: (_) => unawaited(_intentarIngreso()),
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              key: const Key(
                                'btn_toggle_visibilidad_contrasenia',
                              ),
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
                                  () => _ocultarContrasenia =
                                      !_ocultarContrasenia,
                                );
                              },
                            ),
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
                        if (widget.viewModel.mensajeError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              widget.viewModel.mensajeError!,
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
                                : () => unawaited(_intentarIngreso()),
                            icon: widget.viewModel.estaCargando
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.login),
                            label: Text(
                              widget.viewModel.estaCargando
                                  ? 'Ingresando...'
                                  : 'Entrar',
                            ),
                          ),
                        ),
                      ],
                    ),
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
