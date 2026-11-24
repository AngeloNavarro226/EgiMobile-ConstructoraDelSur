# Contexto Compacto del Proyecto — Constructora Del Sur (`proyectoegi`)

> **Propósito:** Memoria técnica compacta del proyecto (equivalente a `/compact`). Todo agente en Google Antigravity debe usar este documento como base de verdad del estado actual y del roadmap hacia producción.
> **Última actualización:** 2026-11-23 · **Versión actual:** `2.3.0+1` (paquete `constructora_del_sur`, carpeta raíz `proyectoegi/`).

---

## 1. Resumen del Producto y Roles

Aplicación móvil Flutter para gestión de obras civiles e informes diarios de **Constructora Del Sur** (Mendoza, Argentina), diseñada para operar en terreno con conectividad intermitente (**Offline-First**).

- **Roles operativos (`Rol` + `RolUsuario`, persistidos en `roles`, relación `1:N` con `usuarios`):**
  - `rol_ingeniero` (`ingeniero`): ve todas las obras, crea obras nuevas (con mapa y foto de portada), cambia semáforos, agrega/marca tareas, administra alertas y exporta.
  - `rol_capataz` (`capataz`): ve únicamente las obras donde es responsable (`obra.responsableId == usuario.id`), marca tareas y carga informes diarios con fotos y dictado por voz.
  - `rol_duenio` (`duenio`): vista ejecutiva de todas las obras, métricas globales y exportación CSV/JSON.

---

## 2. Arquitectura Actual (v2.3.0 — 59 archivos en `lib/`, 4 en `test/`)

Arquitectura en **3 capas estrictas (MVVM + Repository)** con inyección de dependencias manual en `lib/main.dart`:

1. **Capa de Presentación (`lib/ui/` + `lib/main.dart`):**
   - Base común: `ViewModelBase` (`lib/ui/core/view_model_base.dart`) con `EstadoOperacion` y protección `notificarSiActivo()` contra `dispose()`. Todos los ViewModels notifican explícitamente en `cargando`, `exito` y `error`.
   - `autenticacion/`: `AutenticacionViewModel` (incluye `restaurarSesion()` offline), `LoginScreen`.
   - `obras/`: `ObrasViewModel` (carga perezosa de reportes por obra, operaciones granulares, reprogramación automática del recordatorio tras cargar/sincronizar, `Reloj` + `GeneradorIds`), `InicioIngenieroScreen`, `InicioCapatazScreen`, `InicioDuenioScreen`, `AgregarObraScreen`, `CrearInformeScreen`, `DetalleObraSheet`.
   - `notificaciones/`: `NotificacionesViewModel` (refresco automático vía `BusDeEventos` y stream `toques`), `NotificacionesIngenieroScreen` (solo configuración del recordatorio diario por ingeniero + historial de alertas de semáforo; envío manual de prueba eliminado).
   - `exportar/`: `ExportarViewModel` (generación CSV/JSON asíncrona en `Isolate.run`), `ExportarScreen`.
   - `perfil/`: `PerfilViewModel` (`inicializarPreferencias()` + edición con `telefono`), `PerfilScreen`.
   - `core/`: `ImagenLocalORemota` (archivo local → URL remota → Base64 → asset), `ObraCard`, `Semaforo`, `AlertaSincronizacionBanner`, `SelectorUbicacionMapaDialog`, `VisorFotoInforme`.
2. **Capa de Dominio y Plataforma (`lib/domain/models/` y `lib/plataforma/`):**
   - Modelos inmutables (`final` + `copyWith` + metadatos `updatedAt` UTC y `syncStatus`): `EstadoSincronizacion`, `Rol`, `RolUsuario`, `Usuario` (con `telefono`), `Obra` (con `ingenieroId`, `tareaActualId`, `imagenUrl` y `deletedAt`), `TareaObra`, `ReporteDiario`, `FotoComprimida` (con `urlRemota` y `estadoSubida`), `NotificacionApp` (con `emisorId`), `ProgramacionRecordatorio` (por `ingenieroId`), `Aviso`, `UbicacionObra`, `EventoDeApp`, `PlantillaObra`, `horarios.dart`.
   - `Capacidades` (`lib/plataforma/capacidades.dart`) y `Politicas` / `PoliticaDeAvisos` (`lib/plataforma/politicas.dart` — incluye `resolverDestinatariosAlertaSemaforo` y `resolverRecordatorioMasTemprano`).
