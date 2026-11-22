<<<<<<< HEAD
# EgiMobile-ConstructoraDelSur
Examen global integrador para Desarrollo Mobile -"Tecnicatura Universitaria en desarrollo de software-Instituto Tecnologico Universitario-Uncuyo"-
=======
# Constructora Del Sur — Aplicación Móvil Offline-First

Aplicación móvil desarrollada en **Flutter** para la digitalización en terreno de avances diarios de obra, control de materiales, reportes con fotografías comprimidas, transcripción de voz a texto, monitoreo gerencial mediante sistema de semáforos y exportación automatizada para el sistema legacy **SIGO**.

## 1. Acuerdos de Código Limpio y Convenciones (Effective Dart)

- **Idioma del dominio**: Español (`Obra`, `ReporteDiario`, `Usuario`, `EstadoObra`, `cargar()`, `iniciarSesion()`), manteniendo en inglés únicamente las APIs propias del framework Flutter (`Widget`, `build`, `notifyListeners`).
- **Nomenclatura de piezas por capa**:
  - **Vistas**: `<Funcionalidad>Screen` (por ejemplo, `LoginScreen`, `InicioIngenieroScreen`, `InicioCapatazScreen`, `InicioDuenioScreen`, `AgregarObraScreen`, `CrearInformeScreen`, `ExportarScreen`, `PerfilScreen`, `NotificacionesIngenieroScreen`).
  - **ViewModels**: `<Funcionalidad>ViewModel` extendiendo `ChangeNotifier` (por ejemplo, `AutenticacionViewModel`, `ObrasViewModel`, `ExportarViewModel`, `NotificacionesViewModel`, `PerfilViewModel`).
  - **Repositorios**: `<Dato>Repository` (por ejemplo, `AutenticacionRepository`, `ObrasRepository`, `NotificacionesRepository`, `PreferenciasRepository`).
  - **Servicios**: `<Fuente>Service` (por ejemplo, `BaseDatosLocalService`, `SincronizacionService`, `MultimediaService`, `VozATextoService`, `MapaService`).
  - **Plataforma**: `Capacidades` (`lib/plataforma/capacidades.dart` con el getter `tieneCamara`) y `Politicas` (`lib/plataforma/politicas.dart`).
- **Inyección de dependencias**: Todas las piezas se instancian de abajo hacia arriba en `lib/main.dart` y se inyectan por constructor con parámetros con nombre.

## 2. Estructura de Carpetas (Arquitectura en Capas)

```text
lib/
├── main.dart                                 // Inyección de dependencias y arranque de la app
├── plataforma/
│   ├── capacidades.dart                      // Capacidad de hardware: getter tieneCamara
│   └── politicas.dart                        // Políticas por rol y límites de compresión (< 200 KB)
├── domain/
│   └── models/
│       ├── notificacion_app.dart             // Alertas proactivas y programación de recordatorio
│       ├── obra.dart                         // Obra con cálculo automático de avance por tareas
│       ├── reporte_diario.dart               // Reporte diario con sync_status (pending / synced)
│       ├── tarea_obra.dart                   // Tarea individual (completada / pendiente)
│       ├── ubicacion_obra.dart               // Coordenadas y dirección de Google Maps
│       └── usuario.dart                      // Usuario y RolUsuario (capataz, duenio, ingeniero)
├── data/
│   ├── repositories/
│   │   ├── autenticacion_repository.dart     // Validación de sesión y edición de perfil
│   │   ├── notificaciones_repository.dart    // Alertas amarillo/rojo y horario diario
│   │   ├── obras_repository.dart             // Caché, SQLite y exportación CSV/JSON para SIGO
│   │   └── preferencias_repository.dart      // Tema oscuro y preferencias locales
│   └── services/
│       ├── base_datos_local_service.dart     // Instancia local SQLite (usuarios, obras, reportes_diarios)
│       ├── mapa_service.dart                 // Coordenadas y ubicaciones de Google Maps
│       ├── multimedia_service.dart           // flutter_image_compress (800x600, 70%) + Isolate + Workmanager
│       ├── sincronizacion_service.dart       // connectivity_plus + Workmanager + evento de alerta 2s
│       └── voz_a_texto_service.dart          // speech_to_text para dictado de observaciones en obra
└── ui/
    ├── core/                                 // Widgets compartidos (Semaforo, ObraCard, Banner Sync, Mapa)
    ├── autenticacion/                        // LoginScreen + AutenticacionViewModel
    ├── obras/                                // Vistas de Ingeniero, Capataz, Dueño, Agregar Obra e Informes
    ├── notificaciones/                       // Panel del Ingeniero para envíos y horario diario de sync
    ├── exportar/                             // Exportación CSV (paquete csv) y JSON para SIGO
    └── perfil/                               // Edición de perfil, simulación de sync y cierre de sesión
```

## 3. Usuarios de Prueba en la Base de Datos SQLite Local

Al iniciar la aplicación se presenta la pantalla de **Iniciar Sesión**. Si se ingresan credenciales incorrectas, se muestra el mensaje `"Usuario o contraseña inválidos"` exactamente debajo del campo de contraseña, entre el campo de texto y el botón **Entrar**.

| Rol | Usuario | Contraseña | Vista y Permisos |
| :--- | :--- | :--- | :--- |
| **Ingeniero** | `ingeniero` | `1234` | Grilla de las 6 obras, creación de obras (con tareas, responsable, materiales y ubicación en Google Maps), acceso a informe completo, historial de informes pasados, tareas completas/pendientes, panel de notificaciones y horario de recordatorio diario, más todas las acciones de capataz (hacer informes, añadir tareas y cambiar semáforo). |
| **Capataz** | `capataz` | `1234` | Obras bajo su responsabilidad alineadas en un `Column` (una debajo de otra); al presionar una obra aparece un `SnackBar` con el estado actual y 3 botones: cambiar semáforo, agregar tareas nuevas y realizar informe (con opciones rápidas `DropdownButton`, dictado por voz y fotos con cámara/galería). Comparte Exportar y Perfil. |
| **Dueño** | `dueno` | `1234` | Monitoreo gerencial en grilla de las 6 obras (solo lectura), consulta de estado actual e informes de obra, exportación de datos a SIGO y modificación de su perfil. |

## 4. Cómo Ejecutar el Proyecto y las Pruebas

```bash
flutter pub get
dart format .
flutter analyze
flutter test
flutter run
```
>>>>>>> 0673d71 (chore: estado inicial v2.3 y configuracion agentica de Antigravity)
