// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.io.File
import java.util.concurrent.Executors

/**
 * Accesso al core da fuori del thread dell'interfaccia.
 *
 * Un solo thread per tutte le operazioni sui dati: le scritture si serializzano
 * da sole e due schermate non possono salvare insieme.
 */
object Dati {
    private val lavoratore = Executors.newSingleThreadExecutor()
    private val principale = Handler(Looper.getMainLooper())

    /**
     * Valorizzato se l'apertura del file delle carte è fallita all'avvio.
     * Le schermate lo mostrano invece di comportarsi come se non fosse successo
     * niente: una lista vuota farebbe pensare che le carte siano sparite.
     */
    var erroreDiApertura: String? = null

    private lateinit var applicazione: Context
    private lateinit var fileCarte: File

    /**
     * Va chiamata una volta all'avvio.
     *
     * `filesDir` è la directory privata dell'app: nessuna altra app la legge e
     * non serve nessun permesso.
     */
    fun apri(contesto: Context) {
        applicazione = contesto.applicationContext
        fileCarte = File(contesto.filesDir, "opencard.json")
        recuperaDatiEsistenti(contesto)
        Core.storeInit(contesto.filesDir.absolutePath)
        // La chiave prima di qualsiasi lettura: un file cifrato senza chiave
        // non si apre, e senza questa riga l'app direbbe che il file è rotto.
        // Se il portachiavi non risponde si va avanti in chiaro, come prima:
        // meglio un file leggibile che un'app che non si apre.
        Core.storeChiave(ChiaveDati.dammi(contesto))
        ripristinaDalCloud(contesto)
    }

    /**
     * Le carte arrivate con il backup del telefono, se ce ne sono.
     *
     * Il ripristino del sistema avviene prima che l'app venga aperta, e lascia
     * in `filesDir` il JSON scritto da [BackupNelCloud]. Qui si importa e si
     * cancella: da quel momento le carte stanno nel file dell'app, cifrate con
     * la chiave di questo telefono.
     */
    private fun ripristinaDalCloud(contesto: Context) {
        val arrivato = File(contesto.filesDir, BackupNelCloud.DA_RIPRISTINARE)
        if (!arrivato.exists()) return
        try {
            Core.backupRipristina(arrivato.readBytes())
        } catch (guasto: Exception) {
            // Se il file è rotto non si insiste: le carte non ci sono e
            // l'app parte vuota, che è quello che succedeva prima.
        } finally {
            arrivato.delete()
        }
    }

    /**
     * Recupera il file delle carte se è rimasto in una posizione usata da
     * un'installazione precedente.
     *
     * Aggiornando l'app il sistema conserva il container, quindi il file c'è
     * ancora ma sotto un'altra directory: senza questo l'utente aprirebbe l'app
     * e la troverebbe vuota, con le carte ancora sul telefono ma invisibili.
     *
     * Si copia, non si sposta: se qualcosa va storto l'originale resta dov'è.
     */
    private fun recuperaDatiEsistenti(contesto: Context) {
        val attuale = File(contesto.filesDir, "opencard.json")
        if (attuale.exists()) return

        val possibili = listOf(
            File(contesto.filesDir, "flet/opencard.json"),
            File(contesto.filesDir, "flet/app/opencard.json"),
        )
        val trovato = possibili.firstOrNull { it.exists() && it.length() > 0 } ?: return

        try {
            trovato.copyTo(attuale, overwrite = false)
        } catch (e: Exception) {
            // Se non si riesce si parte da vuoto: il file di partenza resta
            // intatto e le carte si recuperano da un backup.
        }
    }

    /**
     * Esegue [operazione] sul thread dei dati e riporta il risultato su quello
     * dell'interfaccia. Se il core solleva un errore, arriva a [suErrore] col
     * messaggio già scritto per l'utente.
     */
    fun <T> chiedi(
        operazione: () -> T,
        suRisposta: (T) -> Unit,
        suErrore: (String) -> Unit = {},
    ) {
        lavoratore.execute {
            val prima = impronta()
            try {
                val risultato = operazione()
                principale.post { suRisposta(risultato) }
            } catch (e: OpenCardException) {
                val messaggio = e.message ?: "Errore imprevisto."
                principale.post { suErrore(messaggio) }
            }
            // Se l'operazione ha scritto il file, l'orologio riceve le carte
            // com'è adesso. Si guarda il file e non l'operazione, così vale
            // per ogni scrittura, anche per quelle che verranno: il core
            // scrive sempre lì. La risposta è già partita, quindi
            // l'interfaccia non aspetta l'orologio.
            if (impronta() != prima) Orologio.manda(applicazione)
        }
    }

    /** Data e misura del file delle carte: cambiano a ogni scrittura del core. */
    private fun impronta() = fileCarte.lastModified() to fileCarte.length()

    /** Come [chiedi], per le operazioni che non restituiscono niente. */
    fun fai(
        operazione: () -> Unit,
        suFatto: () -> Unit = {},
        suErrore: (String) -> Unit = {},
    ) = chiedi(operazione, { suFatto() }, suErrore)
}
