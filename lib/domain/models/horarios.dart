/// Funciones puras de cálculo de horarios para tareas y recordatorios en
/// segundo plano
///
/// Reciben `ahora` por parámetro en lugar de llamar a `DateTime.now()` adentro,
/// lo que permite verificarlas con pruebas unitarias determinísticas.

/// Calcula el horario del recordatorio diario a las 18:00 del día actual.
DateTime horaDelRecordatorio(DateTime ahora) {
  return DateTime(ahora.year, ahora.month, ahora.day, 18, 0);
}

/// Devuelve la próxima ocurrencia de una hora y minuto diarios a partir de [ahora].
/// Si la hora ya pasó en el día de hoy, devuelve la ocurrencia de mañana.
DateTime proximaOcurrenciaDiaria({
  required DateTime ahora,
  required int hora,
  required int minuto,
}) {
  final hoy = DateTime(ahora.year, ahora.month, ahora.day, hora, minuto);
  if (hoy.isAfter(ahora)) return hoy;
  return hoy.add(const Duration(days: 1));
}
