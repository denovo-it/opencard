// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

/**
 * I due messaggi fra telefono e orologio, con i percorsi che i due manifesti
 * filtrano con `pathPrefix="/opencard"`. Il file sta in condiviso perché i
 * due moduli devono scriverli uguali.
 *
 * Il telefono manda tutte le carte, nel formato del backup, a ogni scrittura
 * del file e ogni volta che l'orologio le chiede. Si passa da MessageClient
 * verso i soli nodi vicini, cioè collegati via Bluetooth: con DataClient un
 * orologio lontano riceverebbe i dati attraverso Google, e l'app promette di
 * non usare la rete. Il rovescio è che un orologio spento o lontano perde il
 * messaggio: per quello le chiede lui, quando si apre.
 */
object Sincronia {
    /** Telefono -> orologio: il backup in chiaro, come byte UTF-8. */
    const val CARTE = "/opencard/carte"

    /** Orologio -> telefono: senza contenuto, vuol dire «mandamele». */
    const val RICHIESTA = "/opencard/richiesta"
}
