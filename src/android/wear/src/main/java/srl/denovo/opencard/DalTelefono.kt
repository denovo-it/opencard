// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService

/**
 * Le carte dal telefono. Il perché delle scelte sta in [Sincronia].
 *
 * Arrivano tutte insieme, nel formato del backup, e sostituiscono quelle che
 * c'erano: l'orologio non modifica mai una carta, quindi non ha niente da
 * perdere. Il file lo scrive il core, cifrato con la chiave di questo
 * orologio.
 */
class DalTelefono : WearableListenerService() {
    override fun onMessageReceived(messaggio: MessageEvent) {
        if (messaggio.path != Sincronia.CARTE) return
        val carte = messaggio.data
        Dati.fai(
            { Core.backupRipristina(carte) },
            { Dati.suCarteNuove?.invoke() },
            { guasto -> Log.w("OpenCard", "carte dal telefono non lette: $guasto") },
        )
    }

    companion object {
        /**
         * Chiede le carte al telefono, se è vicino. Torna subito: la risposta
         * arriva a [onMessageReceived]. Senza telefono a portata non succede
         * niente, e l'elenco resta com'era.
         */
        fun chiedi(contesto: Context) {
            val messaggi = Wearable.getMessageClient(contesto)
            Wearable.getNodeClient(contesto).connectedNodes.addOnSuccessListener { nodi ->
                for (nodo in nodi) {
                    if (nodo.isNearby) messaggi.sendMessage(nodo.id, Sincronia.RICHIESTA, null)
                }
            }
        }
    }
}
