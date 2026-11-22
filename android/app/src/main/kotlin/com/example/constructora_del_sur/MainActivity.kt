package com.example.constructora_del_sur

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {
    companion object {
        const val ID_RECORDATORIO = 90002
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
                        val mensaje = llamada.argument<String>("mensaje") ?: ""
                        programarRecordatorio(hora, minuto, titulo, mensaje)
                        resultado.success(true)
                    }
                    "cancelarRecordatorio" -> {
                        cancelarRecordatorio()
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

    private fun intentRecordatorio(titulo: String, mensaje: String): PendingIntent {
        val intent = Intent(this, RecordatorioReceiver::class.java).apply {
            putExtra("titulo", titulo)
            putExtra("mensaje", mensaje)
        }
        return PendingIntent.getBroadcast(
            this, ID_RECORDATORIO, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Alarma diaria inexacta (no necesita permiso de alarmas exactas; Android puede correrla unos minutos). */
    private fun programarRecordatorio(hora: Int, minuto: Int, titulo: String, mensaje: String) {
        val alarmas = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val proxima = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hora)
            set(Calendar.MINUTE, minuto)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        alarmas.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            proxima.timeInMillis,
            AlarmManager.INTERVAL_DAY,
            intentRecordatorio(titulo, mensaje)
        )
    }

    private fun cancelarRecordatorio() {
        val alarmas = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmas.cancel(intentRecordatorio("", ""))
    }
}
