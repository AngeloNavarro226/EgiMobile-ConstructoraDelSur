---
name: supabase-offline-first
description: Guía la migración de Constructora Del Sur desde SQLite-only hacia una arquitectura Offline-First con Supabase como base de datos principal (PostgreSQL, Auth, Storage y RLS) manteniendo SQLite como caché y cola local.
---
# Skill: Migración Offline-First con Supabase como BD Principal

Usa esta skill cuando el objetivo sea conectar **Supabase** como base de datos principal del proyecto manteniendo la operación **Offline-First** sobre SQLite (`BaseDatosLocalService`).

## 1. Preparación obligatoria con MCPs
1. **Context7 (`context7`):** Consulta la documentación vigente de `supabase_flutter` (inicialización, autenticación, consultas `.from()`, `upsert`, `Storage` y manejo de `PostgrestException`).
2. **Supabase MCP (`supabase`):** Inspecciona el proyecto remoto antes de crear tablas o escribir SQL.

## 2. Diseño de esquema PostgreSQL y Storage en Supabase
Replica y evoluciona las 5 entidades actuales de `lib/data/services/base_datos_local_service.dart` usando migraciones SQL controladas vía `supabase` MCP:
- `usuarios` (o `perfiles` enlazado a `auth.users(id)`): `id uuid PK`, `username`, `nombre`, `telefono`, `rol` (`ingeniero` | `capataz` | `duenio`), `fcm_token text`, `updated_at timestamptz`.
- `obras`: `id text/uuid PK`, `nombre`, `estado_semaforo`, `fecha_ultimo_reporte`, `responsable_id`, `responsable_nombre`, `tareas jsonb`, `materiales jsonb`, `ubicacion jsonb`, `observaciones`, `con_foto boolean`, `imagen_url text`, `finalizada boolean`, `updated_at timestamptz`.
- `reportes_diarios`: `id text/uuid PK`, `obra_id` FK -> `obras(id)`, `obra_nombre`, `fecha_creacion_local`, `tarea_seleccionada`, `tarea_completada`, `materiales_usados jsonb`, `observaciones`, `url_fotos jsonb`, `estado_semaforo`, `autor_nombre`, `obra_finalizada`, `created_at timestamptz`.
- `notificaciones`: `id`, `titulo`, `mensaje`, `destinatario`, `fecha_hora`, `es_alerta_semaforo`, `obra_id`.
- **Supabase Storage:** Crea un bucket `fotos-obras` para portadas y fotos de reportes diarios (ya comprimidas a `800x600`, `70%`, `< 200 KB` en `Isolate.run`), guardando en la BD la URL/path de Storage en lugar de inflar PostgreSQL con Base64.
- **Seguridad (RLS obligatorio):** Habilita `ROW LEVEL SECURITY` en todas las tablas con políticas acordes a `RolUsuario` (`ingeniero` y `duenio` leen todas las obras; `capataz` lee/reporta en sus obras asignadas).

## 3. Arquitectura en Flutter (Sin romper capas)
1. **Configuración segura:** Inyecta `SUPABASE_URL` y `SUPABASE_ANON_KEY` mediante `--dart-define` (nunca hardcodeados).
2. **Nuevo servicio remoto:** Crea `lib/data/services/supabase_remote_service.dart` detrás de una interfaz abstracta (ej. `FuenteDatosRemota`) para poder inyectar un `FakeFuenteDatosRemota` en `test/fakes.dart`.
3. **Patrón Offline-First en Repositories (`ObrasRepository`, `AutenticacionRepository`):**
   - **Lectura:** Devuelve primero caché/SQLite si no hay red; si hay red, trae datos de Supabase, actualiza SQLite y refresca la caché.
   - **Escritura:** Guarda inmediatamente en SQLite con `sync_status = pending` (garantizando respuesta instantánea en obra sin señal) y delega el envío remoto al motor de sincronización (`sync-engine-implementation`).
4. **Autenticación real:** Migra `AutenticacionRepository` para autenticar contra Supabase Auth (o tabla `usuarios` autenticada) conservando sesión offline segura.

## 4. Verificación
- Añade pruebas unitarias con `FakeFuenteDatosRemota` verificando comportamiento con red y sin red.
- Ejecuta `flutter-quality-gate` y actualiza `@docs/PROJECT_CONTEXT.md` con `update-project-context`.