3. **Capa de Datos (`lib/data/repositories/` y `lib/data/services/`):**
   - Repositorios (fuente de verdad + caché en memoria + `limpiarCache()`): `AutenticacionRepository` (registra/rota/limpia `fcm_token`), `ObrasRepository`, `NotificacionesRepository` (alertas FCM por rol emisor + recordatorio por ingeniero sincronizado + reprogramación automática del equipo), `PreferenciasRepository` (persiste `usuario_sesion_id` y copia local del recordatorio en `SharedPreferencesAsync` con `allowList`).
   - Servicios: `BaseDatosLocalService` (SQLite `constructora_del_sur_v4.db`, `version: 5` con `onUpgrade`, 3FN + `PRAGMA foreign_keys = ON`), `ConfiguracionSupabase` (`--dart-define` / `.env.json` ignorado en Git), `FuenteDatosRemota` / `SupabaseRemoteService` / `FuenteDatosRemotaOffline`, `ServicioAutenticacionRemota` / `SupabaseAuthService` / `ServicioAutenticacionRemotaOffline`, `MotorSincronizacion` (Push → Pull con lock, subida de fotos previa al `upsert`, reintentos en `cola_sincronizacion`, sincronización de `configuracion_recordatorio` y *local-pending wins*), `FirebaseNotificacionesService` (`firebase_core` + `firebase_messaging` + `NotificacionesSistemaService`), `GeneradorIds` / `GeneradorUuidV4`, `PreferenciasService`, `MultimediaService`, `SincronizacionService` (`connectivity_plus` + `Workmanager`), `NotificacionesSistemaService`, `VozATextoService`, `MapaService`, `DescargaArchivoService`, `BusDeEventos`, `Reloj`, `plataforma_io_real.dart` / `plataforma_io_stub.dart`.

---

## 3. Esquema SQLite Local Actual (`constructora_del_sur_v4.db`, v5 con `onUpgrade`, 3FN + FKs)

13 tablas relacionales normalizadas en `lib/data/services/base_datos_local_service.dart` con `PRAGMA foreign_keys = ON` e índices sobre todas las FKs y `sync_status`:

1. `roles` (`id` PK, `codigo` UNIQUE, `nombre`) — catálogo con los 3 roles (`rol_ingeniero`, `rol_capataz`, `rol_duenio`).
2. `usuarios` (`id` PK, `username` UNIQUE, `rol_id` FK → `roles.id` [relación 1:N], `nombre`, `contrasenia`, `telefono`, `fcm_token`, `updated_at`, `sync_status`).
3. `obras` (`id` PK, `nombre`, `estado_semaforo`, `fecha_ultimo_reporte`, `responsable_id` FK → `usuarios.id`, `ingeniero_id` nullable FK → `usuarios.id` `ON DELETE SET NULL`, `tarea_actual_id` nullable FK → `tareas_obra.id` `ON DELETE SET NULL`, `ubicacion_latitud`, `ubicacion_longitud`, `ubicacion_direccion`, `observaciones`, `con_foto`, `imagen`, `imagen_url`, `finalizada`, `updated_at`, `sync_status`, `deleted_at`).
4. `tareas_obra` (`id` PK, `obra_id` FK → `obras.id` `ON DELETE CASCADE`, `nombre`, `completada`, `orden`, `updated_at`, `sync_status`).
5. `obra_materiales` (`id` PK AUTOINCREMENT, `obra_id` FK → `obras.id` `ON DELETE CASCADE`, `nombre`).
6. `reportes_diarios` (`id` PK, `obra_id` FK → `obras.id` `ON DELETE CASCADE`, `autor_id` FK → `usuarios.id` `ON DELETE RESTRICT`, `fecha_creacion_local`, `fecha_sincronizacion`, `tarea_seleccionada`, `tarea_completada`, `observaciones`, `estado_semaforo`, `sync_status` [`pending`|`synced`|`error`], `obra_finalizada`, `updated_at`).
7. `reporte_materiales` (`id` PK AUTOINCREMENT, `reporte_id` FK → `reportes_diarios.id` `ON DELETE CASCADE`, `nombre`).
8. `reporte_fotos` (`id` PK AUTOINCREMENT, `reporte_id` FK → `reportes_diarios.id` `ON DELETE CASCADE`, `ruta_local`, `origen`, `ancho_px`, `alto_px`, `calidad_pct`, `peso_kb`, `bytes_base64`, `url_remota`, `estado_subida`).
9. `notificaciones` (`id` PK, `obra_id` nullable FK → `obras.id` `ON DELETE SET NULL`, `emisor_id` nullable FK → `usuarios.id` `ON DELETE SET NULL`, `titulo`, `mensaje`, `destinatario`, `fecha_hora`, `es_alerta_semaforo`, `updated_at`, `sync_status`).
10. `configuracion_recordatorio` (`ingeniero_id` PK FK → `usuarios.id` `ON DELETE CASCADE`, `activo`, `hora`, `minuto`, `updated_at`, `sync_status`) — 1 fila por ingeniero, sincronizable con Supabase; la alarma efectiva del dispositivo se copia también en `SharedPreferences` (Dart + Android nativo) y `RecordatorioReceiver.kt` solo la dispara si `reportes_diarios` tiene filas `pending`.
11. `estado_sincronizacion` (`id` PK, `ultima_sync_utc`) — cursor UTC para *Pull* incremental.
12. `cola_sincronizacion` (`id` PK, `entidad`, `entidad_id`, `operacion`, `reintentos`, `ultimo_error`, `creado_en`) — trazabilidad de reintentos Push.
13. `catalogo_plantillas` (`id` PK, `usuario_id` FK → `usuarios.id` `ON DELETE CASCADE`, `tipo` [`tarea`|`material`], `nombre`, `updated_at`, `sync_status`, `deleted_at`) — catálogo individual por ingeniero de tareas y materiales frecuentes.

