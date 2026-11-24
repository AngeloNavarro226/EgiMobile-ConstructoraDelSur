import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/obra.dart';
import '../../../domain/models/plantilla_obra.dart';
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
/// - Responsable asignado (Capataces o el propio ingeniero que crea la obra)
/// - Listado de tareas (obligatorio al menos 1) con catálogo personal rápido
/// - Materiales a utilizar (opcional) con catálogo personal rápido
/// - Ubicación de la obra seleccionada en el mapa de calles
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

  final List<String> _tareas = [];
  final List<String> _materiales = [];

  bool _guardarTareaEnCatalogo = false;
  bool _guardarMaterialEnCatalogo = false;
  bool _responsableElegidoManualmente = false;
  bool _guardando = false;
  String? _responsableIdSeleccionado;
  late UbicacionObra _ubicacionSeleccionada;
  EstadoObra _estado = EstadoObra.aTiempo;
  FotoComprimida? _fotoPortada;
  String? _errorNombre;
  String? _errorTareas;

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

  bool _contieneSinMayusculas(List<String> lista, String valor) {
    final objetivo = valor.trim().toLowerCase();
    return lista.any((e) => e.trim().toLowerCase() == objetivo);
  }

  void _alternarDesdeCatalogo(List<String> destino, String nombre) {
    final objetivo = nombre.trim().toLowerCase();
    final idx = destino.indexWhere((e) => e.trim().toLowerCase() == objetivo);
    setState(() {
      if (idx == -1) {
        destino.add(nombre.trim());
        if (identical(destino, _tareas)) {
          _errorTareas = null;
        }
      } else {
        destino.removeAt(idx);
      }
    });
  }

  Future<void> _agregarTareaALista() async {
    final texto = _controladorNuevaTarea.text.trim();
    if (texto.isEmpty) return;
    final debeGuardarEnCatalogo = _guardarTareaEnCatalogo;
    setState(() {
      if (!_contieneSinMayusculas(_tareas, texto)) {
        _tareas.add(texto);
      }
      _errorTareas = null;
      _controladorNuevaTarea.clear();
    });
    if (debeGuardarEnCatalogo) {
      await widget.viewModel.guardarPlantillaPersonal(
        tipo: TipoPlantilla.tarea,
        nombre: texto,
      );
    }
  }

  Future<void> _agregarMaterialALista() async {
    final texto = _controladorNuevoMaterial.text.trim();
    if (texto.isEmpty) return;
    final debeGuardarEnCatalogo = _guardarMaterialEnCatalogo;
    setState(() {
      if (!_contieneSinMayusculas(_materiales, texto)) {
        _materiales.add(texto);
      }
      _controladorNuevoMaterial.clear();
    });
    if (debeGuardarEnCatalogo) {
      await widget.viewModel.guardarPlantillaPersonal(
        tipo: TipoPlantilla.material,
        nombre: texto,
      );
    }
  }

  Future<void> _mostrarGestionCatalogo(TipoPlantilla tipo) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _DialogoGestionCatalogo(
        tipo: tipo,
        viewModel: widget.viewModel,
      ),
    );
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

  Usuario? _resolverResponsableActual(List<Usuario> disponibles) {
    if (disponibles.isEmpty) return null;
    if (_responsableElegidoManualmente && _responsableIdSeleccionado != null) {
      for (final u in disponibles) {
        if (u.id == _responsableIdSeleccionado) {
          return u;
        }
      }
    }
    return disponibles.first;
  }

  Future<void> _guardarObra() async {
    if (_guardando) return;
    final nombreVacio = _controladorNombre.text.trim().isEmpty;
    final sinTareas = _tareas.isEmpty;
    if (nombreVacio || sinTareas) {
      setState(() {
        _errorNombre = nombreVacio ? 'Ingresá el nombre de la obra' : null;
        _errorTareas = sinTareas
            ? 'Agregá al menos una tarea para poder crear la obra'
            : null;
      });
      return;
    }

    final disponibles = widget.viewModel.responsablesDisponibles;
    final responsable = _resolverResponsableActual(disponibles);
    if (responsable == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Todavía no se cargaron los responsables. Sincronizá e intentá de nuevo.',
          ),
        ),
      );
      return;
    }

    final nombreCreado = _controladorNombre.text.trim();
    setState(() => _guardando = true);
    try {
      await widget.viewModel.crearNuevaObra(
        nombre: nombreCreado,
        responsable: responsable,
        nombresTareas: List.from(_tareas),
        materiales: List.from(_materiales),
        ubicacion: _ubicacionSeleccionada,
        estadoInicial: _estado,
        observaciones: _controladorObservaciones.text,
        imagenPortadaPersonalizada:
            _fotoPortada?.bytesBase64 ?? _fotoPortada?.rutaLocal,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"$nombreCreado" creada correctamente. Se sincronizará automáticamente.',
          ),
        ),
      );

      _controladorNombre.clear();
      _controladorNuevaTarea.clear();
      _controladorNuevoMaterial.clear();
      _controladorObservaciones.clear();
      setState(() {
        _tareas.clear();
        _materiales.clear();
        _errorNombre = null;
        _errorTareas = null;
        _estado = EstadoObra.aTiempo;
        _fotoPortada = null;
        _ubicacionSeleccionada = widget.viewModel.ubicacionPorDefecto;
        _responsableElegidoManualmente = false;
        _responsableIdSeleccionado =
            disponibles.isNotEmpty ? disponibles.first.id : null;
      });

      widget.onGuardado();
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final responsables = widget.viewModel.responsablesDisponibles;
        final usuarioActual = widget.viewModel.usuarioActual;
        final responsableActivo = _resolverResponsableActual(responsables);
        final idValido = responsableActivo?.id;
        final tareasGuardadas = widget.viewModel.tareasGuardadas;
        final materialesGuardados = widget.viewModel.materialesGuardados;

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
                key: ValueKey(
                  '${idValido}_${responsables.map((r) => r.id).join(',')}',
                ),
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
                        u.id == usuarioActual?.id
                            ? '${u.nombre} (Yo · ${u.rol.etiqueta})'
                            : '${u.nombre} (${u.rol.etiqueta})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (nuevoId) {
                  if (nuevoId != null) {
                    setState(() {
                      _responsableElegidoManualmente = true;
                      _responsableIdSeleccionado = nuevoId;
                    });
                  }
                },
              )
            else
              const Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(Icons.sync),
                  title: Text('Cargando capataces y responsables...'),
                ),
              ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.map_outlined),
                title: const Text('Ubicación de la obra'),
                subtitle: Text(_ubicacionSeleccionada.etiquetaCompleta),
                trailing: FilledButton.tonalIcon(
                  onPressed: _seleccionarUbicacionEnMapa,
                  icon: const Icon(Icons.pin_drop_outlined),
                  label: const Text('Elegir en mapa'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                const Text(
                  'Listado de tareas de la obra *',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _mostrarGestionCatalogo(TipoPlantilla.tarea),
                  icon: const Icon(Icons.bookmarks_outlined, size: 16),
                  label: const Text('Mis tareas guardadas'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controladorNuevaTarea,
                    onSubmitted: (_) => unawaited(_agregarTareaALista()),
                    decoration: InputDecoration(
                      labelText: 'Añadir tarea al plan de la obra',
                      prefixIcon: const Icon(Icons.construction),
                      border: const OutlineInputBorder(),
                      errorText: _errorTareas,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => unawaited(_agregarTareaALista()),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _guardarTareaEnCatalogo,
              onChanged: (v) =>
                  setState(() => _guardarTareaEnCatalogo = v ?? false),
              title: const Text(
                'Guardar también en mi catálogo para futuras obras',
                style: TextStyle(fontSize: 13),
              ),
            ),
            if (tareasGuardadas.isNotEmpty) ...[
              Text(
                'Tocar para agregar rápido desde tus guardadas:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final plantilla in tareasGuardadas)
                    FilterChip(
                      label: Text(plantilla.nombre),
                      selected: _contieneSinMayusculas(
                        _tareas,
                        plantilla.nombre,
                      ),
                      onSelected: (_) =>
                          _alternarDesdeCatalogo(_tareas, plantilla.nombre),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (_tareas.isNotEmpty) ...[
              Text(
                'Tareas seleccionadas para esta obra (${_tareas.length}):',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
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
            ],
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                const Text(
                  'Materiales a utilizar (opcional)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () =>
                      _mostrarGestionCatalogo(TipoPlantilla.material),
                  icon: const Icon(Icons.bookmarks_outlined, size: 16),
                  label: const Text('Mis materiales guardados'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controladorNuevoMaterial,
                    onSubmitted: (_) => unawaited(_agregarMaterialALista()),
                    decoration: const InputDecoration(
                      labelText: 'Nombre del material (ej. Hormigón H-21)',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => unawaited(_agregarMaterialALista()),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _guardarMaterialEnCatalogo,
              onChanged: (v) =>
                  setState(() => _guardarMaterialEnCatalogo = v ?? false),
              title: const Text(
                'Guardar también en mi catálogo para futuras obras',
                style: TextStyle(fontSize: 13),
              ),
            ),
            if (materialesGuardados.isNotEmpty) ...[
              Text(
                'Tocar para agregar rápido desde tus guardados:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final plantilla in materialesGuardados)
                    FilterChip(
                      label: Text(plantilla.nombre),
                      selected: _contieneSinMayusculas(
                        _materiales,
                        plantilla.nombre,
                      ),
                      onSelected: (_) =>
                          _alternarDesdeCatalogo(_materiales, plantilla.nombre),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (_materiales.isNotEmpty) ...[
              Text(
                'Materiales seleccionados para esta obra (${_materiales.length}):',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
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
            ],
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
              onPressed: _guardando ? null : _guardarObra,
              icon: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_guardando ? 'Guardando obra...' : 'Guardar obra'),
            ),
          ],
        );
      },
    );
  }
}

class _DialogoGestionCatalogo extends StatefulWidget {
  const _DialogoGestionCatalogo({
    required this.tipo,
    required this.viewModel,
  });

  final TipoPlantilla tipo;
  final ObrasViewModel viewModel;

  @override
  State<_DialogoGestionCatalogo> createState() =>
      _DialogoGestionCatalogoState();
}

class _DialogoGestionCatalogoState extends State<_DialogoGestionCatalogo> {
  final TextEditingController _controladorNuevo = TextEditingController();

  @override
  void dispose() {
    _controladorNuevo.dispose();
    super.dispose();
  }

  Future<void> _guardarNuevo() async {
    final texto = _controladorNuevo.text.trim();
    if (texto.isEmpty) return;
    _controladorNuevo.clear();
    await widget.viewModel.guardarPlantillaPersonal(
      tipo: widget.tipo,
      nombre: texto,
    );
  }

  @override
  Widget build(BuildContext context) {
    final esTarea = widget.tipo == TipoPlantilla.tarea;
    final titulo = esTarea
        ? 'Gestionar tareas guardadas'
        : 'Gestionar materiales guardados';

    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final items = esTarea
            ? widget.viewModel.tareasGuardadas
            : widget.viewModel.materialesGuardados;
        return AlertDialog(
          title: Text(titulo),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controladorNuevo,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => unawaited(_guardarNuevo()),
                        decoration: InputDecoration(
                          labelText: esTarea
                              ? 'Nueva tarea frecuente'
                              : 'Nuevo material frecuente',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => unawaited(_guardarNuevo()),
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Todavía no guardaste elementos en tu catálogo.',
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (_, index) {
                        final plantilla = items[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(plantilla.nombre),
                          trailing: IconButton(
                            tooltip: 'Quitar de mi catálogo',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () {
                              unawaited(
                                widget.viewModel
                                    .eliminarPlantillaPersonal(plantilla.id),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Listo'),
            ),
          ],
        );
      },
    );
  }
}
