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

/// Representa un rol operativo persistido en la tabla `roles` de SQLite.
///
/// Se vincula en relación 1-1 con `usuarios` a través de `usuarios.rol_id`.
class Rol {
  const Rol({
    required this.id,
    required this.codigo,
    required this.nombre,
  });

  final String id;
  final String codigo;
  final String nombre;

  static const Rol ingeniero = Rol(
    id: 'rol_ingeniero',
    codigo: 'ingeniero',
    nombre: 'Ingeniero Jefe de Obra',
  );

  static const Rol capataz = Rol(
    id: 'rol_capataz',
    codigo: 'capataz',
    nombre: 'Capataz de Obra',
  );

  static const Rol duenio = Rol(
    id: 'rol_duenio',
    codigo: 'duenio',
    nombre: 'Dueño / Gerencia',
  );

  /// Catálogo con los 3 roles operativos del proyecto.
  static const List<Rol> predefinidos = [ingeniero, capataz, duenio];

  /// Tipo fuertemente tipado usado por [Politicas] y la navegación.
  RolUsuario get tipo => RolUsuario.fromStorage(codigo);

  /// Etiqueta legible del rol para mostrar en pantalla.
  String get etiqueta => nombre;

  /// Obtiene el [Rol] correspondiente a un [RolUsuario].
  static Rol desdeTipo(RolUsuario tipo) => switch (tipo) {
        RolUsuario.ingeniero => ingeniero,
        RolUsuario.capataz => capataz,
        RolUsuario.duenio => duenio,
      };

  /// Reconstruye un [Rol] predefinido a partir de su `id` o `codigo`.
  static Rol desdeStorage(String valor) => switch (valor) {
        'rol_capataz' || 'capataz' => capataz,
        'rol_duenio' || 'duenio' || 'dueno' => duenio,
        _ => ingeniero,
      };

  /// Convierte la instancia a un mapa compatible con la tabla `roles` de SQLite.
  Map<String, dynamic> toMap() => {
        'id': id,
        'codigo': codigo,
        'nombre': nombre,
      };

  /// Construye un [Rol] desde una fila de la tabla `roles` de SQLite.
  factory Rol.fromMap(Map<String, dynamic> map) => Rol(
        id: map['id'] as String,
        codigo: map['codigo'] as String,
        nombre: map['nombre'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Rol && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
