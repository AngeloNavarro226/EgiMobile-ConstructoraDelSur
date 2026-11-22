package com.example.constructora_del_sur

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import java.util.Calendar

/**
 * Centraliza la persistencia en SharedPreferences nativo, la programación en
 * AlarmManager y la verificación de informes pendientes en SQLite para el
 * recordatorio diario de sincronización.
 */
object RecordatorioAlarmas {
    const val ID_RECORDATORIO = 90002

    private const val NOMBRE_PREFS = "constructora_recordatorio_prefs"
    private const val CLAVE_ACTIVO = "activo"
    private const val CLAVE_HORA = "hora"
    private const val CLAVE_MINUTO = "minuto"
    private const val CLAVE_TITULO = "titulo"
    private const val CLAVE_MENSAJE = "mensaje"
    private const val CLAVE_NOMBRE_DB = "nombre_base_datos"

    const val EXTRA_TITULO = "titulo"
    const val EXTRA_MENSAJE = "mensaje"
    const val EXTRA_NOMBRE_DB = "nombreBaseDatos"
    const val DB_POR_DEFECTO = "constructora_del_sur_v4.db"

    private fun prefs(contexto: Context) =
        contexto.getSharedPreferences(NOMBRE_PREFS, Context.MODE_PRIVATE)

    private fun construirPendingIntent(
        contexto: Context,
        titulo: String,
        mensaje: String,
        nombreBaseDatos: String,
    ): PendingIntent {
        val intent = Intent(contexto, RecordatorioReceiver::class.java).apply {
            putExtra(EXTRA_TITULO, titulo)
            putExtra(EXTRA_MENSAJE, mensaje)
            putExtra(EXTRA_NOMBRE_DB, nombreBaseDatos)
        }
        return PendingIntent.getBroadcast(
            contexto,
            ID_RECORDATORIO,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Guarda en SharedPreferences y agenda la alarma diaria en AlarmManager. */
    fun programar(
        contexto: Context,
        hora: Int,
        minuto: Int,
        titulo: String,
        mensaje: String,
        nombreBaseDatos: String = DB_POR_DEFECTO,
    ) {
        prefs(contexto).edit()
            .putBoolean(CLAVE_ACTIVO, true)
            .putInt(CLAVE_HORA, hora)
            .putInt(CLAVE_MINUTO, minuto)
            .putString(CLAVE_TITULO, titulo)
            .putString(CLAVE_MENSAJE, mensaje)
            .putString(CLAVE_NOMBRE_DB, nombreBaseDatos)
            .apply()

        agendarEnAlarmManager(
            contexto = contexto,
            hora = hora,
            minuto = minuto,
            titulo = titulo,
            mensaje = mensaje,
            nombreBaseDatos = nombreBaseDatos,
        )
    }

    /** Reprograma la alarma desde SharedPreferences tras reiniciar el dispositivo. */
    fun restaurarSiActivo(contexto: Context) {
        val p = prefs(contexto)
        if (!p.getBoolean(CLAVE_ACTIVO, false)) return
        val hora = p.getInt(CLAVE_HORA, 18)
        val minuto = p.getInt(CLAVE_MINUTO, 0)
        val titulo = p.getString(CLAVE_TITULO, "Constructora Del Sur") ?: "Constructora Del Sur"
        val mensaje = p.getString(
            CLAVE_MENSAJE,
            "Tenés informes sin sincronizar. Abrí la app para subirlos.",
        ) ?: "Tenés informes sin sincronizar. Abrí la app para subirlos."
        val nombreDb = p.getString(CLAVE_NOMBRE_DB, DB_POR_DEFECTO) ?: DB_POR_DEFECTO

        agendarEnAlarmManager(
            contexto = contexto,
            hora = hora,
            minuto = minuto,
            titulo = titulo,
            mensaje = mensaje,
            nombreBaseDatos = nombreDb,
        )
    }

    /** Cancela la alarma activa y desactiva el registro en SharedPreferences. */
    fun cancelar(contexto: Context) {
        prefs(contexto).edit().putBoolean(CLAVE_ACTIVO, false).apply()
        val alarmas = contexto.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmas.cancel(construirPendingIntent(contexto, "", "", DB_POR_DEFECTO))
    }

    /** Devuelve el nombre de la BD local configurada en SharedPreferences. */
    fun obtenerNombreBaseDatosGuardado(contexto: Context): String {
        return prefs(contexto).getString(CLAVE_NOMBRE_DB, DB_POR_DEFECTO) ?: DB_POR_DEFECTO
    }

    /**
     * Consulta la tabla `reportes_diarios` en modo solo lectura para saber
     * cuántos informes siguen con `sync_status = 'pending'`.
     */
    fun contarReportesPendientes(contexto: Context, nombreBaseDatos: String): Int {
        val archivoDb = contexto.getDatabasePath(nombreBaseDatos)
        if (!archivoDb.exists()) return 0

        return try {
            SQLiteDatabase.openDatabase(
                archivoDb.path,
                null,
                SQLiteDatabase.OPEN_READONLY,
            ).use { db ->
                db.rawQuery(
                    "SELECT COUNT(*) FROM reportes_diarios WHERE sync_status = ?",
                    arrayOf("pending"),
                ).use { cursor ->
                    if (cursor.moveToFirst()) cursor.getInt(0) else 0
                }
            }
        } catch (_: Exception) {
            0
        }
    }

    private fun agendarEnAlarmManager(
        contexto: Context,
        hora: Int,
        minuto: Int,
        titulo: String,
        mensaje: String,
        nombreBaseDatos: String,
    ) {
        val alarmas = contexto.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val proxima = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hora)
            set(Calendar.MINUTE, minuto)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }
        alarmas.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            proxima.timeInMillis,
            AlarmManager.INTERVAL_DAY,
            construirPendingIntent(contexto, titulo, mensaje, nombreBaseDatos),
        )
    }
}
