---
trigger: glob
globs: "lib/**/*.dart, test/**/*.dart"
description: "Reglas de Código Limpio en Dart basadas en CodigoLimpio_Apunte.pdf y Effective Dart."
---
# Cláusulas de Código Limpio en Dart

Aplica estas reglas en todo archivo `.dart` que crees o modifiques (basadas en `CodigoLimpio_Apunte.pdf` y `analysis_options.yaml`):

## 1. Nombres según Effective Dart
- `UpperCamelCase` para clases, enums, extensiones y typedefs (`ObrasViewModel`, `EstadoObra`).
- `lowerCamelCase` para variables, parámetros, métodos, propiedades, **constantes** y valores de enum (`pesoMaximoFotoKb`, `EstadoSincronizacion.pending`). No uses `MAYUSCULAS_SOSTENIDAS` ni prefijo `k` en constantes propias.
- `lowercase_with_underscores` para archivos y carpetas (`obras_repository.dart`). Cada clase pública principal vive en su propio archivo con el mismo nombre.
- Siglas de más de dos letras como palabra común: `HttpService`, `ApiClient`, `obraId` (no `HTTPService` ni `obraID`).
- **Idioma consistente:** Español sin tildes ni `ñ` en identificadores del dominio (`estaCargando`, `tieneFoto`, `puedeCrearObras`).
- **Semántica de nombres:**
  - Booleanos como pregunta de sí/no (`estaFinalizada`, `tieneSesionActiva`).
  - Métodos que ejecutan acciones como verbos (`cargar()`, `sincronizarPendientes()`).
  - Valores derivados rápidos y sin efectos secundarios como `get` sustantivos (`totalTexto`, `porcentajeAvance`), **nunca** `getPorcentajeAvance()`.
  - Conversiones con `to...()` (`toMap()`, `toJson()`).

## 2. Funciones y Métodos Limpios
- **Una sola responsabilidad:** Si para explicar una función necesitas decir "y" ("valida y calcula y guarda y notifica"), divídela.
- **Cláusulas de guarda (retornos tempranos):** Prefiere `if (!puedeContinuar) return;` al inicio en lugar de `if` anidados profundos.
- **Parámetros pocos y con nombre:** Evita booleanos posicionales (`obtenerObras(true)` está prohibido; usa `obtenerObras(forzarRecarga: true)`). Si una función requiere más de 4 datos relacionados, agrúpalos en una clase de dominio inmutable.
- **Cero números mágicos:** Extrae todo valor numérico de negocio a una constante con nombre en `Politicas` o en la clase correspondiente.
- **DRY con criterio:** No dupliques reglas de negocio entre capas ni entre pantallas.

## 3. Widgets Limpios
- **Extrae clases de `Widget`, no métodos `_build...()`** cuando un subárbol crece o se reutiliza; así Flutter puede optimizar reconstrucciones con `const` y aparecen nombrados en DevTools.
- **Comunicación por callbacks (`on...`):** Los widgets pequeños no reciben el `ViewModel` completo; reciben solo los datos que muestran y callbacks (`VoidCallback? onConfirmar`).
- **Usa `const` siempre que sea posible** (`prefer_const_constructors: true`).
- **Cero lógica de negocio en `build()`:** La vista solo presenta datos y dispara eventos.
- **Imports ordenados en 3 bloques alfabéticos** (`directives_ordering: true`): `dart:`, `package:`, y archivos relativos del proyecto.

## 4. Documentación y Herramientas
- Usa `///` (nunca `/** ... */`) para documentar clases y métodos públicos de `data/`, `domain/` y `ViewModels`, referenciando símbolos entre corchetes (`[ObrasRepository]`).
- Borra todo código muerto o comentado ("por las dudas") y elimina "comentarios desodorante" mejorando los nombres.
- Respeta estrictamente `analysis_options.yaml`: comillas simples (`prefer_single_quotes`), tipos de retorno explícitos (`always_declare_return_types`), `unawaited(...)` explícito en futuros no esperados (`unawaited_futures`) y ancho máximo de 80 caracteres (`dart format .`).
