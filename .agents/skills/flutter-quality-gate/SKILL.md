---
name: flutter-quality-gate
description: Ejecuta la rutina obligatoria de calidad Flutter (dart format, flutter analyze y flutter test). Si algún chequeo falla, diagnostica la causa raíz exacta y recomienda correcciones concretas paso a paso antes de tocar código.
---
# Skill: Flutter Quality Gate (`analyze` + `test` + diagnóstico)

Usa esta skill cada vez que el usuario pida validar el proyecto, correr `flutter analyze` o `flutter test`, o antes de cerrar cualquier tarea o commit.

## 1. Ejecución de chequeos (en este orden estricto)

Prefiere las herramientas del servidor MCP **`dart`** (`dart mcp-server`) cuando estén disponibles; si no, ejecuta los comandos en terminal desde la raíz de `proyectoegi/`:

1. **Verificación de formato:**
   ```bash
   dart format --output=none --set-exit-if-changed .
   ```
2. **Análisis estático (`flutter analyze`):**
   ```bash
   flutter analyze
   ```
3. **Suite de pruebas (`flutter test`):**
   ```bash
   flutter test
   ```

## 2. Protocolo obligatorio cuando algo FALLA

**Nunca** te limites a pegar el log crudo ni a aplicar parches a ciegas (`// ignore:...` está prohibido salvo justificación documentada). Si falla cualquiera de los 3 pasos, entrega un **Reporte de Diagnóstico** estructurado antes de corregir:

### A. Si falla `dart format`
- Lista los archivos con diferencias de formato.
- Recomienda ejecutar `dart format .` (respetando `page_width: 80` de `analysis_options.yaml`).

### B. Si falla `flutter analyze`
Agrupa cada incidencia por severidad (`error` -> `warning` -> `info`) e indica para cada una:
1. **Archivo y línea:** `ruta/archivo.dart:Línea`.
2. **Regla o código de error:** por ejemplo `unawaited_futures`, `directives_ordering`, `prefer_const_constructors`, `deprecated_member_use`, `uri_does_not_exist`.
3. **Por qué ocurrió (causa raíz):** explica en lenguaje claro qué invariante de Dart, Flutter o `analysis_options.yaml` se rompió (por ejemplo, un `Future` disparado sin `await` ni `unawaited(...)`, un import fuera de orden entre `dart:` / `package:` / relativos, o una API deprecada — en cuyo caso consulta `context7` para la firma vigente).
4. **Corrección recomendada:** muestra el cambio exacto mínimo. Si aplica corrección automática, sugiere correr primero `dart fix --dry-run` antes de `dart fix --apply`.

### C. Si falla `flutter test`
Para cada test fallido (`FAILED`), analiza y explica:
1. **Test y archivo:** nombre completo del `test(...)` o `testWidgets(...)` y línea del `expect` que falló.
2. **Valor esperado vs. obtenido:** qué esperaba la aserción y qué devolvió el código real (o qué excepción se lanzó, ej. `MissingPluginException`, `StateError`, `AssertionError`).
3. **Diagnóstico de causa raíz:** distingue explícitamente si:
   - Se rompió una **regla de negocio o regresión real** en `lib/` (corregir `lib/`).
   - Se acopló accidentalmente un plugin nativo (Supabase, Firebase, Workmanager) sin inyectar un **Fake** de `test/fakes.dart` (corregir la inyección de dependencias).
   - Cambió intencionalmente la UI (por ejemplo, al eliminar `_TarjetaUsuariosPrueba` en `login_screen.dart`) y corresponde actualizar la prueba de widget.
4. **Plan de corrección recomendado:** indica exactamente qué archivo modificar y qué comando volver a correr para confirmar 100% en verde.

## 3. Criterio de aprobación
Solo marca el gate como **APROBADO** cuando:
- `dart format --output=none --set-exit-if-changed .` devuelve código `0`.
- `flutter analyze` devuelve `No issues found!`.
- `flutter test` devuelve `All tests passed!`.
