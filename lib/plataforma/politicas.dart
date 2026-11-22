import 'package:flutter/foundation.dart';

import '../domain/models/obra.dart';
import '../domain/models/usuario.dart';

/// Política de avisos del sistema
///
/// Decide cuándo corresponde disparar un aviso en la barra de estado sin
/// acoplar esa regla al widget ni al plugin nativo.
class PoliticaDeAvisos {
  const PoliticaDeAvisos();

  /// Solo se emite alerta proactiva cuando el semáforo pasa a amarillo
  /// (`demorada`) o rojo (`problemas`).
  bool debeAvisar(EstadoObra estado) =>
      estado == EstadoObra.demorada || estado == EstadoObra.problemas;
}

/// Define lo que la aplicación **debe** hacer según las reglas de negocio,
/// de las tiendas de aplicaciones y de cada perfil o entorno
class Politicas {
  const Politicas();

  /// Límite máximo en kilobytes por cada foto comprimida para respetar
  /// la cuota de Supabase Free Tier (< 200 KB por imagen).
  int get pesoMaximoFotoKb => 200;

  /// Ancho objetivo en píxeles para la compresión de fotografías de obra.
  int get resolucionAnchoFoto => 800;

  /// Alto objetivo en píxeles para la compresión de fotografías de obra.
  int get resolucionAltoFoto => 600;

  /// Calidad JPEG objetivo (70%) para la compresión con `flutter_image_compress`.
  int get calidadCompresionFoto => 70;

  /// Nombre de la tienda o canal de distribución según la plataforma, siguiendo
  /// el apunte de Capacidades y Políticas.
  String get nombreDeLaTienda {
    if (kIsWeb) return 'nuestro portal web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => 'la App Store',
      TargetPlatform.android => 'Google Play',
      _ => 'la tienda de tu sistema',
    };
  }

  /// Indica si se permite abrir enlaces externos de descarga/documentación en
  /// el navegador (en iOS se restringe según reglas de la App Store).
  bool get permiteEnlacesExternosEnNavegador {
    if (kIsWeb) return true;
    return defaultTargetPlatform != TargetPlatform.iOS;
  }

  /// Indica si el rol tiene permiso para crear nuevas obras y asignar responsables.
  bool puedeCrearObras(RolUsuario rol) => rol == RolUsuario.ingeniero;

  /// Indica si el rol puede modificar el semáforo, añadir tareas y cargar informes.
  bool puedeGestionarAvanceObra(RolUsuario rol) =>
      rol == RolUsuario.ingeniero || rol == RolUsuario.capataz;

  /// Indica si el rol puede programar y enviar notificaciones desde el panel.
  bool puedeAdministrarNotificaciones(RolUsuario rol) =>
      rol == RolUsuario.ingeniero;

  /// Indica si el rol visualiza todas las obras activas de la empresa.
  bool puedeVerTodasLasObras(RolUsuario rol) =>
      rol == RolUsuario.ingeniero || rol == RolUsuario.duenio;
}
