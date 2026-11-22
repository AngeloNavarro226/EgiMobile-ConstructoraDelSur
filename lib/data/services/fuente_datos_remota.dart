import 'dart:typed_data';

/// Conjunto incremental de cambios descargados desde el servidor remoto
/// durante el paso *Pull* del ciclo Offline-First.
class CambiosRemotos {
  const CambiosRemotos({
    this.roles = const [],
    this.usuarios = const [],
    this.obras = const [],
    this.tareas = const [],
    this.reportes = const [],
    this.notificaciones = const [],
  });

  final List<Map<String, dynamic>> roles;
  final List<Map<String, dynamic>> usuarios;
  final List<Map<String, dynamic>> obras;
  final List<Map<String, dynamic>> tareas;
  final List<Map<String, dynamic>> reportes;
  final List<Map<String, dynamic>> notificaciones;

  bool get estaVacio =>
      roles.isEmpty &&
      usuarios.isEmpty &&
      obras.isEmpty &&
      tareas.isEmpty &&
      reportes.isEmpty &&
      notificaciones.isEmpty;
}

/// Contrato remoto (seam) para desacoplar el motor de sincronización y los
/// repositorios del proveedor concreto de nube (Supabase en Fase 1).
abstract interface class FuenteDatosRemota {
  /// Indica si la fuente remota está configurada y habilitada para operar.
  bool get estaDisponible;

  /// Sube una fotografía comprimida (< 200 KB) al bucket remoto y devuelve su URL.
  Future<String> subirFoto({
    required String rutaLocal,
    required String destinoStorage,
    Uint8List? bytes,
  });

  /// Inserta o actualiza un usuario en el servidor (operación idempotente).
  Future<void> upsertUsuario(Map<String, dynamic> usuario);

  /// Inserta o actualiza una obra junto con sus materiales.
  Future<void> upsertObra({
    required Map<String, dynamic> obra,
    required List<String> materiales,
  });

  /// Inserta o actualiza una tarea individual de una obra.
  Future<void> upsertTarea(Map<String, dynamic> tarea);

  /// Inserta o actualiza un reporte diario junto con materiales y fotos ya subidas.
  Future<void> upsertReporte({
    required Map<String, dynamic> reporte,
    required List<String> materiales,
    required List<Map<String, dynamic>> fotos,
  });

  /// Inserta o actualiza una notificación en el servidor.
  Future<void> upsertNotificacion(Map<String, dynamic> notificacion);

  /// Descarga los cambios modificados con posterioridad a [ultimaSyncUtc].
  Future<CambiosRemotos> obtenerCambiosDesde(DateTime? ultimaSyncUtc);

  /// Stream en tiempo real que emite el nombre de la tabla remota modificada
  /// por otro dispositivo (respetando RLS).
  Stream<String> escucharCambiosRemotos();
}

/// Implementación local/offline por defecto mientras Supabase Cloud no está
/// conectado. Permite compilar, probar y operar sin credenciales remotas.
class FuenteDatosRemotaOffline implements FuenteDatosRemota {
  const FuenteDatosRemotaOffline();

  @override
  bool get estaDisponible => false;

  @override
  Future<String> subirFoto({
    required String rutaLocal,
    required String destinoStorage,
    Uint8List? bytes,
  }) async =>
      rutaLocal;

  @override
  Future<void> upsertUsuario(Map<String, dynamic> usuario) async {}

  @override
  Future<void> upsertObra({
    required Map<String, dynamic> obra,
    required List<String> materiales,
  }) async {}

  @override
  Future<void> upsertTarea(Map<String, dynamic> tarea) async {}

  @override
  Future<void> upsertReporte({
    required Map<String, dynamic> reporte,
    required List<String> materiales,
    required List<Map<String, dynamic>> fotos,
  }) async {}

  @override
  Future<void> upsertNotificacion(Map<String, dynamic> notificacion) async {}

  @override
  Future<CambiosRemotos> obtenerCambiosDesde(DateTime? ultimaSyncUtc) async =>
      const CambiosRemotos();

  @override
  Stream<String> escucharCambiosRemotos() => const Stream<String>.empty();
}
