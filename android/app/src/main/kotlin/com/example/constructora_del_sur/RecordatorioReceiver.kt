package com.example.constructora_del_sur

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Se ejecuta cuando AlarmManager dispara el recordatorio diario (app cerrada o
 * abierta). Verifica en SQLite si existen informes con `sync_status = 'pending'`
 * y solo muestra la notificación cuando hay al menos uno sin sincronizar.
 */
class RecordatorioReceiver : BroadcastReceiver() {
    override fun onReceive(contexto: Context, intent: Intent) {
        // Reagenda siempre para mañana antes de evaluar si hoy hay pendientes.
        RecordatorioAlarmas.reprogramarParaManiana(contexto)

        val nombreDb = intent.getStringExtra(RecordatorioAlarmas.EXTRA_NOMBRE_DB)
            ?: RecordatorioAlarmas.obtenerNombreBaseDatosGuardado(contexto)

        val pendientes = RecordatorioAlarmas.contarReportesPendientes(contexto, nombreDb)
        if (pendientes <= 0) {
            return
        }

        val titulo = intent.getStringExtra(RecordatorioAlarmas.EXTRA_TITULO)
            ?: "Constructora Del Sur"
        val mensajeBase = intent.getStringExtra(RecordatorioAlarmas.EXTRA_MENSAJE)
            ?: "Abrí la app para sincronizar los informes del día."
        val sufijo = if (pendientes == 1) {
            "Tenés 1 informe sin sincronizar."
        } else {
            "Tenés $pendientes informes sin sincronizar."
        }
        val mensajeFinal = "$sufijo $mensajeBase".trim()

        Notificador.mostrar(
            contexto,
            RecordatorioAlarmas.ID_RECORDATORIO,
            titulo,
            mensajeFinal,
        )
    }
}
