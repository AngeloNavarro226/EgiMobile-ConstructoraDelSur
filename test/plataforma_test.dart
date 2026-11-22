import 'package:constructora_del_sur/plataforma/capacidades.dart';
import 'package:constructora_del_sur/plataforma/politicas.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hace que [defaultTargetPlatform] devuelva [plataforma] durante la prueba
/// y la restaura al terminar, aunque la prueba falle.
void simularPlataforma(TargetPlatform plataforma) {
  debugDefaultTargetPlatformOverride = plataforma;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

void main() {
  test(
      'en Android el dispositivo tiene cámara, micrófono, GPS y trabajo en segundo plano',
      () {
    simularPlataforma(TargetPlatform.android);
    const cap = Capacidades();
    expect(cap.tieneCamara, isTrue);
    expect(cap.tieneMicrofono, isTrue);
    expect(cap.tieneGps, isTrue);
    expect(cap.requiereDialogoDePermiso, isTrue);
    expect(cap.soportaTrabajoEnSegundoPlano, isTrue);
    expect(const Politicas().nombreDeLaTienda, 'Google Play');
  });

  test(
      'en iOS la tienda es la App Store y no se permiten enlaces externos en navegador',
      () {
    simularPlataforma(TargetPlatform.iOS);
    const pol = Politicas();
    expect(pol.nombreDeLaTienda, 'la App Store');
    expect(pol.permiteEnlacesExternosEnNavegador, isFalse);
  });

  test('en Linux no se asume cámara móvil ni trabajo en segundo plano', () {
    simularPlataforma(TargetPlatform.linux);
    const cap = Capacidades();
    expect(cap.tieneCamara, isFalse);
    expect(cap.soportaTrabajoEnSegundoPlano, isFalse);
  });
}
