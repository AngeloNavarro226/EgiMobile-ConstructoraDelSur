// Funciones puras de formateo de fechas y tiempos relativos en español.
//
// Reciben [ahora] por parámetro en lugar de llamar a `DateTime.now()`, lo que
// permite pruebas determinísticas inyectando `Reloj`.

String _dosDigitos(int valor) => valor.toString().padLeft(2, '0');

/// Formatea una fecha y hora en formato corto argentino 24hs:
/// `dd/MM/yyyy HH:mm hs`.
String formatearFechaHoraCorta(DateTime fecha) {
  final local = fecha.toLocal();
  final dia = _dosDigitos(local.day);
  final mes = _dosDigitos(local.month);
  final anio = local.year;
  final hora = _dosDigitos(local.hour);
  final minuto = _dosDigitos(local.minute);
  return '$dia/$mes/$anio $hora:$minuto hs';
}

/// Formatea solo la fecha en formato corto argentino: `dd/MM/yyyy`.
String formatearFechaCorta(DateTime fecha) {
  final local = fecha.toLocal();
  final dia = _dosDigitos(local.day);
  final mes = _dosDigitos(local.month);
  final anio = local.year;
  return '$dia/$mes/$anio';
}

/// Devuelve una etiqueta relativa fácil de leer en obra:
/// - `"Hoy HH:mm"` si corresponde al mismo día calendario que [ahora]
/// - `"Ayer HH:mm"` si corresponde al día anterior
/// - `"Hace N días"` si ocurrió entre 2 y 7 días atrás
/// - `"dd/MM/yyyy"` para fechas más antiguas o futuras
String formatearTiempoRelativo(
  DateTime fecha, {
  required DateTime ahora,
}) {
  final f = fecha.toLocal();
  final ref = ahora.toLocal();
  final diaFecha = DateTime(f.year, f.month, f.day);
  final diaRef = DateTime(ref.year, ref.month, ref.day);
  final diferenciaDias = diaRef.difference(diaFecha).inDays;

  final horaMinuto = '${_dosDigitos(f.hour)}:${_dosDigitos(f.minute)}';
  if (diferenciaDias == 0) {
    return 'Hoy $horaMinuto';
  }
  if (diferenciaDias == 1) {
    return 'Ayer $horaMinuto';
  }
  if (diferenciaDias >= 2 && diferenciaDias <= 7) {
    return 'Hace $diferenciaDias días';
  }
  return formatearFechaCorta(f);
}

/// Normaliza un texto para búsquedas sin distinguir mayúsculas ni tildes.
String normalizarTextoBusqueda(String texto) {
  final minusculas = texto.trim().toLowerCase();
  const reemplazos = <String, String>{
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
  };
  final buffer = StringBuffer();
  for (var i = 0; i < minusculas.length; i++) {
    final ch = minusculas[i];
    buffer.write(reemplazos[ch] ?? ch);
  }
  return buffer.toString();
}
