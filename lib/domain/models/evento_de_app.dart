/// Eventos globales de la aplicación que circulan por el `BusDeEventos`

sealed class EventoDeApp {
  const EventoDeApp();
}

/// Se emite cuando la aplicación detecta conectividad y sincroniza reportes.
class SincronizacionCompletada extends EventoDeApp {
  const SincronizacionCompletada(this.reportesSincronizados);

  final int reportesSincronizados;
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

/// Se emite cuando la sesión del usuario se cierra.
class SesionCerrada extends EventoDeApp {
  const SesionCerrada();
}
