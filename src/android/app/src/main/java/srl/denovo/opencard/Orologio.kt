// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.content.Context
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import java.util.concurrent.TimeUnit

/**
 * Le carte all'orologio. Il perché delle scelte sta in [Sincronia].
 *
 * Senza Google Play services, o senza un orologio collegato, ogni chiamata
 * fallisce o torna vuota, e non succede niente: le carte restano dove sono.
 */
object Orologio {
    private const val ATTESA_S = 5L

    /**
     * Manda tutte le carte a ogni orologio vicino.
     *
     * Da chiamare sul thread dei dati, come fa [Dati]: aspetta le risposte
     * di Play services, e sul thread dell'interfaccia non si aspetta. Un
     * messaggio porta al massimo 100 KB, cioè qualche centinaio di carte:
     * oltre, l'invio fallisce e finisce nel log.
     */
    fun manda(contesto: Context) {
        val carte = try {
            Core.backupEsporta(Core.adesso()).toByteArray()
        } catch (guasto: OpenCardException) {
            return
        }
        try {
            val nodi = Tasks.await(
                Wearable.getNodeClient(contesto).connectedNodes, ATTESA_S, TimeUnit.SECONDS,
            )
            val messaggi = Wearable.getMessageClient(contesto)
            for (nodo in nodi) {
                if (!nodo.isNearby) continue
                Tasks.await(
                    messaggi.sendMessage(nodo.id, Sincronia.CARTE, carte),
                    ATTESA_S, TimeUnit.SECONDS,
                )
            }
        } catch (guasto: Exception) {
            // Niente Play services, orologio non raggiunto, tempo scaduto: le
            // carte restano sul telefono e l'orologio le chiede quando si apre.
            Log.w("OpenCard", "carte non mandate all'orologio: $guasto")
        }
    }
}

/**
 * Riceve la richiesta dell'orologio e risponde con le carte.
 *
 * Lo avvia Play services quando arriva il messaggio, anche con l'app chiusa:
 * il processo parte da [Applicazione], quindi il file è già aperto.
 */
class OrologioService : WearableListenerService() {
    override fun onMessageReceived(messaggio: MessageEvent) {
        if (messaggio.path == Sincronia.RICHIESTA) {
            Dati.fai({ Orologio.manda(this) })
        }
    }
}
