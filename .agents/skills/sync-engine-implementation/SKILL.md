---
name: sync-engine-implementation
description: Implementa la sincronización real bidireccional (push de cola pending y pull remoto) entre SQLite y Supabase usando connectivity_plus, Workmanager, AppLifecycleListener y manejo de reintentos/conflictos.
---
# Skill: Motor de Sincronización Real Offline-First

Usa esta skill para reemplazar la sincronización simulada actual (`marcarReportesComoSincronizados` en `obras_repository.dart` y `ejecutarTareaSincronizacion` en `sincronizacion_service.dart`) por un **motor de sincronización real contra Supabase**.

## 1. Principios del motor Offline-First
1. **Outbox local confiable:** Todo cambio creado en terreno (reporte diario, cambio de semáforo, actualización de tareas, nueva obra, foto comprimida) se persiste primero en SQLite con `sync_status = pending` y marca de tiempo obtenida de `Reloj` (`_reloj.ahora()`).
2. **Idempotencia obligatoria:** Usa los `id` generados en el cliente (`obra.id`, `reporte.id`) con `upsert` en Supabase para que reintentar una sincronización interrumpida nunca duplique filas.
3. **Subida de fotos antes del registro:**
   - Para cada `FotoComprimida` adjunta en un reporte `pending`, sube primero los bytes a Supabase Storage (`fotos-obras/<obraId>/<reporteId>_<i>.jpg`).
   - Reemplaza la referencia local por la URL remota antes de hacer `upsert` del `reporte_diario` en PostgreSQL.
4. **Orden de ejecución del ciclo `sincronizarTodo()`:**
   - **Paso 1 (Push):** Leer obras/reportes locales con `sync_status = pending` -> subir fotos a Storage -> `upsert` en Supabase -> solo si Supabase confirma éxito, marcar `sync_status = synced` y `fecha_sincronizacion = _reloj.ahora()` en SQLite.
   - **Paso 2 (Pull):** Consultar cambios recientes desde Supabase (`updated_at > ultima_sync`) y actualizar SQLite local sin sobrescribir registros locales que todavía estén en `pending` (estrategia *local-pending wins* / *last-write-wins* por `updated_at`).
   - **Paso 3 (Notificación UI):** Emitir `SincronizacionCompletada(cantidad)` en `BusDeEventos` y mostrar `AlertaSincronizacionBanner`.

## 2. Integración con Segundo Plano y Eventos del Sistema
- **`Workmanager` (`sincronizacion_service.dart`):** Mantén `@pragma('vm:entry-point')` en `callbackDispatcher()` y conecta `ejecutarTareaSincronizacion(...)` con el sincronizador real (respetando `NetworkType.connected` y devolviendo `false` ante fallas transitorias para que Android aplique backoff/reintento).
- **`connectivity_plus`:** Mantén `.map(hayAlgunaRed).distinct()` para disparar sincronización al recuperar señal sin tormentas de eventos.
- **`AppLifecycleListener` (`lib/main.dart`):** En `onResume`, dispara sincronización silenciosa si hay conectividad.
- **Manejo de errores:** Si falla un reporte puntual por error de red, mantenerlo en `pending` y continuar con el resto sin crashear la UI.

## 3. Verificación
- Escribe tests unitarios en `test/caracterizacion_y_dominio_test.dart` simulando: (a) falla de red (queda `pending`), (b) recuperación de red (pasa a `synced`), (c) reintento idempotente sin duplicados.
- Ejecuta `flutter-quality-gate` y actualiza `@docs/PROJECT_CONTEXT.md`.
