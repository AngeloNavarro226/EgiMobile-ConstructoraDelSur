/// Roles disponibles en el sistema Constructora Del Sur.
enum RolUsuario {
  capataz,
  duenio,
  ingeniero;

  /// Etiqueta legible para mostrar en la interfaz de usuario.
  String get etiqueta => switch (this) {
        RolUsuario.capataz => 'Capataz de Obra',
        RolUsuario.duenio => 'Dueño / Gerencia',
        RolUsuario.ingeniero => 'Ingeniero Jefe de Obra',
      };

  /// Convierte el valor en texto para almacenamiento en SQLite.
  String toStorage() => name;

  /// Reconstruye el rol desde una cadena almacenada en SQLite.
  static RolUsuario fromStorage(String valor) => switch (valor) {
        'capataz' => RolUsuario.capataz,
        'duenio' || 'dueno' => RolUsuario.duenio,
        _ => RolUsuario.ingeniero,
      };
}

/// Representa un usuario autenticado o asignable dentro de la aplicación.
class Usuario {
  const Usuario({
    required this.id,
    required this.username,
    required this.nombre,
    required this.contrasenia,
    required this.rol,
    this.telefono = '',
  });

  final String id;
  final String username;
  final String nombre;
  final String contrasenia;
  final RolUsuario rol;
  final String telefono;

  /// Crea una copia del usuario con los campos actualizados.
  Usuario copyWith({
    String? nombre,
    String? contrasenia,
    String? telefono,
  }) =>
      Usuario(
        id: id,
        username: username,
        nombre: nombre ?? this.nombre,
        contrasenia: contrasenia ?? this.contrasenia,
        rol: rol,
        telefono: telefono ?? this.telefono,
      );

  /// Convierte la instancia a un mapa compatible con la tabla `usuarios` de SQLite.
  Map<String, dynamic> toMap() => {
        'id': id,
        'username': username,
        'rol': rol.toStorage(),
        'nombre': nombre,
        'contrasenia': contrasenia,
        'telefono': telefono,
      };

  /// Construye un [Usuario] desde una fila de la tabla `usuarios` de SQLite.
  factory Usuario.fromMap(Map<String, dynamic> map) => Usuario(
        id: map['id'] as String,
        username: (map['username'] as String?) ?? (map['id'] as String),
        rol: RolUsuario.fromStorage(map['rol'] as String),
        nombre: map['nombre'] as String,
        contrasenia: map['contrasenia'] as String,
        telefono: (map['telefono'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Usuario && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
