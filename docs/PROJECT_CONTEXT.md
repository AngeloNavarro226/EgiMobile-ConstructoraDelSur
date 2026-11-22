# Contexto Compacto del Proyecto — Constructora Del Sur (`proyectoegi`)

> **Propósito:** Memoria técnica compacta del proyecto (equivalente a `/compact`). Todo agente en Google Antigravity debe usar este documento como base de verdad del estado actual y del roadmap hacia producción.
> **Última actualización:** 2026-11-20 · **Versión actual:** `2.3.0+1` (paquete `constructora_del_sur`, carpeta raíz `proyectoegi/`).

---

## 1. Resumen del Producto y Roles

Aplicación móvil Flutter para gestión de obras civiles e informes diarios de **Constructora Del Sur** (Mendoza, Argentina), diseñada para operar en terreno con conectividad intermitente (**Offline-First**).

- **Roles operativos (`RolUsuario`):**
  - `ingeniero`: ve todas las obras, crea obras nuevas (con mapa y foto de portada), cambia semáforos, agrega/marca tareas, administra alertas y exporta.
  - `capataz`: ve únicamente las obras donde es responsable (`obra.responsableId == usuario.id`), marca tareas y carga informes diarios con fotos y dictado por voz.
  - `duenio`: vista ejecutiva de todas las obras, métricas globales y exportación CSV/JSON.

---

## 2. Arquitectura Actual (v2.3.0 — 48 archivos en `lib/`, 4 en `test/`)

Arquitectura en **3 capas estrictas (MVVM + Repository)** con inyección de dependencias manual en `lib/main.dart`:

1. **Capa de Presentación (`lib/ui/` + `lib/main.dart`):**
   - `autenticacion/`: `AutenticacionViewModel`, `LoginScreen`.
   - `obras/`: `ObrasViewModel`, `InicioIngenieroScreen`, `InicioCapatazScreen`, `InicioDuenioScreen`, `AgregarObraScreen`, `CrearInformeScreen`, `DetalleObraSheet`.
   - `notificaciones/`: `NotificacionesViewModel`, `NotificacionesIngenieroScreen`.
   - `exportar/`: `ExportarViewModel`, `ExportarScreen`.
   - `perfil/`: `PerfilViewModel`, `PerfilScreen`.
   - `core/`: `ObraCard`, `Semaforo`, `AlertaSincronizacionBanner`, `SelectorUbicacionMapaDialog`, `VisorFotoInforme`.
2. **Capa de Dominio y Plataforma (`lib/domain/models/` y `lib/plataforma/`):**
   - Modelos inmutables (`final` + `copyWith`): `Obra`, `TareaObra`, `ReporteDiario`, `FotoComprimida`, `Usuario`, `NotificacionApp`, `Aviso`, `UbicacionObra`, `EventoDeApp`, `horarios.dart`.
   - `Capacidades` (`lib/plataforma/capacidades.dart`): qué puede hacer el dispositivo (`tieneCamara`, `tieneMicrofono`, `tieneGps`, `soportaTrabajoEnSegundoPlano`).
   - `Politicas` y `PoliticaDeAvisos` (`lib/plataforma/politicas.dart`): reglas de negocio (`800x600`, calidad `70%`, tope `200 KB` por foto, permisos por rol, alerta proactiva solo en Amarillo/Rojo).
3. **Capa de Datos (`lib/data/repositories/` y `lib/data/services/`):**
   - Repositorios (fuente de verdad + caché en memoria con `forzarRecarga`): `AutenticacionRepository`, `ObrasRepository`, `NotificacionesRepository`, `PreferenciasRepository`.
   - Servicios: `BaseDatosLocalService` (SQLite `constructora_del_sur_v3.db`), `PreferenciasService` (`SharedPreferencesAsync` con `allowList`), `MultimediaService` (`Stream` + `Isolate.run` + `Workmanager`), `SincronizacionService` (`connectivity_plus` + `Workmanager` `callbackDispatcher`), `NotificacionesSistemaService` (`ServicioDeNotificaciones` + `MethodChannel`), `VozATextoService` (`speech_to_text`), `MapaService` (Google Maps + OSM + geocodificación inversa con timeout 3 s), `DescargaArchivoService`, `BusDeEventos`, `Reloj`, `plataforma_io_real.dart` / `plataforma_io_stub.dart`.

---

## 3. Esquema SQLite Local Actual (`constructora_del_sur_v3.db`)

