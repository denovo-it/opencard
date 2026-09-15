// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

/**
 * Sull'orologio gli errori del core non si mostrano: finiscono nel log, e la
 * schermata dice solo di riaprire OpenCard sul telefono. Il numero è quello di
 * `opencard_esito` in `store.h`; la versione del telefono, nel modulo app,
 * li traduce nella lingua dell'app.
 */
object Errori {
    fun testo(codice: Int, posizione: Int, dettaglio: String, schemaTrovato: Int): String =
        "errore $codice del core (posizione $posizione, schema $schemaTrovato, $dettaglio)"
}
