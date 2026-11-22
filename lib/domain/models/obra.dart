import 'dart:convert';
import 'dart:typed_data';

import 'tarea_obra.dart';
import 'ubicacion_obra.dart';

/// Estado del sistema de semáforos para el monitoreo gerencial en tiempo real.
enum EstadoObra {
  aTiempo,
  demorada,
  problemas;

  /// Etiqueta legible para mostrar en los indicadores de estado.
  String get etiqueta => switch (this) {
        EstadoObra.aTiempo => 'A tiempo',
        EstadoObra.demorada => 'Demorada',
        EstadoObra.problemas => 'Con problemas',
      };

  /// Nombre del color del semáforo para alertas y reportes.
  String get nombreColor => switch (this) {
        EstadoObra.aTiempo => 'Verde',
        EstadoObra.demorada => 'Amarillo',
        EstadoObra.problemas => 'Rojo',
      };

  /// Indica si este estado requiere disparar una alerta proactiva a gerencia.
  bool get requiereAlertaProactiva =>
      this == EstadoObra.demorada || this == EstadoObra.problemas;

  String toStorage() => name;

  static EstadoObra fromStorage(String valor) => switch (valor) {
        'aTiempo' => EstadoObra.aTiempo,
        'demorada' => EstadoObra.demorada,
        _ => EstadoObra.problemas,
      };
}

/// Modelo de dominio de una Obra en ejecución.
///
/// Calcula automáticamente su porcentaje de [avance] en función de la
/// cantidad de tareas completadas dentro de [tareas], o 1.0 (100%) si la
/// obra fue marcada como [finalizada].
class Obra {
  const Obra({
    required this.id,
    required this.nombre,
    required this.estado,
    required this.fechaUltimoReporte,
    required this.responsableId,
    required this.responsableNombre,
    required this.tareas,
    required this.materiales,
    required this.ubicacion,
    this.observaciones = '',
    this.conFoto = false,
    this.imagen,
    this.finalizada = false,
  });

  final String id;
  final String nombre;
  final EstadoObra estado;
  final DateTime fechaUltimoReporte;
  final String responsableId;
  final String responsableNombre;
  final List<TareaObra> tareas;
  final List<String> materiales;
  final UbicacionObra ubicacion;
  final String observaciones;
  final bool conFoto;

  /// Puede ser una ruta de asset (`assets/images/obra1.png`) o una cadena
  /// Base64 con los bytes comprimidos de la foto de portada elegida al crear la obra.
  final String? imagen;

  /// Indica si la obra fue marcada como finalizada.
  ///
  /// Las obras finalizadas se ocultan por defecto de las vistas principales y
  /// solo se muestran cuando se selecciona el chip de filtro `"Finalizadas"`.
  final bool finalizada;

  /// Si [imagen] contiene una fotografía personalizada codificada en Base64,
  /// devuelve sus bytes listos para renderizar con `Image.memory`.
  Uint8List? get bytesImagenPortada {
    final valor = imagen;
    if (valor == null || valor.isEmpty || valor.startsWith('assets/')) {
      return null;
    }
    try {
      return base64Decode(valor);
    } catch (_) {
      return null;
    }
  }

  /// Porcentaje de avance entre 0.0 y 1.0 calculado automáticamente
  /// según la proporción de tareas completadas (o 1.0 si está finalizada).
  double get avance {
    if (finalizada) return 1.0;
    if (tareas.isEmpty) return 0.0;
    final completadas = tareas.where((t) => t.completada).length;
    return completadas / tareas.length;
  }

  /// Porcentaje entero (0 a 100) listo para mostrar en etiquetas y reportes.
  int get porcentajeAvance => (avance * 100).round();

  /// Devuelve el nombre de la tarea actualmente en curso (la primera pendiente,
  /// o el estado finalizado si la obra concluyó).
  String get tareaActual {
    if (finalizada) return 'Obra finalizada';
    if (tareas.isEmpty) return 'Sin tareas asignadas';
    for (final tarea in tareas) {
      if (!tarea.completada) return tarea.nombre;
    }
    return '${tareas.last.nombre} (Finalizada)';
  }

  /// Lista de tareas que ya fueron completadas.
  List<TareaObra> get tareasCompletas =>
      tareas.where((t) => t.completada).toList();

  /// Lista de tareas que aún están pendientes de finalización.
  List<TareaObra> get tareasPendientes =>
      tareas.where((t) => !t.completada).toList();

  /// Crea una copia inmutable de la obra con los campos modificados.
  Obra copyWith({
    String? nombre,
    EstadoObra? estado,
    DateTime? fechaUltimoReporte,
    String? responsableId,
    String? responsableNombre,
    List<TareaObra>? tareas,
    List<String>? materiales,
    UbicacionObra? ubicacion,
    String? observaciones,
    bool? conFoto,
    String? imagen,
    bool? finalizada,
  }) =>
      Obra(
        id: id,
        nombre: nombre ?? this.nombre,
        estado: estado ?? this.estado,
        fechaUltimoReporte: fechaUltimoReporte ?? this.fechaUltimoReporte,
        responsableId: responsableId ?? this.responsableId,
        responsableNombre: responsableNombre ?? this.responsableNombre,
        tareas: tareas ?? this.tareas,
        materiales: materiales ?? this.materiales,
        ubicacion: ubicacion ?? this.ubicacion,
        observaciones: observaciones ?? this.observaciones,
        conFoto: conFoto ?? this.conFoto,
        imagen: imagen ?? this.imagen,
        finalizada: finalizada ?? this.finalizada,
      );

  /// Convierte la obra a un mapa para almacenamiento en la tabla `obras` de SQLite.
  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'estado_semaforo': estado.toStorage(),
        'fecha_ultimo_reporte': fechaUltimoReporte.toIso8601String(),
        'responsable_id': responsableId,
        'responsable_nombre': responsableNombre,
        'tareas': jsonEncode(tareas.map((t) => t.toJson()).toList()),
        'materiales': jsonEncode(materiales),
        'ubicacion': jsonEncode(ubicacion.toJson()),
        'observaciones': observaciones,
        'con_foto': conFoto ? 1 : 0,
        'imagen': imagen,
        'finalizada': finalizada ? 1 : 0,
      };

  /// Reconstruye una instancia de [Obra] desde un registro de SQLite.
  factory Obra.fromMap(Map<String, dynamic> map) {
    final tareasDecodificadas =
        (jsonDecode(map['tareas'] as String) as List<dynamic>)
            .map((item) => TareaObra.fromJson(item as Map<String, dynamic>))
            .toList();
    final materialesDecodificados =
        (jsonDecode(map['materiales'] as String) as List<dynamic>)
            .map((e) => e.toString())
            .toList();
    final ubicacionDecodificada = UbicacionObra.fromJson(
      jsonDecode(map['ubicacion'] as String) as Map<String, dynamic>,
    );

    return Obra(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      estado: EstadoObra.fromStorage(map['estado_semaforo'] as String),
      fechaUltimoReporte: DateTime.parse(map['fecha_ultimo_reporte'] as String),
      responsableId: map['responsable_id'] as String,
      responsableNombre: (map['responsable_nombre'] as String?) ?? 'Capataz',
      tareas: tareasDecodificadas,
      materiales: materialesDecodificados,
      ubicacion: ubicacionDecodificada,
      observaciones: (map['observaciones'] as String?) ?? '',
      conFoto: (map['con_foto'] as int? ?? 0) == 1,
      imagen: map['imagen'] as String?,
      finalizada: (map['finalizada'] as int? ?? 0) == 1,
    );
  }
}
