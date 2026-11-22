import 'package:flutter/material.dart';

import '../../../domain/models/obra.dart';
import '../../../domain/models/reporte_diario.dart';
import '../../../domain/models/ubicacion_obra.dart';
import '../../../domain/models/usuario.dart';
import '../../../plataforma/capacidades.dart';
import '../../core/selector_ubicacion_dialog.dart';
import '../../core/visor_foto_informe.dart';
import '../view_models/obras_view_model.dart';

/// Vista exclusiva del Ingeniero para crear nuevas obras asignando:
/// - Nombre de la obra
/// - Foto de portada de la obra (cámara o galería, comprimida a 800x600 70%)
/// - Responsable asignado (Capataz / Ingeniero)
/// - Listado completo de tareas de la obra
/// - Materiales que se van a utilizar (nombres, sin cantidades)
/// - Ubicación de la obra seleccionada mediante Google Maps con transcripción
///   del nombre del lugar desde las coordenadas
class AgregarObraScreen extends StatefulWidget {
  const AgregarObraScreen({
    super.key,
    required this.viewModel,
    required this.capacidades,
    required this.onGuardado,
  });

  final ObrasViewModel viewModel;
  final Capacidades capacidades;
  final VoidCallback onGuardado;

  @override
  State<AgregarObraScreen> createState() => _AgregarObraScreenState();
}

class _AgregarObraScreenState extends State<AgregarObraScreen> {
  final TextEditingController _controladorNombre = TextEditingController();
  final TextEditingController _controladorNuevaTarea = TextEditingController();
  final TextEditingController _controladorNuevoMaterial =
      TextEditingController();
  final TextEditingController _controladorObservaciones =
      TextEditingController();

  final List<String> _tareas = [
    'Replanteo y nivelación de terreno',
    'Excavación de fundaciones',
    'Hormigonado de estructura',
  ];
  final List<String> _materiales = [
    'Hormigón H-21',
    'Hierro nervado 12mm',
    'Cemento Portland',
  ];

  String? _responsableIdSeleccionado;
  late UbicacionObra _ubicacionSeleccionada;
  EstadoObra _estado = EstadoObra.aTiempo;
  FotoComprimida? _fotoPortada;
  String? _errorNombre;

  @override
  void initState() {
    super.initState();
    _ubicacionSeleccionada = widget.viewModel.ubicacionPorDefecto;
    final disponibles = widget.viewModel.responsablesDisponibles;
    if (disponibles.isNotEmpty) {
      _responsableIdSeleccionado = disponibles.first.id;
    }
  }

  @override
  void dispose() {
    _controladorNombre.dispose();
    _controladorNuevaTarea.dispose();
    _controladorNuevoMaterial.dispose();
    _controladorObservaciones.dispose();
    super.dispose();
  }

  void _agregarTareaALista() {
    final texto = _controladorNuevaTarea.text.trim();
    if (texto.isEmpty) return;
    setState(() {
      _tareas.add(texto);
      _controladorNuevaTarea.clear();
    });
  }

  void _agregarMaterialALista() {
    final texto = _controladorNuevoMaterial.text.trim();
    if (texto.isEmpty) return;
    setState(() {
      _materiales.add(texto);
      _controladorNuevoMaterial.clear();
    });
  }

  Future<void> _seleccionarFotoPortada({required bool desdeCamara}) async {
    final foto = await widget.viewModel.adjuntarFotoComprimida(
      desdeCamara: desdeCamara,
    );
    if (!mounted || foto == null) return;
    setState(() {
      _fotoPortada = foto;
    });
  }

  Future<void> _seleccionarUbicacionEnMapa() async {
    final resultado = await showDialog<UbicacionObra>(
      context: context,
      builder: (_) => SelectorUbicacionMapaDialog(
        ubicacionInicial: _ubicacionSeleccionada,
        ubicacionesSugeridas: widget.viewModel.ubicacionesSugeridas,
        onResolverNombreLugar:
            widget.viewModel.obtenerNombreLugarDesdeCoordenadas,
      ),
    );
    if (resultado != null && mounted) {
      setState(() => _ubicacionSeleccionada = resultado);
    }
  }

  Usuario _resolverResponsableActual(List<Usuario> disponibles) {
    for (final u in disponibles) {
      if (u.id == _responsableIdSeleccionado) {
        return u;
      }
    }
    if (disponibles.isNotEmpty) {
      return disponibles.first;
    }
    return const Usuario(
      id: 'u_capataz',
      username: 'capataz',
      nombre: 'Carlos Méndez (Capataz)',
      contrasenia: '1234',
      rol: RolUsuario.capataz,
    );
  }

