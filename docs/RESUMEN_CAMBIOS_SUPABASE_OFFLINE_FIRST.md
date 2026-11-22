# Resumen de Cambios — Normalización 3FN, Offline-First, Supabase y Realtime

> **Fecha:** 2026-11-22 · **Proyecto:** Constructora Del Sur (`proyectoegi2`) · **Rama:** `feat/offline-first-bd-normalizada`
> **Proyecto Supabase:** `EgiMobile` (`cgczsdbidvqykigxbgxg`, PostgreSQL 17, `us-west-2`)

---

## 1. Normalización de la Base de Datos Local (SQLite v2 — 3FN + FKs)

Archivo principal: `lib/data/services/base_datos_local_service.dart`

- Se migró el esquema plano de 5 tablas con columnas JSON (`constructora_del_sur_v3.db`) a **12 tablas normalizadas en 3FN** con `PRAGMA foreign_keys = ON` e índices en todas las FKs y `sync_status`:
  1. `roles` (`id` PK, `codigo` UNIQUE, `nombre`) — catálogo con los 3 roles (`rol_ingeniero`, `rol_capataz`, `rol_duenio`).
  2. `usuarios` (`id` PK, `username` UNIQUE, `rol_id` FK 1:N → `roles.id`, `nombre`, `contrasenia`, `telefono`, `updated_at`, `sync_status`).
  3. `obras` (`id` PK, `nombre`, `estado_semaforo`, `fecha_ultimo_reporte`, `responsable_id` FK → `usuarios.id`, `ubicacion_latitud`, `ubicacion_longitud`, `ubicacion_direccion`, `observaciones`, `con_foto`, `imagen`, `imagen_url`, `finalizada`, `updated_at`, `sync_status`, `deleted_at`).
  4. `tareas_obra` (`id` PK, `obra_id` FK `ON DELETE CASCADE`, `nombre`, `completada`, `orden`, `updated_at`, `sync_status`).
  5. `obra_materiales` (`id` PK AUTOINCREMENT, `obra_id` FK `ON DELETE CASCADE`, `nombre`).
  6. `reportes_diarios` (`id` PK, `obra_id` FK `ON DELETE CASCADE`, `autor_id` FK `ON DELETE RESTRICT`, `fecha_creacion_local`, `fecha_sincronizacion`, `tarea_seleccionada`, `tarea_completada`, `observaciones`, `estado_semaforo`, `sync_status`, `obra_finalizada`, `updated_at`).
  7. `reporte_materiales` (`id` PK AUTOINCREMENT, `reporte_id` FK `ON DELETE CASCADE`, `nombre`).
  8. `reporte_fotos` (`id` PK AUTOINCREMENT, `reporte_id` FK `ON DELETE CASCADE`, `ruta_local`, `origen`, `ancho_px`, `alto_px`, `calidad_pct`, `peso_kb`, `bytes_base64`, `url_remota`, `estado_subida`).
  9. `notificaciones` (`id` PK, `obra_id` nullable FK `ON DELETE SET NULL`, `titulo`, `mensaje`, `destinatario`, `fecha_hora`, `es_alerta_semaforo`, `updated_at`, `sync_status`).
  10. `configuracion_recordatorio` (`id` PK, `activo`, `hora`, `minuto`) — solo local.
  11. `estado_sincronizacion` (`id` PK, `ultima_sync_utc`) — cursor UTC local para *Pull* incremental.
  12. `cola_sincronizacion` (`id` PK, `entidad`, `entidad_id`, `operacion`, `reintentos`, `ultimo_error`, `creado_en`) — trazabilidad local de reintentos Push.
- **Migraciones incrementales y seguridad SQLite:**
  - Implementado `onUpgrade` (`v1 -> v2`) sin pérdida de datos locales `pending`.
  - Se reemplazó `ConflictAlgorithm.replace` en tablas padre por transacciones `UPDATE` + `INSERT` condicional para evitar disparos accidentales de `ON DELETE CASCADE`.
  - BD separada para modo nube (`constructora_del_sur_supabase.db`, sin semillas demo) vs. modo local (`constructora_del_sur_v4.db`).
  - Reapertura automática en `inicializar()` si `_db!.isOpen == false`, serialización de aperturas concurrentes y `instanciaUnica: false` (`singleInstance: false`) para el isolate de `Workmanager`.
- **Operaciones granulares y consultas filtradas:** `actualizarSemaforoObraCruda`, `insertarTareaCruda`, `actualizarEstadoTareaCruda`, `obtenerObrasCrudas` (paginado/filtrado) y `obtenerReportesPorObraCrudos` (filtro `WHERE obra_id = ?` en SQL).

---

## 2. Modelos de Dominio y Escalabilidad

