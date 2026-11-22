package com.example.constructora_del_sur

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Código nativo compartido para crear el canal y publicar avisos.
 * Lo usan tanto MainActivity (avisos inmediatos) como RecordatorioReceiver
 * (aviso diario disparado por AlarmManager con la app cerrada).
 */
object Notificador {
    const val ID_CANAL = "constructora_alertas_obras"

    fun crearCanal(contexto: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val gestor = contexto.getSystemService(NotificationManager::class.java)
            val canal = NotificationChannel(
                ID_CANAL,
                "Alertas de Constructora Del Sur",
                NotificationManager.IMPORTANCE_HIGH
            )
            gestor?.createNotificationChannel(canal)
        }
    }

    fun mostrar(contexto: Context, id: Int, titulo: String, mensaje: String): Boolean {
        val gestor = contexto.getSystemService(NotificationManager::class.java) ?: return false
        if (!gestor.areNotificationsEnabled()) return false
        crearCanal(contexto)

        // Al tocar el aviso se abre (o se trae al frente) la app.
        val intentAbrir = Intent(contexto, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendiente = PendingIntent.getActivity(
            contexto, id, intentAbrir,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val constructor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(contexto, ID_CANAL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(contexto).setPriority(Notification.PRIORITY_HIGH)
        }

        val aviso = constructor
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(titulo)
            .setContentText(mensaje)
            .setStyle(Notification.BigTextStyle().bigText(mensaje))
            .setContentIntent(pendiente)
            .setAutoCancel(true)
            .build()

        return try {
            gestor.notify(id, aviso)
            true
        } catch (_: SecurityException) {
            false
        }
    }
}
