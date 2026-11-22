import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Servicio de transcripción de voz a texto usando el motor nativo del
/// dispositivo o navegador (`speech_to_text`).
///
/// Reutiliza el estado de inicialización y configura `SpeechListenOptions`
/// con `localeId`, `listenFor`, `pauseFor`, `partialResults: true` y
/// `ListenMode.dictation` para evitar el uso de parámetros deprecados en `listen`.
class VozATextoService {
  final SpeechToText _speech = SpeechToText();
  bool _inicializado = false;
  String? _localeEspanolSeleccionado;

  /// Indica si el micrófono se encuentra escuchando activamente.
  bool get estaEscuchando => _speech.isListening;

  /// Inicia la escucha real del micrófono y envía las palabras reconocidas en
  /// tiempo real a [onResultado].
  Future<bool> iniciarEscucha({
    required void Function(String textoReconocido) onResultado,
    required void Function(String mensajeError) onError,
    required void Function() onFinalizado,
  }) async {
    try {
      if (!_inicializado) {
        _inicializado = await _speech.initialize(
          onStatus: (estado) {
            if (estado == 'done' || estado == 'notListening') {
              onFinalizado();
            }
          },
          onError: (error) {
            onError(_traducirErrorMicrofono(error.errorMsg));
            onFinalizado();
          },
        );

        if (_inicializado && !kIsWeb) {
          try {
            final locales = await _speech.locales();
            for (final loc in locales) {
              if (loc.localeId.toLowerCase().startsWith('es')) {
                _localeEspanolSeleccionado = loc.localeId;
                break;
              }
            }
          } catch (_) {}
        }
      }

      if (!_inicializado) {
        onError(
          kIsWeb
              ? 'El navegador no pudo iniciar el reconocimiento de voz. '
                  'En Microsoft Edge el servicio en la nube de Web Speech API suele estar bloqueado; '
                  'probá ejecutando en Google Chrome (`flutter run -d chrome`) y aceptá el permiso de micrófono.'
              : 'El dispositivo no pudo iniciar el reconocimiento de voz. '
                  'Verificá que `AndroidManifest.xml` tenga `RECORD_AUDIO` y el `<queries>` para `RecognitionService`, '
                  'y que en el emulador esté activado "Virtual microphone uses host audio input" en Extended Controls (... > Microphone).',
        );
        return false;
      }

      await _speech.listen(
        onResult: (resultado) {
          if (resultado.recognizedWords.isNotEmpty) {
            onResultado(resultado.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: _localeEspanolSeleccionado,
          listenFor: const Duration(seconds: 40),
          pauseFor: const Duration(seconds: 6),
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
      );
      return true;
    } catch (e) {
      onError(
        'No se pudo iniciar la captura del micrófono ($e). '
        'Verificá los permisos de audio en el navegador o en AndroidManifest.xml.',
      );
      return false;
    }
  }

  /// Detiene la captura de voz del micrófono.
  Future<void> detener() async {
    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (_) {}
  }

  String _traducirErrorMicrofono(String codigo) {
    final limpio = codigo.toLowerCase();
    if (limpio.contains('not-allowed') || limpio.contains('permission')) {
      return 'Permiso de micrófono denegado ($codigo). Habilitalo en el candado de la barra de direcciones o en Ajustes de Android.';
    }
    if (limpio.contains('network')) {
      return 'Error de red en Web Speech API ($codigo). Microsoft Edge bloquea el servicio de voz de Google; usá Google Chrome (`flutter run -d chrome`).';
    }
    if (limpio.contains('no-speech') || limpio.contains('speech_timeout')) {
      return 'No se detectó audio en el micrófono ($codigo). Si usás el emulador Android, activá "Virtual microphone uses host audio input" en los 3 puntos (...) > Microphone.';
    }
    return 'Aviso del motor de voz ($codigo). Verificá la entrada de micrófono.';
  }
}
