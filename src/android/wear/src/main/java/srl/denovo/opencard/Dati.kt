// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

/**
 * Accesso al core da fuori del thread dell'interfaccia, come sul telefono:
 * un solo thread per tutte le operazioni sui dati, così quello che arriva dal
 * telefono e quello che legge la schermata non si pestano.
 */
object Dati {
    private val lavoratore = Executors.newSingleThreadExecutor()
    private val principale = Handler(Looper.getMainLooper())

    /** Valorizzato se l'apertura del file è fallita all'avvio. */
    var erroreDiApertura: String? = null

    /**
     * Chi vuole sapere che sono arrivate carte nuove dal telefono: l'elenco,
     * finché è davanti. Chiamato sul thread dell'interfaccia.
     */
    var suCarteNuove: (() -> Unit)? = null

    fun apri(contesto: Context) {
        Core.storeInit(contesto.filesDir.absolutePath)
        // La chiave prima di qualsiasi lettura, come sul telefono: senza, un
        // file cifrato sembra rotto. Se il portachiavi non risponde si va
        // avanti in chiaro.
        Core.storeChiave(ChiaveDati.dammi(contesto))
    }

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
                val messaggio = e.message ?: "errore imprevisto"
                principale.post { suErrore(messaggio) }
            }
        }
    }

    fun fai(
        operazione: () -> Unit,
        suFatto: () -> Unit = {},
        suErrore: (String) -> Unit = {},
    ) = chiedi(operazione, { suFatto() }, suErrore)
}
