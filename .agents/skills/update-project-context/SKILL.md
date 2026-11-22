---
name: update-project-context
description: Actualiza y compacta docs/PROJECT_CONTEXT.md (equivalente a /compact) tras completar un hito, cambiar el esquema de BD o modificar la arquitectura para preservar memoria limpia entre sesiones en Antigravity.
---
# Skill: Actualizar Contexto Compacto del Proyecto (`/compact`)

Usa esta skill al terminar cualquier hito relevante (migración de Supabase, integración de FCM, motor de sincronización, limpieza de UI) o cuando el usuario pida compactar/guardar el estado actual del proyecto.

## Instrucciones
1. Inspecciona el estado real actual del repositorio (`pubspec.yaml`, estructura de `lib/` y `test/`, tablas en Supabase/SQLite y resultado reciente de `flutter analyze` / `flutter test`).
2. Edita **`docs/PROJECT_CONTEXT.md`** manteniendo un formato denso, escaneable y **por debajo de 12 KB** (para no acercarse al límite de 24 KB de inclusión `@[...]` de `AGENTS.md`):
   - Actualiza la **fecha**, la **versión** y el conteo/resumen de módulos si cambió.
   - Actualiza la tabla de **Roadmap Activo** marcando como `Completado` o `En progreso` cada fase con los archivos reales creados/modificados.
   - Documenta cualquier decisión técnica nueva, esquema SQL/RLS aplicado en Supabase, nombre de buckets de Storage o configuración de Firebase FCM.
   - Elimina notas de deuda técnica ya resueltas para que el archivo no crezca con historial obsoleto.
3. Confirma al usuario en 3–4 líneas qué secciones de `docs/PROJECT_CONTEXT.md` se actualizaron.
