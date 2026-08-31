// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.content.Context
import android.os.Build
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Raccoglie l'errore che ha chiuso l'app, per poterlo leggere dopo.
 *
 * Senza questo, di un arresto resta solo il messaggio di sistema, che non dice
 * niente di utile. Il file finisce in una cartella raggiungibile con un gestore
 * di file, così si può mandare a chi sviluppa senza collegare il telefono a un
 * computer.
 */
object Diagnostica {

    private const val NOME_FILE = "ultimo-errore.txt"

    /** Va installato per primo, prima di qualunque altra cosa nell'app. */
    fun installa(contesto: Context) {
        val precedente = Thread.getDefaultUncaughtExceptionHandler()

        Thread.setDefaultUncaughtExceptionHandler { thread, errore ->
            try {
                scrivi(contesto, thread, errore)
            } catch (e: Throwable) {
                // Se anche la scrittura fallisce non si insiste: conta che il
                // sistema riceva comunque l'errore originale.
            }
            precedente?.uncaughtException(thread, errore)
        }
    }

    private fun scrivi(contesto: Context, thread: Thread, errore: Throwable) {
        val traccia = StringWriter()
        errore.printStackTrace(PrintWriter(traccia))

        val quando = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ITALY).format(Date())
        val testo = buildString {
            appendLine("OpenCard ${BuildConfig.VERSION_NAME} build ${BuildConfig.VERSION_CODE}")
            appendLine("$quando, thread ${thread.name}")
            appendLine("${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            appendLine()
            append(traccia.toString())
        }

        destinazioni(contesto).forEach { file ->
            try {
                file.parentFile?.mkdirs()
                file.writeText(testo)
            } catch (e: Throwable) {
                // La prossima destinazione può andare meglio.
            }
        }
    }

    /**
     * Due posizioni: quella esterna si apre con un gestore di file senza
     * permessi, quella interna resta come riserva se la prima non c'è.
     */
    private fun destinazioni(contesto: Context): List<File> = listOfNotNull(
        contesto.getExternalFilesDir(null)?.let { File(it, NOME_FILE) },
        File(contesto.filesDir, NOME_FILE),
    )

    /** L'ultimo errore raccolto, oppure null. */
    fun ultimoErrore(contesto: Context): String? =
        destinazioni(contesto).firstOrNull { it.exists() }?.let {
            try {
                it.readText()
            } catch (e: Throwable) {
                null
            }
        }

    fun dimentica(contesto: Context) {
        destinazioni(contesto).forEach {
            try {
                it.delete()
            } catch (e: Throwable) {
                // Se resta, al massimo lo si rivede una volta di più.
            }
        }
    }
}
