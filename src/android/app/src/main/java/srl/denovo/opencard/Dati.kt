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
     * Valorizzato se l'apertura del file delle carte e' fallita all'avvio.
     * Le schermate lo mostrano invece di comportarsi come se non fosse successo
     * niente: una lista vuota farebbe pensare che le carte siano sparite.
     */
    var erroreDiApertura: String? = null

    /**
     * Va chiamata una volta all'avvio.
     *
     * `filesDir` e' la directory privata dell'app: nessuna altra app la legge e
     * non serve nessun permesso.
     */
    fun apri(contesto: Context) {
        recuperaDatiEsistenti(contesto)
        Core.storeInit(contesto.filesDir.absolutePath)
    }

    /**
     * Recupera il file delle carte se e' rimasto in una posizione usata da
     * un'installazione precedente.
     *
     * Aggiornando l'app il sistema conserva il container, quindi il file c'e'
     * ancora ma sotto un'altra directory: senza questo l'utente aprirebbe l'app
     * e la troverebbe vuota, con le carte ancora sul telefono ma invisibili.
     *
     * Si copia, non si sposta: se qualcosa va storto l'originale resta dov'e'.
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
     * messaggio gia' scritto per l'utente.
     */
    fun <T> chiedi(
        operazione: () -> T,
        suRisposta: (T) -> Unit,
        suErrore: (String) -> Unit = {},
    ) {
        lavoratore.execute {
            try {
                val risultato = operazione()
                principale.post { suRisposta(risultato) }
            } catch (e: OpenCardException) {
                val messaggio = e.message ?: "Errore imprevisto."
                principale.post { suErrore(messaggio) }
            }
        }
    }

    /** Come [chiedi], per le operazioni che non restituiscono niente. */
    fun fai(
        operazione: () -> Unit,
        suFatto: () -> Unit = {},
        suErrore: (String) -> Unit = {},
    ) = chiedi(operazione, { suFatto() }, suErrore)
}
