// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.card.MaterialCardView

/**
 * Le carte come schede colorate.
 *
 * Il colore lo decide il core: quello scelto dall'utente, altrimenti quello che
 * spetta all'id. Il glifo dice che tipo di codice si troverà dentro, prima di
 * aprirlo.
 *
 * Il numero della carta nella lista non c'è: chi guarda lo schermo da sopra la
 * spalla lo leggerebbe senza toccare niente. Si vede solo aprendo la carta.
 */
class CarteAdapter(
    private val suTocco: (Carta) -> Unit,
    private val suOrdineCambiato: (IntArray) -> Unit,
    private val suCestino: (Carta) -> Unit,
) : RecyclerView.Adapter<CarteAdapter.Riquadro>() {

    private var carte = mutableListOf<Carta>()
    private var conCestino = false

    class Riquadro(vista: View) : RecyclerView.ViewHolder(vista) {
        val scheda: MaterialCardView = vista.findViewById(R.id.scheda)
        val nome: TextView = vista.findViewById(R.id.nome)
        val glifo: ImageView = vista.findViewById(R.id.glifo)
        val cestino: ImageView = vista.findViewById(R.id.cestino)
    }

    fun mostra(nuove: List<Carta>, cestino: Boolean) {
        carte = nuove.toMutableList()
        conCestino = cestino
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(genitore: ViewGroup, tipo: Int): Riquadro {
        val vista = LayoutInflater.from(genitore.context)
            .inflate(R.layout.item_carta, genitore, false)
        return Riquadro(vista)
    }

    override fun getItemCount() = carte.size

    override fun onBindViewHolder(riquadro: Riquadro, posizione: Int) {
        val carta = carte[posizione]

        riquadro.nome.text = carta.label
        riquadro.scheda.setCardBackgroundColor(coloreCarta(carta.colore))
        riquadro.glifo.setImageResource(
            if (carta.isQrcode) R.drawable.ic_qrcode else R.drawable.ic_barcode
        )
        riquadro.cestino.visibility = if (conCestino) View.VISIBLE else View.GONE
        riquadro.cestino.setOnClickListener { suCestino(carta) }
        riquadro.scheda.setOnClickListener { suTocco(carta) }
    }

    /**
     * Trascinamento verticale per riordinare.
     *
     * L'ordine si salva quando l'utente lascia la presa, non a ogni scambio:
     * altrimenti si scriverebbe il file dei dati decine di volte per un
     * movimento solo.
     */
    fun trascinamento() = object : ItemTouchHelper.SimpleCallback(
        ItemTouchHelper.UP or ItemTouchHelper.DOWN, 0
    ) {
        override fun onMove(
            lista: RecyclerView,
            da: RecyclerView.ViewHolder,
            a: RecyclerView.ViewHolder,
        ): Boolean {
            val partenza = da.bindingAdapterPosition
            val arrivo = a.bindingAdapterPosition
            if (partenza == RecyclerView.NO_POSITION || arrivo == RecyclerView.NO_POSITION) {
                return false
            }
            val carta = carte.removeAt(partenza)
            carte.add(arrivo, carta)
            notifyItemMoved(partenza, arrivo)
            return true
        }

        override fun onSwiped(riquadro: RecyclerView.ViewHolder, direzione: Int) {}

        override fun isLongPressDragEnabled() = true

        override fun clearView(lista: RecyclerView, riquadro: RecyclerView.ViewHolder) {
            super.clearView(lista, riquadro)
            suOrdineCambiato(carte.map { it.id }.toIntArray())
        }
    }
}
