# AGENTS.md — Constructora Del Sur (`proyectoegi`)

Eres el agente de ingeniería de software encargado de continuar el desarrollo de **Constructora Del Sur** (Flutter/Dart) bajo **programación agéntica**, orquestado desde **Google Antigravity** y coeditado por el equipo humano en **Android Studio**.

## 1. Contexto vivo obligatorio (estilo `/compact`)

Antes de planificar, leer código o editar archivos, utiliza siempre el contexto consolidado del proyecto inyectado a continuación:

@[Contexto del Proyecto](docs/PROJECT_CONTEXT.md)

> **Regla de mantenimiento del contexto:** Al finalizar cualquier hito, migración de esquema, cambio de arquitectura o cierre de sesión, ejecuta la skill `update-project-context` para mantener actualizado `@docs/PROJECT_CONTEXT.md` y evitar pérdida de contexto entre sesiones.

## 2. Coordinación Antigravity + Android Studio

- **Orquestación en Antigravity:** Planifica en fases pequeñas, usa las skills de `.agents/skills/` y valida cada cambio antes de darlo por terminado.
- **Coedición con Android Studio:**
  - Nunca edites ni borres archivos de configuración local del IDE dentro de `.idea/` salvo petición explícita.
  - Mantén `pubspec.yaml`, `analysis_options.yaml` y la estructura de `android/` compatibles con el runner de Android Studio y Gradle Kotlin DSL (`android/app/build.gradle.kt`).
  - Antes de finalizar una tarea, deja el árbol formateado con `dart format .` para evitar conflictos de formato con el auto-format de Android Studio.

## 3. Uso obligatorio de servidores MCP (`.agents/mcp_config.json`)

Este proyecto cuenta con **4 servidores MCP**. Úsalos de forma disciplinada según la tarea:

1. **`dart` (`dart mcp-server`)**:
   - Úsalo como herramienta principal para analizar código Dart/Flutter, ejecutar `flutter analyze`, correr `flutter test`, resolver dependencias de `pubspec.yaml` y verificar símbolos/errores sin adivinar.
2. **`supabase` (`https://mcp.supabase.com/mcp`)**:
   - Úsalo para diseñar tablas PostgreSQL, generar y aplicar migraciones SQL, configurar políticas RLS (*Row Level Security*), buckets de Storage para fotos de obra y verificar logs/esquemas reales en la nube.
   - Nunca inventes columnas o políticas RLS sin verificar primero el esquema actual vía Supabase MCP.
3. **`firebase` (`firebase-tools mcp`)**:
   - Úsalo para inspeccionar el proyecto Firebase, registrar/verificar la app Android (`google-services.json` y `applicationId`), configurar Firebase Cloud Messaging (FCM) y validar el envío de notificaciones push reales.
4. **`context7` (`@upstash/context7-mcp`)**:
   - Úsalo **siempre** antes de escribir código que integre APIs recientes de `supabase_flutter`, `firebase_core`, `firebase_messaging`, `flutter_local_notifications`, `sqflite` o `workmanager`, para consultar la documentación actualizada de la versión exacta declarada en `pubspec.yaml` y evitar APIs deprecadas.

## 4. Skills disponibles en `.agents/skills/`

Invoca automáticamente la skill correspondiente cuando el usuario solicite cualquiera de estas tareas:

- **`flutter-quality-gate`**: Ejecuta `dart format --output=none --set-exit-if-changed .`, `flutter analyze` y `flutter test` (vía terminal o `dart` MCP). Si algo falla, explica la causa raíz y recomienda correcciones exactas sin ocultar errores.
- **`supabase-offline-first`**: Guía la migración de SQLite-only a arquitectura **Offline-First con Supabase como BD principal** (PostgreSQL + Auth + Storage + SQLite como caché/cola local).
- **`firebase-push-notifications`**: Guía el reemplazo de notificaciones emuladas/locales por **notificaciones push reales con Firebase Cloud Messaging (FCM)** integradas con `ServicioDeNotificaciones`.
- **`sync-engine-implementation`**: Implementa la sincronización bidireccional y la cola `pending -> synced` real entre SQLite y Supabase con `Workmanager` y `connectivity_plus`.
- **`ui-production-cleanup`**: Elimina componentes y datos exclusivos de la versión de prueba/demo (como `_TarjetaUsuariosPrueba` en `login_screen.dart` y botones de simulación) manteniendo los tests en verde.
- **`update-project-context`**: Compacta y actualiza `@docs/PROJECT_CONTEXT.md` tras completar avances importantes.

## 5. Flujo obligatorio por tarea

1. **Leer contexto y código real:** Revisa `@docs/PROJECT_CONTEXT.md` y los archivos afectados antes de proponer cambios.
2. **Consultar documentación fresca:** Si agregas o actualizas un paquete (`supabase_flutter`, `firebase_messaging`, etc.), consulta primero `context7`.
3. **Respetar Clean Code y Refactoring:** Aplica las reglas de `@.agents/rules/architecture_layers.md`, `@.agents/rules/clean_code_dart.md` y `@.agents/rules/refactoring_safe.md`. Nunca mezcles un refactoring estructural con una nueva funcionalidad en el mismo paso.
4. **Gate de calidad obligatorio:** Antes de cerrar cualquier cambio, ejecuta la skill `flutter-quality-gate`. No des una tarea por completada si `flutter analyze` o `flutter test` fallan.