### Esquema Remoto en Supabase (`EgiMobile`, `cgczsdbidvqykigxbgxg`, Postgres 17)

- **11 tablas en `public`** con `RLS` habilitado, índices FK/`updated_at`, triggers `actualizar_updated_at()` + `on_auth_user_created` + resolución de conflictos LWW (`a_trg_obras_resolver_conflicto_lww` y `a_trg_tareas_obra_resolver_conflicto_lww` sobre `client_updated_at` con merge monotónico de `finalizada`, `con_foto` y `fecha_ultimo_reporte`), y helpers RLS en esquema `private`: `roles`, `usuarios` (`fcm_token`), `obras` (`responsable_id`, `ingeniero_id`, `tarea_actual_id`, `client_updated_at`), `tareas_obra` (`client_updated_at`), `obra_materiales`, `reportes_diarios`, `reporte_materiales`, `reporte_fotos` (`peso_kb <= 200`, `storage_path`), `notificaciones` (`emisor_id`, `push_enviado`), `catalogo_plantillas`, `configuracion_recordatorio` (`ingeniero_id` PK, RLS: ingeniero edita la propia, capataz lee la de los ingenieros de sus obras, dueño lee todas).
- **Edge Function FCM (`supabase/functions/enviar-push-fcm/index.ts`):** desplegada (`ACTIVE`), resuelve destinatarios en servidor (Capataz → Ingeniero a cargo + Dueño; Ingeniero → Capataz a cargo + Dueño), garantiza idempotencia vía `push_enviado` y despacha con FCM HTTP v1 API usando `FIREBASE_SERVICE_ACCOUNT_JSON`.
- **Storage:** bucket privado `fotos-obras` (`file_size_limit = 204800`, JPEG/PNG/WebP) con políticas RLS por rol.
- **Realtime:** publicación `supabase_realtime` habilitada para `obras`, `tareas_obra`, `reportes_diarios`, `reporte_fotos`, `notificaciones`, `catalogo_plantillas` y `configuracion_recordatorio`.
- **Android (`applicationId`):** `com.constructoradelsur.egimobile` en `android/app/build.gradle.kts` (Firebase proyecto `egimobile-fc985`, `google-services.json` local ignorado en Git); `BaseDatosLocalService` usa `WAL` + `busy_timeout = 5000`; `RecordatorioAlarmas.kt` + `RecordatorioReceiver.kt` + `RecordatorioBootReceiver.kt` usan `setAndAllowWhileIdle` (reprogramando el día siguiente) y leen SQLite WAL antes de notificar.

---

## 4. Estado de Calidad y Red de Seguridad Actual

