/// Eventos globales de la aplicación que circulan por el `BusDeEventos`.
sealed class EventoDeApp {
  const EventoDeApp();
}

/// Se emite cuando la aplicación detecta conectividad y sincroniza pendientes.
class SincronizacionCompletada extends EventoDeApp {
  const SincronizacionCompletada(this.reportesSincronizados);

  final int reportesSincronizados;
}

/// Se emite cuando ocurre un error durante un ciclo de sincronización.
class ErrorSincronizacion extends EventoDeApp {
  const ErrorSincronizacion(this.mensaje);

  final String mensaje;
}

/// Se emite cuando se guarda un nuevo informe diario en terreno.
class InformeGuardado extends EventoDeApp {
  const InformeGuardado({
    required this.obraId,
    required this.obraFinalizada,
  });

  final String obraId;
  final bool obraFinalizada;
}

/// Se emite cuando se crea o modifica una obra o sus tareas.
class ObrasActualizadas extends EventoDeApp {
  const ObrasActualizadas({this.obraId});

  final String? obraId;
}

/// Se emite cuando se dispara una alerta proactiva de cambio de semáforo.
class AlertaSemaforoEmitida extends EventoDeApp {
  const AlertaSemaforoEmitida({required this.obraId});

  final String obraId;
}

/// Se emite cuando un usuario inicia o restaura su sesión.
class SesionIniciada extends EventoDeApp {
  const SesionIniciada({required this.usuarioId});

  final String usuarioId;
}

/// Se emite cuando la sesión del usuario se cierra.
class SesionCerrada extends EventoDeApp {
  const SesionCerrada();
}
