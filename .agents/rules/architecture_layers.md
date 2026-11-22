---
trigger: always_on
description: "Invariantes de Arquitectura en Capas (UI / Dominio / Datos), Capacidades vs Políticas y uso de MCPs para Constructora Del Sur."
---
# Reglas de Arquitectura en Capas

1. **Separación estricta de capas (`lib/ui/`, `lib/domain/`, `lib/data/`, `lib/plataforma/`):**
   - `lib/ui/` (Widgets y ViewModels) **nunca** importa `sqflite`, `supabase_flutter`, `firebase_messaging`, `shared_preferences` ni `workmanager`.
   - Los Widgets solo muestran estado y delegan acciones mediante callbacks (`on...`) o métodos del `ViewModel`. Nunca contienen reglas de negocio ni consultas de red/BD.
   - Los `ViewModels` (`ChangeNotifier`) hablan únicamente con `Repositories` (`lib/data/repositories/`) y abstracciones de dominio/plataforma.
   - Los `Repositories` son la **única fuente de verdad** que coordina datos locales (SQLite) y remotos (Supabase) y traduce `Map<String, dynamic>` a modelos inmutables de `lib/domain/models/`.

2. **Inversión de dependencias y costuras (Seams):**
   - Toda nueva integración externa (Supabase, Firebase Messaging) debe quedar detrás de una interfaz o servicio dedicado en `lib/data/services/` inyectable por constructor desde `lib/main.dart`, permitiendo sustituirla por un `Fake` en `test/fakes.dart`.
   - Nunca uses `DateTime.now()` directamente en lógica de negocio o sincronización; inyecta `Reloj` (`lib/data/services/reloj.dart`).

3. **Capacidades vs. Políticas:**
   - **Nunca** uses `Platform.isAndroid` / `Platform.isIOS` directamente dentro de widgets: consulta `Capacidades` (`lib/plataforma/capacidades.dart`).
   - Toda regla de negocio (límites de fotos, permisos por rol, cuándo emitir alertas) vive en `Politicas` o `PoliticaDeAvisos` (`lib/plataforma/politicas.dart`), nunca hardcodeada en pantallas.

4. **Uso obligatorio de Context7 antes de codificar SDKs externos:**
   - Antes de implementar o modificar código de `supabase_flutter`, `firebase_core`, `firebase_messaging` o `workmanager`, consulta la documentación vigente mediante el servidor MCP `context7`.

5. **Seguridad y secretos:**
   - En SQLite usa siempre consultas parametrizadas (`where: 'id = ?', whereArgs: [...]`).
   - En Supabase habilita **RLS (Row Level Security)** en todas las tablas antes de usarlas desde el cliente Flutter.
   - Nunca commitees claves privadas ni `service_role` keys en el repositorio.
