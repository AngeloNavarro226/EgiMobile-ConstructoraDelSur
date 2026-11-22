/// Modelo de dominio de un aviso del sistema operativo
///
/// Desacopla la representación del aviso en el dominio de los tipos concretos
/// de cualquier plugin de notificaciones nativas.
class Aviso {
  const Aviso({
    required this.id,
    required this.titulo,
    required this.cuerpo,
    this.alTocar,
  });

  final int id;
  final String titulo;
  final String cuerpo;

  /// Identificador de navegación o acción asociada cuando el usuario toca la
  /// notificación en la barra de estado (ej. `'obra:1'`).
  final String? alTocar;
}
