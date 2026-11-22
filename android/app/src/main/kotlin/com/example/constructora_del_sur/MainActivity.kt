package com.example.constructora_del_sur

import android.Manifest
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val ID_RECORDATORIO = RecordatorioAlarmas.ID_RECORDATORIO
        private const val CODIGO_PERMISO_NOTIFICACIONES = 2026
    }

    private val nombreCanalMetodo = "constructora_del_sur/notificaciones_nativas"

    // Respuesta pendiente a Dart mientras el usuario decide en el diálogo del sistema.
    private var respuestaPermisoPendiente: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Notificador.crearCanal(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nombreCanalMetodo)
            .setMethodCallHandler { llamada, resultado ->
                when (llamada.method) {
                    "pedirPermiso" -> pedirPermiso(resultado)
                    "mostrarNotificacion" -> {
                        val id = llamada.argument<Int>("id") ?: 100
                        val titulo = llamada.argument<String>("titulo") ?: "Constructora Del Sur"
                        val mensaje = llamada.argument<String>("mensaje") ?: ""
                        resultado.success(Notificador.mostrar(this, id, titulo, mensaje))
                    }
                    "cancelarNotificacion" -> {
                        val id = llamada.argument<Int>("id") ?: 100
                        getSystemService(NotificationManager::class.java)?.cancel(id)
                        resultado.success(true)
                    }
                    "programarRecordatorio" -> {
                        val hora = llamada.argument<Int>("hora") ?: 18
                        val minuto = llamada.argument<Int>("minuto") ?: 0
                        val titulo = llamada.argument<String>("titulo") ?: "Constructora Del Sur"
                        val mensaje = llamada.argument<String>("mensaje")
                            ?: "Abrí la app para sincronizar los reportes del día."
                        val nombreBaseDatos = llamada.argument<String>("nombreBaseDatos")
                            ?: RecordatorioAlarmas.DB_POR_DEFECTO
                        RecordatorioAlarmas.programar(
                            contexto = this,
                            hora = hora,
                            minuto = minuto,
                            titulo = titulo,
                            mensaje = mensaje,
                            nombreBaseDatos = nombreBaseDatos,
                        )
                        resultado.success(true)
                    }
                    "cancelarRecordatorio" -> {
                        RecordatorioAlarmas.cancelar(this)
                        resultado.success(true)
                    }
                    else -> resultado.notImplemented()
                }
            }
    }

    /** Responde true/false recién cuando el usuario contestó el diálogo (Android 13+). */
    private fun pedirPermiso(resultado: MethodChannel.Result) {
        val gestor = getSystemService(NotificationManager::class.java)
        val habilitadas = gestor?.areNotificationsEnabled() ?: false

        if (habilitadas) {
            resultado.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // Antes de Android 13 no hay diálogo: si están deshabilitadas, lo hizo el usuario en Ajustes.
            resultado.success(false)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            resultado.success(true)
            return
        }
        respuestaPermisoPendiente?.success(false)
        respuestaPermisoPendiente = resultado
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), CODIGO_PERMISO_NOTIFICACIONES)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CODIGO_PERMISO_NOTIFICACIONES) {
            val concedido = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            respuestaPermisoPendiente?.success(concedido)
            respuestaPermisoPendiente = null
        }
    }
}
