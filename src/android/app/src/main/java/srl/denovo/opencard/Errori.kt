// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

/**
 * I messaggi degli errori del core, nella lingua dell'app.
 *
 * Quale testo e con quali argomenti lo decide il core
 * (`opencard_errore_scomponi` in `store.c`); da chiave a stringa lo fa
 * `testoCore`, generato da `src/lingue/genera.py` insieme ai file di lingua.
 * Un errore nuovo si aggiunge nel core e nei JSON delle lingue, non qui.
 */
object Errori {
    fun testo(codice: Int, posizione: Int, dettaglio: String, schemaTrovato: Int): String {
        val dove = Applicazione.contesto ?: return "Errore $codice."
        val parti = Core.erroreParti(codice, posizione, dettaglio, schemaTrovato)
        return dove.getString(testoCore(parti[0]), parti[1], parti[2])
    }
}