- `analysis_options.yaml` exige 5 reglas extra sobre `flutter_lints`: `always_declare_return_types`, `directives_ordering`, `prefer_const_constructors`, `prefer_single_quotes`, `unawaited_futures` (`page_width: 80`).
- **Tests existentes (4 archivos, 25 pruebas en verde):**
  - `test/fakes.dart`: `RelojFijo`, `GeneradorIdsSecuencial`, `FakeFuenteDatosRemota` (con modo `resolverConflictosLww`), `FakeServicioAutenticacionRemota`, `FakeServicioPushFcm`, `BaseDatosLocalConError`, `NotificacionesFalsas`, `CapacidadesFalsas`, `PoliticasFalsas`.
  - `test/plataforma_test.dart`: capacidades/políticas Android, iOS y Linux.
  - `test/caracterizacion_y_dominio_test.dart`: dominio de `Obra`, autenticación + sesión offline + Supabase Auth + ciclo de vida `fcm_token`, mapeo SQLite↔Postgres (`client_updated_at`), roles 1:N + integridad FK/3FN, `MotorSincronizacion` Push → Pull + fotos + *local-pending wins* + resolución de conflictos offline LWW, Realtime, catálogo de plantillas + tarea actual, destinatarios FCM por rol emisor (Capataz vs Ingeniero), recordatorio por ingeniero + horario más temprano en Capataz + `SharedPreferences`, auditoría de ViewModels, horarios y `Workmanager`.
  - `test/widget_test.dart`: `LoginScreen`, `PerfilScreen`, `DetalleObraEnriquecidoSheet`, `NotificacionesIngenieroScreen` (sin envío manual + switch de recordatorio diario), `AgregarObraScreen` (sin overflow en 360px) y `CrearInformeScreen` (guardado como Capataz).

---

## 5. Roadmap Activo (Próximas Fases con Agentes)

| Fase | Objetivo | Estado | Skill asignada |
| :--- | :--- | :--- | :--- |
| **Fase 0** | **Preparación Offline-First y Escalabilidad Local:** Esquema normalizado (`onUpgrade`), `telefono`, `roles 1:N`, UUID v4, `FuenteDatosRemota`, `MotorSincronizacion`, `ViewModelBase` | **Completado** | `refactoring_safe` |
| **Fase 1** | **Supabase como BD principal + Offline-First:** Tablas PostgreSQL + RLS + bucket `fotos-obras` + Auth + `SupabaseRemoteService` en `EgiMobile` (`cgczsdbidvqykigxbgxg`) | **Completado** | `supabase-offline-first` |
| **Fase 2** | **Sincronización real en producción:** `Workmanager` + `connectivity_plus` + `AppLifecycleListener` + Realtime + LWW por `client_updated_at` | **Completado** | `sync-engine-implementation` |
| **Fase 3** | **Notificaciones Push reales (Firebase FCM) + Recordatorio por Ingeniero:** FCM en producción (`egimobile-fc985`, `enviar-push-fcm` activo, `FIREBASE_SERVICE_ACCOUNT_JSON` configurado), destinatarios por rol emisor, `configuracion_recordatorio` por `ingeniero_id` con `setAndAllowWhileIdle` + lectura SQLite WAL | **Completado** | `firebase-push-notifications` |
| **Fase 4** | **Limpieza de UI de versión de prueba:** Quitar `_TarjetaUsuariosPrueba` y `_autocompletarCredencialPrueba` de `login_screen.dart`, quitar botones de simulación y semillas demo en producción, y actualizar `test/widget_test.dart` | Pendiente | `ui-production-cleanup` |

---

## 6. Decisiones y Restricciones Innegociables

1. **Nunca romper el patrón Repository:** Ningún archivo de `lib/ui/` puede importar `supabase_flutter`, `firebase_messaging` ni `sqflite`.
2. **Fotos `< 200 KB`:** Mantener la compresión en `800x600`, calidad `70%` y `Isolate.run` antes de subir a Supabase Storage para respetar la cuota del plan gratuito.
3. **Secretos fuera de Git:** Nunca hardcodear `SUPABASE_ANON_KEY`, `SUPABASE_URL` ni claves privadas en código fuente versionado; usar `--dart-define` o `.env` ignorado en `.gitignore`.
4. **Verificación continua:** Ninguna fase se marca como completada sin pasar `flutter-quality-gate` (0 errores/warnings en `flutter analyze` y 100% de tests en verde).
