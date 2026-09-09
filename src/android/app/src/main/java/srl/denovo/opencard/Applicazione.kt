// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Application
import android.util.Log

/**
 * Apre il file dei dati prima di qualunque schermata.
 *
 * Va fatto qui e non nella prima activity: il sistema può far ripartire l'app
 * da una schermata qualunque, per esempio dopo averla chiusa per memoria.
 */
class Applicazione : Application() {

    companion object {
        /**
         * Il contesto dell'applicazione, per chi non ne ha uno.
         *
         * Serve a [Errori], che compone i messaggi del core pescandoli dai file
         * di lingua: un'eccezione non ha una schermata da cui partire. È il
         * contesto dell'applicazione e non quello di una schermata, quindi non
         * trattiene niente che debba morire.
         */
        var contesto: Application? = null
            private set
    }

    override fun onCreate() {
        super.onCreate()
        contesto = this

        // Per primo, così raccoglie anche gli errori dell'avvio.
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
