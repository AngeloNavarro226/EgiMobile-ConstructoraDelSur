/// Estado de sincronización local-remoto para el flujo Offline-First.
enum EstadoSincronizacion {
  pending,
  synced,
  error;

  String get etiqueta => switch (this) {
        EstadoSincronizacion.pending => 'Pendiente de sincronizar',
        EstadoSincronizacion.synced => 'Sincronizado',
        EstadoSincronizacion.error => 'Error al sincronizar',
      };

  String toStorage() => name;

  static EstadoSincronizacion fromStorage(String valor) => switch (valor) {
        'synced' => EstadoSincronizacion.synced,
        'error' => EstadoSincronizacion.error,
        _ => EstadoSincronizacion.pending,
      };
}
