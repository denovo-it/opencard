// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Application
import android.util.Log

/**
 * Apre il file dei dati prima di qualunque schermata.
 *
 * Va fatto qui e non nella prima activity: il sistema puo' far ripartire l'app
 * da una schermata qualunque, per esempio dopo averla chiusa per memoria.
 */
class Applicazione : Application() {
    override fun onCreate() {
        super.onCreate()

        // Per primo, cosi' raccoglie anche gli errori dell'avvio.
        Diagnostica.installa(this)

        // Un problema qui non deve chiudere l'app senza dire niente: le
        // schermate mostrano l'errore e restano usabili per il resto.
        try {
            Dati.apri(this)
        } catch (e: Throwable) {
            Log.e("OpenCard", "apertura dei dati fallita", e)
            Dati.erroreDiApertura = e.message ?: "Non riesco ad aprire il file delle carte."
        }
    }
}