  Future<void> _guardarObra() async {
    if (_controladorNombre.text.trim().isEmpty) {
      setState(() => _errorNombre = 'Ingresá el nombre de la obra');
      return;
    }
    final disponibles = widget.viewModel.responsablesDisponibles;
    final responsable = _resolverResponsableActual(disponibles);

    await widget.viewModel.crearNuevaObra(
      nombre: _controladorNombre.text,
      responsable: responsable,
      nombresTareas:
          _tareas.isEmpty ? ['Tarea inicial de obra'] : List.from(_tareas),
      materiales: _materiales.isEmpty
          ? ['Cemento Portland']
          : List.from(_materiales),
      ubicacion: _ubicacionSeleccionada,
      estadoInicial: _estado,
      observaciones: _controladorObservaciones.text,
      imagenPortadaPersonalizada:
          _fotoPortada?.bytesBase64 ?? _fotoPortada?.rutaLocal,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${_controladorNombre.text.trim()}" creada en SQLite'),
      ),
    );

    _controladorNombre.clear();
    _controladorObservaciones.clear();
    setState(() {
      _errorNombre = null;
      _estado = EstadoObra.aTiempo;
      _fotoPortada = null;
    });

    widget.onGuardado();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final responsables = widget.viewModel.responsablesDisponibles;
        final idValido = responsables.any(
          (u) => u.id == _responsableIdSeleccionado,
        )
            ? _responsableIdSeleccionado
            : (responsables.isNotEmpty ? responsables.first.id : null);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Administrar y crear nueva obra',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controladorNombre,
              decoration: InputDecoration(
                labelText: 'Nombre de la obra',
                prefixIcon: const Icon(Icons.apartment),
                border: const OutlineInputBorder(),
                errorText: _errorNombre,
              ),
              onChanged: (_) {
                if (_errorNombre != null) setState(() => _errorNombre = null);
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Foto de portada de la obra',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_fotoPortada != null)
              MiniaturaFotoInforme(
                foto: _fotoPortada!,
                onEliminar: () => setState(() => _fotoPortada = null),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _seleccionarFotoPortada(desdeCamara: false),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Cargar portada'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: widget.capacidades.tieneCamara
                          ? () => _seleccionarFotoPortada(desdeCamara: true)
                          : null,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(
                        widget.capacidades.tieneCamara
                            ? 'Tomar con cámara'
                            : 'Cámara no disp.',
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            if (responsables.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey(idValido),
                initialValue: idValido,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Responsable asignado',
                  prefixIcon: Icon(Icons.person_pin_outlined),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final u in responsables)
                    DropdownMenuItem<String>(
                      value: u.id,
                      child: Text(
                        '${u.nombre} (${u.rol.etiqueta})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (nuevoId) {
                  if (nuevoId != null) {
                    setState(() => _responsableIdSeleccionado = nuevoId);
                  }
                },
              ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.map_outlined),
                title: const Text('Ubicación de la obra (Google Maps)'),
                subtitle: Text(_ubicacionSeleccionada.etiquetaCompleta),
                trailing: FilledButton.tonalIcon(
                  onPressed: _seleccionarUbicacionEnMapa,
                  icon: const Icon(Icons.pin_drop_outlined),
                  label: const Text('Google Maps'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Listado de tareas de la obra',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controladorNuevaTarea,
                    onSubmitted: (_) => _agregarTareaALista(),
                    decoration: const InputDecoration(
                      labelText: 'Añadir tarea al plan de la obra',
                      prefixIcon: Icon(Icons.construction),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _agregarTareaALista,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _tareas.length; i++)
                  InputChip(
                    label: Text(_tareas[i]),
                    onDeleted: () => setState(() => _tareas.removeAt(i)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Materiales a utilizar (nombres)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controladorNuevoMaterial,
                    onSubmitted: (_) => _agregarMaterialALista(),
                    decoration: const InputDecoration(
                      labelText: 'Nombre del material (ej. Hormigón H-21)',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _agregarMaterialALista,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _materiales.length; i++)
                  InputChip(
                    label: Text(_materiales[i]),
                    onDeleted: () => setState(() => _materiales.removeAt(i)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Estado inicial del semáforo',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SegmentedButton<EstadoObra>(
              showSelectedIcon: false,
              segments: [
                for (final e in EstadoObra.values)
                  ButtonSegment(
                    value: e,
                    label: Text(
                      e.etiqueta,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
              selected: {_estado},
              onSelectionChanged: (s) => setState(() => _estado = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controladorObservaciones,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observaciones iniciales',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _guardarObra,
              icon: const Icon(Icons.save),
              label: const Text('Guardar obra'),
            ),
          ],
        );
      },
    );
  }
}
