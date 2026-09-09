// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/**
 * Quale carta mostra il widget che si sta appoggiando.
 *
 * Il sistema apre questa schermata quando si trascina il widget sulla
 * schermata iniziale, e aspetta un risultato: senza, il widget non compare.
 * Uscendo senza scegliere il risultato resta annullato, che è quello che deve
 * succedere.
 */
class WidgetConfigActivity : AppCompatActivity() {

    private var idWidget = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(statoSalvato: Bundle?) {
        super.onCreate(statoSalvato)
        // Annullato per primo: se si esce con il tasto indietro il sistema deve
        // trovare questo, non un widget a metà.
        setResult(Activity.RESULT_CANCELED)
        setContentView(R.layout.activity_widget_config)

        idWidget = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (idWidget == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val elenco = findViewById<ListView>(R.id.elenco)
        val vuoto = findViewById<TextView>(R.id.vuoto)

        Dati.chiedi(
            { Core.getAll().toList() },
            { carte ->
                if (carte.isEmpty()) {
                    vuoto.visibility = View.VISIBLE
                    elenco.visibility = View.GONE
                    return@chiedi
                }
                elenco.adapter = ArrayAdapter(
                    this,
                    android.R.layout.simple_list_item_1,
                    carte.map { it.label },
                )
                elenco.setOnItemClickListener { _, _, posizione, _ ->
                    scegli(carte[posizione])
                }
            },
            { messaggio ->
                vuoto.text = messaggio
                vuoto.visibility = View.VISIBLE
            },
        )
    }

    private fun scegli(carta: Carta) {
        WidgetCarta.ricorda(this, idWidget, carta.id)
        WidgetCarta.mostra(this, AppWidgetManager.getInstance(this), idWidget, carta)
        setResult(
            Activity.RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, idWidget),
        )
        finish()
    }
}
