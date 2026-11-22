/// Abstracción del reloj del sistema
///
/// Permite inyectar un `RelojFijo` en las pruebas unitarias para verificar
/// cálculos de fechas, vencimientos y recordatorios sin depender de
/// `DateTime.now()`.
abstract class Reloj {
  DateTime ahora();
}

/// Implementación real que consulta la hora actual del sistema operativo.
class RelojDelSistema implements Reloj {
  const RelojDelSistema();

  @override
  DateTime ahora() => DateTime.now();
}
