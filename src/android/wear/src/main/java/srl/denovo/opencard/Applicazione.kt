// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Application
import android.util.Log

/**
 * Apre il file delle carte prima di qualunque componente: anche del servizio
 * che riceve le carte dal telefono, che Play services può avviare da solo.
 */
class Applicazione : Application() {
    override fun onCreate() {
        super.onCreate()
        try {
            Dati.apri(this)
        } catch (e: Throwable) {
            Log.e("OpenCard", "apertura dei dati fallita", e)
            Dati.erroreDiApertura = e.message ?: "file delle carte non apribile"
        }
    }
}
