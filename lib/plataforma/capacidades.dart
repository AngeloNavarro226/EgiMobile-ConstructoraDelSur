import 'package:flutter/foundation.dart';

/// Define lo que el dispositivo o la plataforma **puede** hacer.
///
/// Separa las capacidades de hardware y del sistema operativo para evitar
/// el uso directo de `Platform.isAndroid` o `Platform.isIOS` en las vistas.
class Capacidades {
  const Capacidades();

  /// Indica si el dispositivo cuenta con cámara disponible para tomar fotos
  /// en los informes diarios de obra.
  bool get tieneCamara {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Indica si el dispositivo o navegador soporta reconocimiento de voz por
  /// micrófono (`speech_to_text` en Android, iOS y Web Speech API en navegadores).
  bool get tieneMicrofono {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  /// Indica si la plataforma soporta posicionamiento GPS y mapas interactivos.
  bool get tieneGps {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Indica si el sistema operativo exige mostrar un diálogo nativo de permisos
  /// en tiempo de ejecución antes de acceder a cámara, micrófono o ubicación.
  bool get requiereDialogoDePermiso {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Indica si la plataforma permite ejecutar tareas en segundo plano con el
  /// sistema operativo cuando la app se cierra (`WorkManager` / `BGTaskScheduler`).
  bool get soportaTrabajoEnSegundoPlano {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