- **Nuevos modelos:**
  - `lib/domain/models/rol.dart`: `class Rol` (entidad escalable) + `enum RolUsuario`.
  - `lib/domain/models/estado_sincronizacion.dart`: enum `EstadoSincronizacion` (`pending`, `synced`, `error`).
- **Modelos actualizados:** `usuario.dart` (columna `telefono` preservada, `Rol`, `updatedAt`, `syncStatus`), `obra.dart` (`imagenUrl`, `deletedAt`, helpers de origen), `tarea_obra.dart`, `reporte_diario.dart` (`autorId`, `urlRemota`, `estadoSubida`), `notificacion_app.dart` (`obraId` FK opcional), `evento_de_app.dart` (`SesionIniciada`, `SesionCerrada`, `ObrasActualizadas`, `AlertaSemaforoEmitida`, `ErrorSincronizacion`).
- **IDs sin colisión:** `lib/data/services/generador_ids.dart` (`GeneradorIds` + `GeneradorUuidV4` RFC-4122, reemplazando `DateTime.now().microsecondsSinceEpoch`).
- **Fotos fuera de Base64 en SQLite:** `plataforma_io_real.dart`, `plataforma_io_stub.dart` y `multimedia_service.dart` persisten los JPEG comprimidos (`800x600`, `70%`, `< 200 KB`) en disco local en plataformas nativas.
- **Visor multi-origen sin parpadeos:** `lib/ui/core/imagen_local_o_remota.dart` (usado por `obra_card.dart` y `visor_foto_informe.dart`) con cascada memoria → archivo local → URL remota → asset, `gaplessPlayback: true` y caché de rutas locales.
- **Exportación asíncrona y destinatarios dinámicos:** `ExportarViewModel` genera CSV/JSON en `Isolate.run` y se actualiza por `BusDeEventos`; `NotificacionesRepository` resuelve destinatarios gerenciales dinámicamente desde BD.

---

## 3. Auditoría y Mejora de ViewModels (`notifyListeners()`)

- **Nueva clase base:** `lib/ui/core/view_model_base.dart` (`ViewModelBase`, `EstadoOperacion`, `notificarSiActivo()` seguro frente a `dispose()`).
- **Los 5 ViewModels refactorizados:**
  - `ObrasViewModel`: notificaciones explícitas en `cargando`, `exito` y `error` (sin `finally` ciego), `mensajeError`, carga perezosa `cargarReportesDeObra()`, lock + re-encolado de sincronización (`_syncPendienteAlTerminar`), suscripción Realtime con *debounce* de `1200 ms`, respaldo periódico de `45 s` solo en primer plano y limpieza en `SesionCerrada`.
  - `AutenticacionViewModel`: `try/catch` en `iniciarSesion()` y `restaurarSesion()` offline para nunca dejar `estaCargando` bloqueado.
  - `NotificacionesViewModel`: `EstadoOperacion` + `mensajeError` y refresco automático vía `BusDeEventos` (`AlertaSemaforoEmitida`).
  - `ExportarViewModel`: generación asíncrona en `Isolate.run` con estado y manejo de errores explícito.
  - `PerfilViewModel`: `inicializarPreferencias()` notificando el tema oscuro al arrancar y edición de perfil (con `telefono` y contraseña opcional) con manejo de errores.
- **Pantallas de inicio:** estados visuales de `cargando` y `error` (con botón Reintentar) + `RefreshIndicator` (pull-to-refresh) en `inicio_ingeniero_screen.dart`, `inicio_capataz_screen.dart` e `inicio_duenio_screen.dart`.

---

## 4. Base de Datos y Servicios en Supabase (`EgiMobile`)

### Migraciones aplicadas en PostgreSQL 17
1. `create_normalized_schema`: 9 tablas en `public` (`roles`, `usuarios`, `obras`, `tareas_obra`, `obra_materiales`, `reportes_diarios`, `reporte_materiales`, `reporte_fotos`, `notificaciones`), FKs, constraints (`peso_kb <= 200`, `UNIQUE` compuestos para idempotencia), triggers `actualizar_updated_at()` en UTC, índices y catálogo de 3 roles.
2. `enable_rls_and_policies` + `harden_rls_helper_functions`: RLS habilitado en las 9 tablas con funciones helper `SECURITY DEFINER` aisladas en el esquema privado `private` (`private.usuario_actual_id`, `private.rol_codigo_actual`, `private.puede_ver_obra`, `private.puede_gestionar_obra`).
3. `create_storage_bucket_fotos_obras`: bucket privado `fotos-obras` (`file_size_limit = 204800`, JPEG/PNG/WebP) y políticas RLS en `storage.objects`.
4. `seed_initial_users_and_auth_trigger`: trigger `on_auth_user_created` + 3 usuarios confirmados (1 por rol) en `auth.users`, `auth.identities` y `public.usuarios` (`ingeniero@constructoradelsur.com`, `capataz@constructoradelsur.com`, `dueno@constructoradelsur.com`).
5. `enable_realtime_publication`: publicación `supabase_realtime` habilitada sobre `obras`, `tareas_obra`, `reportes_diarios`, `reporte_fotos` y `notificaciones`.

