import 'package:flutter/foundation.dart';

import '../domain/models/notificacion_app.dart';
import '../domain/models/obra.dart';
import '../domain/models/usuario.dart';

/// Política de avisos del sistema.
///
/// Decide cuándo corresponde disparar una alerta de semáforo, a qué roles y
/// usuarios debe notificarse según quién hizo el cambio, y qué horario efectivo
/// de recordatorio diario aplica al equipo de un capataz.
class PoliticaDeAvisos {
  const PoliticaDeAvisos();

  /// Solo se emite alerta proactiva cuando el semáforo pasa a amarillo
  /// (`demorada`) o rojo (`problemas`).
  bool debeAvisar(EstadoObra estado) =>
      estado == EstadoObra.demorada || estado == EstadoObra.problemas;

  /// Resuelve los destinatarios exactos de la notificación push de cambio de
  /// semáforo según quién realizó la acción:
  /// - Si el cambio lo hace el **Capataz**: informa al **Ingeniero a cargo**
  ///   (`obra.ingenieroId`) y al **Dueño**.
  /// - Si el cambio lo hace el **Ingeniero**: informa al **Capataz a cargo**
  ///   (`obra.responsableId`) y al **Dueño**.
  ///
  /// Nunca incluye al propio [emisor] como destinatario.
  List<Usuario> resolverDestinatariosAlertaSemaforo({
    required Obra obra,
    required Usuario? emisor,
    required List<Usuario> usuarios,
  }) {
    final porId = <String, Usuario>{for (final u in usuarios) u.id: u};
    final resultado = <String, Usuario>{};

    void agregarSiExiste(String? id) {
      if (id == null || id.isEmpty) return;
      final usuario = porId[id];
      if (usuario != null) {
        resultado[usuario.id] = usuario;
      }
    }

    // El Dueño siempre recibe alertas de semáforo Amarillo o Rojo.
    for (final usuario in usuarios) {
      if (usuario.rol.tipo == RolUsuario.duenio) {
        resultado[usuario.id] = usuario;
      }
    }

    final rolEmisor = emisor?.rol.tipo;
    if (rolEmisor == RolUsuario.capataz) {
      if (obra.ingenieroId != null && porId.containsKey(obra.ingenieroId)) {
        agregarSiExiste(obra.ingenieroId);
      } else {
        for (final usuario in usuarios) {
          if (usuario.rol.tipo == RolUsuario.ingeniero) {
            resultado[usuario.id] = usuario;
          }
        }
      }
    } else if (rolEmisor == RolUsuario.ingeniero) {
      agregarSiExiste(obra.responsableId);
    } else {
      if (obra.ingenieroId != null && porId.containsKey(obra.ingenieroId)) {
        agregarSiExiste(obra.ingenieroId);
      } else {
        for (final usuario in usuarios) {
          if (usuario.rol.tipo == RolUsuario.ingeniero) {
            resultado[usuario.id] = usuario;
          }
        }
      }
    }

    if (emisor != null) {
      resultado.remove(emisor.id);
    }

    return resultado.values.toList();
  }

  /// Determina la configuración efectiva del recordatorio diario para un
  /// capataz a partir de los ingenieros a cargo de sus obras activas
  /// (`obra.ingenieroId`).
  ///
  /// Si un capataz tiene obras de 2 o más ingenieros con horarios distintos,
  /// toma únicamente el **horario más temprano** entre las configuraciones
  /// activas. Devuelve `null` si ninguna configuración aplicable está activa.
  ProgramacionRecordatorio? resolverRecordatorioMasTemprano({
    required List<Obra> obrasDelCapataz,
    required Map<String, ProgramacionRecordatorio> configuracionesPorIngeniero,
  }) {
    final ingenierosIds = <String>{
      for (final obra in obrasDelCapataz)
        if (!obra.finalizada &&
            obra.deletedAt == null &&
            obra.ingenieroId != null &&
            obra.ingenieroId!.isNotEmpty)
          obra.ingenieroId!,
    };

    ProgramacionRecordatorio? masTemprano;
    for (final ingenieroId in ingenierosIds) {
      final config = configuracionesPorIngeniero[ingenieroId];
      if (config == null || !config.activo) continue;
      if (masTemprano == null ||
          config.minutosDesdeMedianoche < masTemprano.minutosDesdeMedianoche) {
        masTemprano = config;
      }
    }
    return masTemprano;
  }
}

/// Define lo que la aplicación **debe** hacer según las reglas de negocio,
/// de las tiendas de aplicaciones y de cada perfil o entorno.
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

  /// Indica si el rol puede programar el recordatorio diario de su equipo.
  bool puedeAdministrarNotificaciones(RolUsuario rol) =>
      rol == RolUsuario.ingeniero;

  /// Indica si el rol visualiza todas las obras activas de la empresa.
  bool puedeVerTodasLasObras(RolUsuario rol) =>
      rol == RolUsuario.ingeniero || rol == RolUsuario.duenio;

  /// Indica si el [usuario] puede elegir manualmente la tarea actual en curso
  /// de [obra]: únicamente el capataz responsable o el ingeniero a cargo.
  bool puedeElegirTareaActual(Usuario? usuario, Obra obra) {
    if (usuario == null || obra.finalizada || obra.tareasPendientes.isEmpty) {
      return false;
    }
    if (usuario.rol.tipo == RolUsuario.capataz) {
      return obra.responsableId == usuario.id;
    }
    if (usuario.rol.tipo == RolUsuario.ingeniero) {
      return obra.ingenieroId == usuario.id ||
          obra.ingenieroId == null ||
          obra.responsableId == usuario.id;
    }
    return false;
  }
}
