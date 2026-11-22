---
trigger: model_decision
description: "Aplica estas reglas obligatorias siempre que refactorices código existente, reestructures capas, renombres símbolos o prepares el código antes de integrar Supabase o Firebase."
---
# Cláusulas de Refactoring Seguro (`Refactoring_Apunte.pdf`)

## 1. Regla de los Dos Sombreros (Nunca mezclar)
- **Refactorizar** es cambiar la estructura interna del código **sin cambiar su comportamiento observable**.
- **Nunca mezcles** en un mismo paso/commit un refactoring estructural con una nueva funcionalidad (ej. primero extrae la interfaz del datasource y verifica que todos los tests pasen; recién en el paso siguiente implementa Supabase).
- No reescribas módulos enteros desde cero: transforma el código existente en pasos pequeños y verificables.

## 2. Red de Seguridad Obligatoria (Pruebas de Caracterización)
- **Sin pruebas no hay refactoring:** Antes de tocar cualquier clase crítica (`ObrasRepository`, `SincronizacionService`, `NotificacionesRepository`, `LoginScreen`), ejecuta `flutter test` y verifica que todo esté en verde.
- Si el archivo que vas a refactorizar no tiene cobertura suficiente, **escribe primero pruebas de caracterización** usando los fakes de `test/fakes.dart` (`RelojFijo`, `NotificacionesFalsas`, `CapacidadesFalsas`, `PoliticasFalsas`) que fijen el comportamiento observable externo (nunca detalles internos privados).

## 3. Catálogo de Olores (Code Smells) a Corregir
Cuando detectes alguno de estos olores al preparar el código, aplica su cura específica:
- **Nombre misterioso** -> Renombrar con refactor semántico (nunca buscar/reemplazar ciego).
- **Datos expuestos** -> Hacer campos privados (`_campo`) y exponer getters de solo lectura (`List.unmodifiable(...)`).
- **Argumento bandera (`bool`)** -> Convertir a parámetro con nombre (`{bool forzarRecarga = false}`).
- **Número mágico** -> Extraer constante con nombre.
- **Código duplicado** -> Extraer método o getter.
- **Obsesión por primitivos** -> Reemplazar `int`/`String` mágicos por `enum` o clase de dominio (`EstadoSincronizacion`, `EstadoObra`).
- **Condicionales anidados** -> Aplicar cláusulas de guarda con retorno temprano.
- **Lógica fuera de lugar** -> Mover a `domain/`, `Politicas` o `ViewModel`.
- **Comentarios desodorante / Código muerto** -> Renombrar y eliminar comentarios redundantes o bloques comentados.

## 4. Ciclo de Pasos Chicos y Reversión
1. Verifica `flutter test` en verde antes de empezar.
2. Aplica **un único cambio pequeño** (renombrar, extraer interfaz, mover clase sin modificarla a la vez).
3. Ejecuta `flutter analyze` y `flutter test` inmediatamente.
4. Si algo se rompe y no es obvio en segundos, revierte el paso (`git restore .`) e inténtalo con un cambio más pequeño.
5. **Nunca** dejes pruebas en rojo "para arreglar después" ni ejecutes `dart fix --apply` mezclado con lógica nueva (corre `dart fix --dry-run` primero y en un paso separado).
