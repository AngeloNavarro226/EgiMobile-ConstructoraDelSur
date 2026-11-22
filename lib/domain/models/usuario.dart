import 'estado_sincronizacion.dart';
import 'rol.dart';

export 'rol.dart';

/// Representa un usuario autenticado o asignable dentro de la aplicación.
///
/// Se vincula con [Rol] mediante la clave foránea `rol_id` (1 rol → N usuarios).
class Usuario {
  const Usuario({
    required this.id,
    required this.username,
    required this.nombre,
    required this.contrasenia,
    required this.rol,
    this.telefono = '',
    this.updatedAt,
    this.syncStatus = EstadoSincronizacion.synced,
  });

  final String id;
  final String username;
  final String nombre;
  final String contrasenia;
  final Rol rol;
  final String telefono;
  final DateTime? updatedAt;
  final EstadoSincronizacion syncStatus;

  /// Identificador de la clave foránea hacia la tabla `roles`.
  String get rolId => rol.id;

  /// Enum operativo equivalente del rol asignado.
  RolUsuario get tipoRol => rol.tipo;

  /// Crea una copia del usuario con los campos actualizados.
  Usuario copyWith({
    String? nombre,
    String? contrasenia,
    String? telefono,
    Rol? rol,
    DateTime? updatedAt,
    EstadoSincronizacion? syncStatus,
  }) =>
      Usuario(
        id: id,
        username: username,
        nombre: nombre ?? this.nombre,
        contrasenia: contrasenia ?? this.contrasenia,
        rol: rol ?? this.rol,
        telefono: telefono ?? this.telefono,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );

  /// Convierte la instancia a un mapa compatible con la tabla `usuarios` de SQLite.
  Map<String, dynamic> toMap() => {
        'id': id,
        'username': username,
        'rol_id': rol.id,
        'nombre': nombre,
        'contrasenia': contrasenia,
        'telefono': telefono,
        'updated_at':
            (updatedAt ?? DateTime.utc(2026)).toUtc().toIso8601String(),
        'sync_status': syncStatus.toStorage(),
      };

  /// Construye un [Usuario] desde una fila de `usuarios` unida con `roles`.
  factory Usuario.fromMap(Map<String, dynamic> map) {
    final rolId = map['rol_id'] as String?;
    final rolCodigo = map['rol_codigo'] as String?;
    final rolNombre = map['rol_nombre'] as String?;

    final rol = (rolId != null && rolCodigo != null && rolNombre != null)
        ? Rol(id: rolId, codigo: rolCodigo, nombre: rolNombre)
        : Rol.desdeStorage(rolId ?? 'rol_ingeniero');

    final updatedAtRaw = map['updated_at'] as String?;

    return Usuario(
      id: map['id'] as String,
      username: (map['username'] as String?) ?? (map['id'] as String),
      rol: rol,
      nombre: map['nombre'] as String,
      contrasenia: (map['contrasenia'] as String?) ?? '',
      telefono: (map['telefono'] as String?) ?? '',
      updatedAt: updatedAtRaw != null ? DateTime.parse(updatedAtRaw) : null,
      syncStatus: EstadoSincronizacion.fromStorage(
        (map['sync_status'] as String?) ?? 'synced',
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Usuario && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
