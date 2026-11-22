package com.example.constructora_del_sur

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Se ejecuta cuando AlarmManager dispara el recordatorio diario (app cerrada o abierta). */
class RecordatorioReceiver : BroadcastReceiver() {
    override fun onReceive(contexto: Context, intent: Intent) {
        val titulo = intent.getStringExtra("titulo") ?: "Constructora Del Sur"
        val mensaje = intent.getStringExtra("mensaje") ?: "Es hora de sincronizar los reportes."
        Notificador.mostrar(contexto, MainActivity.ID_RECORDATORIO, titulo, mensaje)
    }
}
