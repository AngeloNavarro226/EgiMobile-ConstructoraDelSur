---
name: ui-production-cleanup
description: Elimina componentes, textos, botones de simulación y credenciales hardcodeadas de la versión de prueba en las vistas de Flutter, actualizando los tests de widgets para mantener todo en verde.
---
# Skill: Limpieza de UI de Versión de Prueba hacia Producción

Usa esta skill para auditar y eliminar todos los elementos exclusivos de la demostración/prototipo académico antes de pasar a producción real.

## 1. Inventario conocido de elementos de prueba a revisar y retirar
Antes de editar, inspecciona cada archivo y confirma con el usuario qué elementos eliminar en el paso actual:

1. **Login (`lib/ui/autenticacion/widgets/login_screen.dart`):**
   - Eliminar `_TarjetaUsuariosPrueba` (líneas ~134 y 149–195) que muestra *"Usuarios de prueba en BD SQLite local (contraseña: 1234)"* y los botones de acceso rápido (`ingeniero / 1234`, `capataz / 1234`, `dueno / 1234`).
   - Eliminar el método `_autocompletarCredencialPrueba` (línea ~39).
   - Conservar las `Key` de prueba (`Key('boton_iniciar_sesion')`, `Key('mensaje_credenciales_invalidas')`) para no romper `test/widget_test.dart` innecesariamente.
2. **Simulaciones de conectividad y notificaciones:**
   - Revisar `lib/ui/perfil/widgets/perfil_screen.dart`, `lib/ui/obras/widgets/inicio_capataz_screen.dart` y `lib/ui/notificaciones/widgets/notificaciones_ingeniero_screen.dart` para retirar botones de *"Simular detección de Internet"* o *"Probar notificación local"* cuando la sincronización real y FCM estén activos (o moverlos detrás de `if (kDebugMode)` solo si el equipo los necesita en desarrollo).
3. **Textos y referencias de demo:**
   - Revisar `SnackBar`s y subtítulos que mencionen `"BD SQLite local"`, `"sync_status = pending"` crudo o `"usuarios de prueba"` y reemplazarlos por mensajes claros para usuarios finales de Constructora Del Sur (ej. `"Informe guardado. Se sincronizará automáticamente cuando haya conexión."`).
   - Retirar semillas hardcodeadas con contraseñas planas (`'1234'`) en `BaseDatosLocalService._insertarSemillasSql` una vez que Supabase Auth esté operativo.

## 2. Reglas de ejecución segura
- Aplica la limpieza en pasos pequeños por pantalla (no borres toda la UI en un solo cambio masivo).
- Verifica que ninguna pantalla quede con imports sin usar (`unused_import`) ni widgets huérfanos.
- Actualiza `test/widget_test.dart` si alguna expectativa dependía de widgets de prueba eliminados, asegurando que el test siga validando el flujo real de login y navegación.

## 3. Verificación
- Ejecuta `flutter-quality-gate` (`dart format`, `flutter analyze`, `flutter test`).
- Actualiza `@docs/PROJECT_CONTEXT.md` con `update-project-context`.
