import 'dart:math';

/// Contrato inyectable para generar identificadores únicos sin colisión
/// entre dispositivos trabajando en modo Offline-First.
abstract interface class GeneradorIds {
  String generar();
}

/// Genera identificadores UUID v4 compatibles con el tipo `uuid` de PostgreSQL
/// y Supabase sin dependencias externas.
class GeneradorUuidV4 implements GeneradorIds {
  GeneradorUuidV4([Random? aleatorio])
      : _aleatorio = aleatorio ?? Random.secure();

  final Random _aleatorio;

  @override
  String generar() {
    final bytes = List<int>.generate(16, (_) => _aleatorio.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
