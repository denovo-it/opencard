/*
 * SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

package srl.denovo.opencard

import android.app.backup.BackupAgent
import android.app.backup.BackupDataInput
import android.app.backup.BackupDataOutput
import android.app.backup.FullBackupDataOutput
import android.os.ParcelFileDescriptor
import java.io.File

/**
 * Cosa esce dall'app quando il telefono fa il suo backup.
 *
 * Fino alla 1.0.2 la risposta stava nel manifesto, `allowBackup="false"`, e non
 * si poteva cambiare. Dalla 1.0.3 la sceglie chi usa l'app, e una scelta che
 * cambia a telefono acceso nel manifesto non si scrive: serve questa classe,
 * che il sistema chiama ogni volta che sta per fare un backup.
 *
 * Interruttore spento: il metodo torna subito e non esce un byte.
 *
 * Interruttore acceso: **non** si copiano i file dell'app così come stanno.
 * Il file delle carte sul disco è cifrato con una chiave che vive nel Keystore
 * e da questo telefono non esce; copiarlo altrove darebbe un file che nessuno
 * può più aprire, e le carte sarebbero perse senza che nessuno se ne accorga.
 * Esce invece un JSON in chiaro, lo stesso di «Esporta su file», più le foto,
 * e al primo avvio sul telefono nuovo l'app lo importa e lo cancella. Il file
 * in chiaro esiste sul disco per il tempo del backup e viene tolto subito.
 *
 * Vale anche per il passaggio diretto fra due telefoni, che il sistema fa
 * chiamando lo stesso metodo.
 */
class BackupNelCloud : BackupAgent() {

    companion object {
        /** Il file che il telefono nuovo si ritrova in `filesDir` dopo il ripristino. */
        const val DA_RIPRISTINARE = "ripristino-cloud.json"
    }

    override fun onFullBackup(dati: FullBackupDataOutput?) {
        if (dati == null || !Impostazioni.backupNelCloud(this)) {
            return
        }

        val esportato = File(filesDir, DA_RIPRISTINARE)
        try {
            Core.storeInit(filesDir.absolutePath)
            Core.storeChiave(ChiaveDati.dammi(this))
            esportato.writeText(Core.backupEsporta(quandoIso()))
            fullBackupFile(esportato, dati)

            // Le foto sono file JPEG a parte e nella carta viaggia solo il
            // nome: senza queste righe il telefono nuovo troverebbe le carte
            // con il riferimento a foto che non ci sono.
            File(filesDir, "foto").listFiles()?.forEach { fullBackupFile(it, dati) }

            // Anche la scelta stessa, se no sul telefono nuovo l'interruttore
            // ripartirebbe spento con le carte già arrivate.
            fullBackupFile(File(File(dataDir, "shared_prefs"), "${Impostazioni.FILE}.xml"), dati)
        } catch (guasto: Exception) {
            // Un backup che non riesce non deve buttare giu' il processo: il
            // sistema lo ritenta domani, e le carte sul telefono sono intatte.
        } finally {
            esportato.delete()
        }
    }

    private fun quandoIso(): String =
        java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US)
            .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
            .format(java.util.Date())

    /* Il backup a chiave e valore non si usa, l'app dichiara `fullBackupOnly`.
     * I due metodi sono obbligatori e restano vuoti. */
    override fun onBackup(
        vecchio: ParcelFileDescriptor?,
        dati: BackupDataOutput?,
        nuovo: ParcelFileDescriptor?,
    ) = Unit

    override fun onRestore(
        dati: BackupDataInput?,
        versione: Int,
        nuovo: ParcelFileDescriptor?,
    ) = Unit
}
