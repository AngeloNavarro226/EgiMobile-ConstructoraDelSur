package com.example.constructora_del_sur

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restaura automáticamente la alarma diaria desde SharedPreferences cuando el
 * dispositivo se reinicia o se actualiza el paquete de la aplicación.
 */
class RecordatorioBootReceiver : BroadcastReceiver() {
    override fun onReceive(contexto: Context, intent: Intent) {
        val accion = intent.action
        if (accion == Intent.ACTION_BOOT_COMPLETED ||
            accion == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            RecordatorioAlarmas.restaurarSiActivo(contexto)
        }
    }
}
