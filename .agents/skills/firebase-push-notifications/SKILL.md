---
name: firebase-push-notifications
description: Reemplaza las notificaciones emuladas locales por notificaciones push reales con Firebase Cloud Messaging (FCM), conservando la interfaz ServicioDeNotificaciones y los tests con NotificacionesFalsas.
---
# Skill: Notificaciones Push Reales con Firebase (FCM)

Usa esta skill para migrar las alertas y notificaciones desde la emulación local actual (`MethodChannel` en `MainActivity.kt`) hacia **notificaciones push reales con Firebase Cloud Messaging (FCM)**.

## 1. Preparación obligatoria con MCPs
1. **Context7 (`context7`):** Consulta la documentación vigente de `firebase_core`, `firebase_messaging` y la integración de notificaciones en primer plano en Android (`flutter_local_notifications` o canal nativo actual).
2. **Firebase MCP (`firebase`):** Verifica el proyecto Firebase activo, la configuración de la app Android y el archivo `google-services.json`.

## 2. Verificación crítica de `android/` antes de tocar código
Antes de registrar la app en Firebase:
- Revisa el `applicationId` real en `android/app/build.gradle.kt` y verifica por qué existen carpetas `com/example/proyectoegi/` y `com/example/constructora_del_sur/` en `android/app/src/main/kotlin/`.
- Unifica el paquete si corresponde para que `google-services.json` coincida exactamente con `applicationId`.
- Agrega el plugin `com.google.gms.google-services` en Gradle Kotlin DSL (`android/settings.gradle.kt` y `android/app/build.gradle.kt`) y `firebase_core` + `firebase_messaging` en `pubspec.yaml`.

## 3. Integración respetando la Arquitectura en Capas
1. **Preservar el contrato:** Mantén intacta la abstracción `ServicioDeNotificaciones` (`lib/data/services/notificaciones_sistema_service.dart`) para que `NotificacionesRepository` y `NotificacionesFalsas` (`test/fakes.dart`) sigan funcionando sin depender de Firebase en tests.
2. **Implementación FCM (`lib/data/services/firebase_notificaciones_service.dart`):**
   - Inicializa `Firebase.initializeApp()` en `lib/main.dart` (protegido para entornos sin configuración/tests).
   - Solicita permiso en contexto (`FirebaseMessaging.instance.requestPermission()`), nunca de forma invasiva en el primer frame sin contexto.
   - Obtiene el token FCM (`getToken()`) y escucha `onTokenRefresh` para guardarlo en la tabla `usuarios` de Supabase (`fcm_token`) asociado al usuario autenticado.
   - Registra un handler top-level con `@pragma('vm:entry-point')` para `FirebaseMessaging.onBackgroundMessage(...)`.
   - Maneja mensajes en primer plano (`FirebaseMessaging.onMessage`) mostrándolos en la barra superior Android, y clics en notificaciones (`onMessageOpenedApp` y `getInitialMessage`) emitiendo el destino en el `Stream<String> get toques`.
3. **Disparo real del servidor:** Configura el envío de push (vía Edge Function de Supabase o Cloud Function de Firebase disparada por `firebase` MCP) cuando se inserta una alerta crítica (semáforo Amarillo/Rojo evaluado por `PoliticaDeAvisos`) o una notificación manual del Ingeniero.

## 4. Verificación
- Verifica que los tests unitarios de `NotificacionesRepository` sigan pasando usando `NotificacionesFalsas`.
- Prueba una notificación push real en dispositivo físico/emulador Android (en primer plano y con la app minimizada) vía `firebase` MCP o Firebase Console.
- Ejecuta `flutter-quality-gate` y actualiza `@docs/PROJECT_CONTEXT.md`.