5 tablas relacionales creadas en `lib/data/services/base_datos_local_service.dart`:
1. `usuarios` (`id`, `username`, `nombre`, `telefono`, `contrasenia`, `rol`).
2. `obras` (`id`, `nombre`, `estado_semaforo`, `fecha_ultimo_reporte`, `responsable_id`, `responsable_nombre`, `tareas` JSON, `materiales` JSON, `ubicacion` JSON, `observaciones`, `con_foto`, `imagen` asset/base64, `finalizada`).
3. `reportes_diarios` (`id`, `obra_id`, `obra_nombre`, `fecha_creacion_local`, `tarea_seleccionada`, `tarea_completada`, `materiales_usados` JSON, `observaciones`, `url_fotos` JSON, `estado_semaforo`, `autor_nombre`, `sync_status` [`pending`|`synced`], `fecha_sincronizacion`, `obra_finalizada`).
4. `notificaciones` (`id`, `titulo`, `mensaje`, `destinatario`, `fecha_hora`, `es_alerta_semaforo`).
5. `configuracion_recordatorio` (`id`, `activo`, `hora`, `minuto`).

> **Nota técnica importante en `android/`:** En `proyectoegi/android/app/src/main/kotlin/` conviven `com/example/proyectoegi/MainActivity.kt` y `com/example/constructora_del_sur/{MainActivity.kt, Notificador.kt, RecordatorioReceiver.kt}`. Al configurar Firebase (`google-services.json`), verificar primero el `applicationId` exacto en `android/app/build.gradle.kt` y unificar si hay duplicación de `MainActivity.kt`.

---

## 4. Estado de Calidad y Red de Seguridad Actual

- `analysis_options.yaml` exige 5 reglas extra sobre `flutter_lints`: `always_declare_return_types`, `directives_ordering`, `prefer_const_constructors`, `prefer_single_quotes`, `unawaited_futures` (`page_width: 80`).
- **Tests existentes (4 archivos, 9 pruebas):**
  - `test/fakes.dart`: `RelojFijo`, `NotificacionesFalsas`, `CapacidadesFalsas`, `PoliticasFalsas`.
  - `test/plataforma_test.dart`: capacidades/políticas Android, iOS y Linux.
  - `test/caracterizacion_y_dominio_test.dart`: avance de `Obra`, autenticación, filtro `Finalizadas`, `PoliticaDeAvisos`, horarios y geocodificación.
  - `test/widget_test.dart`: flujo inicial de `ConstructoraApp` y validación de `LoginScreen`.

---

## 5. Roadmap Activo (Próximas 4 Fases con Agentes)

| Fase | Objetivo | Estado | Skill asignada |
| :--- | :--- | :--- | :--- |
| **Fase 1** | **Supabase como BD principal + Offline-First:** Crear tablas PostgreSQL + RLS + Storage en Supabase, integrar `supabase_flutter` en `lib/data/services/` manteniendo SQLite como caché local y cola `pending` | Pendiente | `supabase-offline-first` |
| **Fase 2** | **Sincronización real:** Reemplazar el marcado local simulado en `SincronizacionService` y `ObrasRepository` por subida real de reportes/fotos pendientes a Supabase + descarga incremental (*pull* & *push*) + `Workmanager` | Pendiente | `sync-engine-implementation` |
| **Fase 3** | **Notificaciones Push reales (Firebase FCM):** Integrar `firebase_core` + `firebase_messaging`, registrar tokens FCM por usuario en Supabase, enviar push reales en cambios de semáforo/alertas (reemplazando la emulación local) manteniendo el contrato `ServicioDeNotificaciones` | Pendiente | `firebase-push-notifications` |
| **Fase 4** | **Limpieza de UI de versión de prueba:** Quitar `_TarjetaUsuariosPrueba` y `_autocompletarCredencialPrueba` de `lib/ui/autenticacion/widgets/login_screen.dart`, quitar botones/textos de simulación de internet o semillas demo visibles, y actualizar `test/widget_test.dart` | Pendiente | `ui-production-cleanup` |

---

## 6. Decisiones y Restricciones Innegociables

1. **Nunca romper el patrón Repository:** Ningún archivo de `lib/ui/` puede importar `supabase_flutter`, `firebase_messaging` ni `sqflite`.
2. **Fotos `< 200 KB`:** Mantener la compresión en `800x600`, calidad `70%` y `Isolate.run` antes de subir a Supabase Storage para respetar la cuota del plan gratuito.
3. **Secretos fuera de Git:** Nunca hardcodear `SUPABASE_ANON_KEY`, `SUPABASE_URL` ni claves privadas en código fuente versionado; usar `--dart-define` o `.env` ignorado en `.gitignore`.
4. **Verificación continua:** Ninguna fase se marca como completada sin pasar `flutter-quality-gate` (0 errores/warnings en `flutter analyze` y 100% de tests en verde).
