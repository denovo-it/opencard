// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Una carta sulla schermata iniziale.
 *
 * Un widget vale una carta, scelta quando lo si appoggia. Mostra il nome sul
 * colore della carta e basta: il numero non ci va, perché la schermata
 * iniziale la vede chiunque guardi il telefono, e nell'elenco dentro l'app il
 * numero non si mostra per la stessa ragione. Toccandolo si apre la carta, che
 * è la schermata con il codice grande e la luminosità al massimo.
 */
class WidgetCarta : AppWidgetProvider() {

    /**
     * Il sistema chiama qui, e leggere le carte vuol dire leggere un file.
     *
     * `goAsync` tiene vivo il processo finché la lettura non è finita: senza,
     * il sistema può chiuderlo appena questo metodo ritorna, e il widget
     * resterebbe come stava.
     */
    override fun onUpdate(contesto: Context, gestore: AppWidgetManager, quali: IntArray) {
        val risultato = goAsync()
        Dati.chiedi(
            { quali.map { it to leggiCarta(contesto, it) } },
            { coppie ->
                coppie.forEach { (idWidget, carta) -> mostra(contesto, gestore, idWidget, carta) }
                risultato.finish()
            },
            { risultato.finish() },
        )
    }

    /** Un widget tolto dalla schermata non deve lasciare la sua riga nel file. */
    override fun onDeleted(contesto: Context, quali: IntArray) {
        val penna = dove(contesto).edit()
        quali.forEach { penna.remove(chiave(it)) }
        penna.apply()
    }

    companion object {
        private const val FILE = "widget"

        private fun dove(contesto: Context) =
            contesto.getSharedPreferences(FILE, Context.MODE_PRIVATE)

        private fun chiave(idWidget: Int) = "carta_$idWidget"

        /** Quale carta mostra questo widget. Zero vuol dire nessuna. */
        fun cartaDi(contesto: Context, idWidget: Int) = dove(contesto).getInt(chiave(idWidget), 0)

        fun ricorda(contesto: Context, idWidget: Int, idCarta: Int) {
            dove(contesto).edit().putInt(chiave(idWidget), idCarta).apply()
        }

        /**
         * Rifà tutti i widget appoggiati.
         *
         * Si chiama quando le carte cambiano: senza, un nome modificato o una
         * carta cancellata resterebbero sulla schermata iniziale come prima,
         * fino al giro di aggiornamento del sistema.
         */
        fun aggiornaTutti(contesto: Context) {
            val gestore = AppWidgetManager.getInstance(contesto)
            val quali = gestore.getAppWidgetIds(
                ComponentName(contesto, WidgetCarta::class.java)
            )
            if (quali.isEmpty()) return
            val aggiorna = Intent(contesto, WidgetCarta::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, quali)
            }
            contesto.sendBroadcast(aggiorna)
        }

        /** La carta di un widget, o null se non c'è più. */
        private fun leggiCarta(contesto: Context, idWidget: Int): Carta? {
            val idCarta = cartaDi(contesto, idWidget)
            if (idCarta == 0) return null
            return try {
                Core.get(idCarta)
            } catch (guasto: OpenCardException) {
                // Cancellata dall'app: il widget resta, e lo dice.
                null
            }
        }

        /**
         * Scrive il widget. Con `carta` a null vuol dire che quella carta non
         * c'è più: si dice, e toccandolo si apre l'app invece di niente.
         */
        fun mostra(
            contesto: Context,
            gestore: AppWidgetManager,
            idWidget: Int,
            carta: Carta?,
        ) {
            val viste = RemoteViews(contesto.packageName, R.layout.widget_carta)

            if (carta != null) {
                viste.setTextViewText(R.id.widget_nome, carta.label)
                viste.setTextViewText(R.id.widget_sotto, contesto.getString(R.string.widget_tocca))
                // Il colore va sull'immagine di fondo e non sullo sfondo della
                // vista: setBackgroundColor cancellerebbe il disegno, e con lui
                // gli angoli arrotondati.
                viste.setInt(R.id.widget_fondo, "setColorFilter", coloreCarta(carta.colore))
                viste.setOnClickPendingIntent(
                    R.id.widget_radice,
                    apri(contesto, DettaglioActivity.intent(contesto, carta.id), carta.id),
                )
            } else {
                viste.setTextViewText(R.id.widget_nome, contesto.getString(R.string.app_name))
                viste.setTextViewText(
                    R.id.widget_sotto,
                    contesto.getString(R.string.widget_carta_sparita),
                )
                viste.setInt(R.id.widget_fondo, "setColorFilter", coloreCarta("#6B7280"))
                viste.setOnClickPendingIntent(
                    R.id.widget_radice,
                    apri(contesto, Intent(contesto, MainActivity::class.java), idWidget),
                )
            }

            gestore.updateAppWidget(idWidget, viste)
        }

        /**
         * Il codice della richiesta è diverso per ogni widget: con lo stesso,
         * due widget di due carte diverse si ritroverebbero lo stesso intento e
         * aprirebbero tutti la carta dell'ultimo.
         */
        private fun apri(contesto: Context, destinazione: Intent, codice: Int): PendingIntent {
            destinazione.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            return PendingIntent.getActivity(
                contesto,
                codice,
                destinazione,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
