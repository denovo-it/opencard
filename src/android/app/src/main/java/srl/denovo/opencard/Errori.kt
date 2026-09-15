// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

/**
 * I messaggi degli errori del core, nella lingua dell'app.
 *
 * I numeri sono quelli di `opencard_esito` in `store.h`: chi ne aggiunge uno
 * aggiunge una riga qui, una in `OCCore.m` e una nei due file di lingua.
 */
object Errori {
    private const val IO = -1
    private const val JSON = -2
    private const val FORMATO = -3
    private const val SCHEMA = -4
    private const val CARTA = -5
    private const val MEMORIA = -6
    private const val NON_TROVATA = -8
    private const val ALTRO_TRASF = -9
    private const val TRASF_INCOMPLETO = -10
    private const val TRASF_ROTTO = -11
    private const val TRASF_VERSIONE = -12
    private const val TRASF_TROPPE = -13
    private const val PASSWORD = -14

    /** Lo stesso numero di `OPENCARD_SCHEMA_VERSION` in `store.h`. */
    private const val SCHEMA_NOSTRO = 3

    fun testo(codice: Int, posizione: Int, dettaglio: String, schemaTrovato: Int): String {
        val dove = Applicazione.contesto ?: return "Errore $codice."
        return when (codice) {
            IO -> dove.getString(R.string.core_io)
            JSON -> dove.getString(R.string.core_json)
            FORMATO -> dove.getString(R.string.core_formato)
            SCHEMA -> dove.getString(R.string.core_schema, schemaTrovato, SCHEMA_NOSTRO)
            CARTA -> if (dettaglio.isEmpty()) {
                dove.getString(R.string.core_carta_senza_dettaglio, posizione)
            } else {
                dove.getString(R.string.core_carta, posizione, dettaglio)
            }
            MEMORIA -> dove.getString(R.string.core_memoria)
            NON_TROVATA -> dove.getString(R.string.core_non_trovata)
            ALTRO_TRASF -> dove.getString(R.string.core_altro_trasferimento)
            TRASF_INCOMPLETO -> dove.getString(R.string.core_trasferimento_incompleto)
            TRASF_ROTTO -> dove.getString(R.string.core_trasferimento_rotto)
            TRASF_VERSIONE -> dove.getString(R.string.core_trasferimento_versione, schemaTrovato)
            TRASF_TROPPE -> dove.getString(R.string.core_trasferimento_troppe)
            PASSWORD -> dove.getString(R.string.core_password)
            else -> dove.getString(R.string.errore_imprevisto)
        }
    }
}