### Integración Flutter (`supabase_flutter: ^2.18.3`)
- `lib/data/services/configuracion_supabase.dart`: carga `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` por `--dart-define` / `--dart-define-from-file=.env.json` (`.env.json` ignorado en `.gitignore`; `.env.example` versionado).
- `lib/data/services/fuente_datos_remota.dart` y `lib/data/services/supabase_remote_service.dart`: contrato remoto + implementación Supabase (subida de portadas `portadas/<obraId>.jpg` y fotos de informes `<obraId>/<reporteId>_<i>.jpg`, URLs firmadas reutilizadas 7 días, `UPDATE` previo a `INSERT` en `obras` para compatibilidad con RLS de capataz, reloj único de PostgreSQL en `updated_at`, *Pull* incremental y canal Realtime `postgres_changes`).
- `lib/data/services/servicio_autenticacion_remota.dart`: contrato + `SupabaseAuthService` + caché de perfil sin contraseña en SQLite para restaurar sesión offline.
- `lib/data/services/motor_sincronizacion.dart`: motor Push → Pull con exclusión mutua, subida previa de portadas y fotos de reportes, trazabilidad en `cola_sincronizacion`, margen de 60 s contra desfase de relojes y estrategia *local-pending wins*.
- `lib/data/services/sincronizacion_service.dart`: `connectivity_plus` + `Workmanager` `callbackDispatcher` conectado a `SupabaseRemoteService` con `instanciaUnica: false`.
- `lib/main.dart`: inicialización condicional de `Supabase.initialize(...)`, carga post-login, y ciclo de vida `AppLifecycleListener` (`onResume` / `onHide` / `onPause`) pausando/reanudando Realtime y el temporizador de respaldo.

---

## 5. Incidencias Reales Detectadas en Emulador/Dispositivos y Resueltas

| Incidencia observada | Causa raíz | Solución aplicada |
| :--- | :--- | :--- |
| `SQLITE_CONSTRAINT_UNIQUE: usuarios.username` al loguear con Supabase | Mezcla de BD local demo (`u_ingeniero`) con UUID real de Supabase | Archivo SQLite separado (`constructora_del_sur_supabase.db`) + actualización por `username` con `ON UPDATE CASCADE` |
| `DatabaseException(database_closed 1)` | `Workmanager` cerraba la instancia `singleInstance: true` compartida de `sqflite` | `instanciaUnica: false` en `Workmanager` + auto-reapertura `_db!.isOpen` y serialización en `inicializar()` |
| Semáforo cambiado por Capataz no subía a Supabase | En PostgreSQL, `UPSERT` exige permiso RLS de `INSERT` (`obras_insert_ingeniero`) aun al actualizar | `UPDATE ... WHERE id = ?` antes de `INSERT` en `SupabaseRemoteService.upsertObra` |
| Foto de portada de obra no cargaba en otro celular | El motor subía `reporte_fotos` pero no `obras.imagen` | Subida de `portadas/<obraId>.jpg` en Push de obras y firma de `imagen_url` en Pull |
| Había que pulsar "Sincronizar" en ambos teléfonos | Sync descartada si había otra en curso + sin Realtime | Flag `_syncPendienteAlTerminar` + Supabase Realtime (`postgres_changes`) + sync silenciosa tras cada mutación |
| Foto de la card parpadeaba y recargaba 3 veces en cada sync | `createSignedUrl` generaba token nuevo en cada Pull invalidando `ImageCache` + debounce corto | Conservar `imagen_url` vigente (< 6 días), `gaplessPlayback: true` + caché local en `ImagenLocalORemota`, debounce `1200 ms` |

---

## 6. Estado de Verificación (`flutter-quality-gate`)

- `dart format --output=none --set-exit-if-changed lib test`: **0 cambios pendientes**.
- `flutter analyze` en toda la capa de dominio, datos, ViewModels y tests: **`No issues found!`**.
- `flutter test`: **`15/15 All tests passed!`** (pruebas unitarias con `FakeFuenteDatosRemota`, `FakeServicioAutenticacionRemota`, `BaseDatosLocalConError`, `RelojFijo`, `GeneradorIdsSecuencial`, `NotificacionesFalsas` y prueba de widgets).
- Validación manual en dos dispositivos reales/emulador: login Supabase, restauración offline sin señal, creación de obras con portada, cambios de semáforo, carga de informes con fotos y actualización automática vía Realtime sin parpadeo.
