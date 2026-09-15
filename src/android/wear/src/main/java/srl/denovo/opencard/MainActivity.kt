// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import androidx.wear.widget.WearableLinearLayoutManager
import androidx.wear.widget.WearableRecyclerView

/**
 * L'elenco delle carte, con le preferite in cima. Un tocco apre il codice.
 *
 * Ogni volta che torna davanti chiede le carte al telefono: se il telefono è
 * vicino l'elenco si aggiorna da solo, se no resta quello salvato qui.
 */
class MainActivity : Activity() {

    private lateinit var elenco: WearableRecyclerView
    private lateinit var vuoto: TextView
    private val adapter = CarteAdapter { carta ->
        startActivity(Intent(this, CodiceActivity::class.java).putExtra(CodiceActivity.ID, carta.id))
    }

    override fun onCreate(stato: Bundle?) {
        super.onCreate(stato)
        setContentView(R.layout.activity_main)
        elenco = findViewById(R.id.elenco)
        vuoto = findViewById(R.id.vuoto)
        // Le righe ai bordi si avvicinano al centro, dove il cerchio è largo,
        // e la prima e l'ultima si possono portare al centro dello schermo.
        elenco.layoutManager = WearableLinearLayoutManager(this)
        elenco.isEdgeItemsCenteringEnabled = true
        elenco.adapter = adapter
    }

    override fun onResume() {
        super.onResume()
        Dati.suCarteNuove = { ricarica() }
        ricarica()
        DalTelefono.chiedi(this)
    }

    override fun onPause() {
        Dati.suCarteNuove = null
        super.onPause()
    }

    private fun ricarica() {
        if (Dati.erroreDiApertura != null) {
            mostraVuoto(getString(R.string.errore_dati_wear))
            return
        }
        Dati.chiedi(
            { Core.getAll().let { tutte -> tutte.filter { it.preferita } + tutte.filter { !it.preferita } } },
            { carte ->
                adapter.carte = carte
                if (carte.isEmpty()) {
                    mostraVuoto(getString(R.string.nessuna_carta_wear))
                } else {
                    vuoto.visibility = View.GONE
                    elenco.visibility = View.VISIBLE
                    // Con il fuoco, la corona fa scorrere l'elenco.
                    elenco.requestFocus()
                }
            },
            { mostraVuoto(getString(R.string.errore_dati_wear)) },
        )
    }

    private fun mostraVuoto(testo: String) {
        vuoto.text = testo
        vuoto.visibility = View.VISIBLE
        elenco.visibility = View.GONE
    }

    /** Una riga per carta: il nome sul colore della carta. */
    private class CarteAdapter(
        private val suTocco: (Carta) -> Unit,
    ) : RecyclerView.Adapter<CarteAdapter.Riga>() {

        var carte: List<Carta> = emptyList()
            set(valore) {
                field = valore
                @Suppress("NotifyDataSetChanged")
                notifyDataSetChanged()
            }

        class Riga(val vista: TextView) : RecyclerView.ViewHolder(vista)

        override fun onCreateViewHolder(genitore: ViewGroup, tipo: Int): Riga {
            val vista = LayoutInflater.from(genitore.context)
                .inflate(R.layout.riga_carta, genitore, false) as TextView
            return Riga(vista)
        }

        override fun getItemCount() = carte.size

        override fun onBindViewHolder(riga: Riga, posizione: Int) {
            val carta = carte[posizione]
            riga.vista.text = carta.label
            riga.vista.backgroundTintList = ColorStateList.valueOf(coloreCarta(carta.colore))
            riga.vista.setOnClickListener { suTocco(carta) }
        }
    }
}
