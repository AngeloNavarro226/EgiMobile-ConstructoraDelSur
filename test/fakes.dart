import 'dart:async';

import 'package:constructora_del_sur/data/services/notificaciones_sistema_service.dart';
import 'package:constructora_del_sur/data/services/reloj.dart';
import 'package:constructora_del_sur/domain/models/aviso.dart';
import 'package:constructora_del_sur/plataforma/capacidades.dart';
import 'package:constructora_del_sur/plataforma/politicas.dart';

/// Reloj determinístico para pruebas unitarias (`SegundoPlano_Apunte.pdf`).
class RelojFijo implements Reloj {
  RelojFijo(this.instante);

  final DateTime instante;

  @override
  DateTime ahora() => instante;
}

/// Implementación Fake de [ServicioDeNotificaciones] para pruebas sin canales
/// nativos (`Notificaciones_Apunte.pdf`).
class NotificacionesFalsas implements ServicioDeNotificaciones {
  final List<Aviso> mostradas = [];
  final List<int> canceladas = [];
  final StreamController<String> _toques = StreamController<String>.broadcast();
  final List<(int, int)> recordatoriosProgramados = [];
  bool recordatorioCancelado = false;
  bool permisoConcedido = true;

  @override
  Future<bool> pedirPermiso() async => permisoConcedido;

  @override
  Future<void> mostrar(Aviso aviso) async {
    mostradas.add(aviso);
  }

  @override
  Future<void> cancelar(int id) async {
    canceladas.add(id);
  }

  @override
  Future<void> programarRecordatorioDiario({
    required int hora,
    required int minuto,
    required String titulo,
    required String mensaje,
  }) async {
    recordatoriosProgramados.add((hora, minuto));
  }

  @override
  Future<void> cancelarRecordatorioDiario() async {
    recordatorioCancelado = true;
  }

  @override
  Stream<String> get toques => _toques.stream;

  void simularToque(String destino) => _toques.add(destino);

  Future<void> dispose() async {
    await _toques.close();
  }
}

/// Cumple el mismo contrato que [Capacidades], pero cada respuesta la decide
/// la prueba sin depender del hardware real del dispositivo
/// (`CapacidadesPoliticas_Apunte.pdf`).
class CapacidadesFalsas implements Capacidades {
  const CapacidadesFalsas({
    this.tieneCamara = true,
    this.tieneMicrofono = true,
    this.tieneGps = true,
    this.requiereDialogoDePermiso = false,
    this.soportaTrabajoEnSegundoPlano = true,
  });

  @override
  final bool tieneCamara;

  @override
  final bool tieneMicrofono;

  @override
  final bool tieneGps;

  @override
  final bool requiereDialogoDePermiso;

  @override
  final bool soportaTrabajoEnSegundoPlano;
}

/// Cumple el mismo contrato que [Politicas] para pruebas unitarias y de widgets.
class PoliticasFalsas extends Politicas {
  const PoliticasFalsas({
    this.pesoMaximoFotoKb = 200,
    this.resolucionAnchoFoto = 800,
    this.resolucionAltoFoto = 600,
    this.calidadCompresionFoto = 70,
    this.nombreDeLaTienda = 'la tienda de prueba',
    this.permiteEnlacesExternosEnNavegador = true,
  });

  @override
  final int pesoMaximoFotoKb;

  @override
  final int resolucionAnchoFoto;

  @override
  final int resolucionAltoFoto;

  @override
  final int calidadCompresionFoto;

  @override
  final String nombreDeLaTienda;

  @override
  final bool permiteEnlacesExternosEnNavegador;
}
