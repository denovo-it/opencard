// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

/**
 * Le schede come pagine affiancate, così si passa dall'una all'altra anche
 * scorrendo con il dito.
 *
 * Le prime due ci sono sempre: carte e usa e getta. La terza, quella con la
 * stella, compare solo quando c'è almeno una carta preferita e sparisce
 * quando si spegne l'ultima stella: una scheda vuota che non si può riempire
 * da lì dentro non serve a niente.
 *
 * Ogni pagina ha la sua lista e il suo adattatore: tenerne una sola e
 * ricaricarla a ogni cambio farebbe vedere le carte sbagliate durante lo
 * scorrimento, quando tutte e due le pagine sono visibili insieme.
 */
class PagineCarte(
    private val suTocco: (Carta) -> Unit,
    private val suOrdineCambiato: (Boolean, IntArray) -> Unit,
    private val suCestino: (Carta) -> Unit,
    private val suErrore: (String) -> Unit,
) : RecyclerView.Adapter<PagineCarte.Pagina>() {

    /** Gli adattatori delle pagine: 0 carte, 1 usa e getta, 2 preferite. */
    private val adattatori = HashMap<Int, CarteAdapter>()

    /** La scheda con la stella si mostra solo se c'è qualcosa dentro. */
    var conPreferite = false
        private set

    /** E la stessa regola vale per l'usa e getta: senza carte, senza scheda. */
    var conUsaEGetta = false
        private set

    /**
     * Le schede che ci sono adesso, nell'ordine in cui si vedono.
     *
     * Tenere qui l'ordine invece di calcolarlo caso per caso evita la trappola
     * di prima: con due schede facoltative le combinazioni sono quattro, e una
     * catena di `if` sbaglia sempre in quella che non si prova.
     */
    private val ordine: List<Int>
        get() = buildList {
            if (conPreferite) add(PREFERITE)
            add(CARTE)
            if (conUsaEGetta) add(USA_E_GETTA)
        }

    companion object {
        const val CARTE = 0
        const val USA_E_GETTA = 1
        const val PREFERITE = 2
    }

    /**
     * Che cosa mostra una posizione adesso.
     *
     * Le preferite stanno per prime, così aprendo l'app si vedono subito le
     * carte che si usano di più. Le posizioni cambiano quando la scheda con la
     * stella compare o sparisce, e per questo nessuno deve ragionare per numero
     * di pagina: si ragiona per tipo.
     */
    fun tipoDi(posizione: Int): Int = ordine.getOrElse(posizione) { CARTE }

    /** Dove sta adesso un tipo di scheda, -1 se non c'è. */
    fun posizioneDi(tipo: Int): Int = ordine.indexOf(tipo)

    inner class Pagina(vista: View) : RecyclerView.ViewHolder(vista) {
        val lista: RecyclerView = vista.findViewById(R.id.lista)
        val vuoto: TextView = vista.findViewById(R.id.vuoto)

        /**
         * Uno solo per pagina. Attaccarne uno nuovo a ogni rebind, senza staccare
         * il vecchio, ne lascia in giro tanti quante sono le ricariche: allora la
         * pressione prolungata prende la carta con più di un helper, uno solo
         * riceve il rilascio, e gli altri lasciano la carta alzata sullo schermo.
         */
        var presa: ItemTouchHelper? = null
    }

    override fun getItemCount() = ordine.size

    /**
     * Da chiamare prima di [ricarica]. Vero se le schede cambiano di numero,
     * cioè se chi guarda si ritroverebbe su una pagina diversa.
     */
    fun mostraSchede(preferite: Boolean, usaEGetta: Boolean): Boolean {
        if (conPreferite == preferite && conUsaEGetta == usaEGetta) {
            return false
        }
        conPreferite = preferite
        conUsaEGetta = usaEGetta
        return true
    }

    override fun onCreateViewHolder(genitore: ViewGroup, tipo: Int): Pagina {
        val vista = LayoutInflater.from(genitore.context)
            .inflate(R.layout.pagina_carte, genitore, false)
        return Pagina(vista)
    }

    override fun onBindViewHolder(pagina: Pagina, posizione: Int) {
        val tipo = tipoDi(posizione)
        val preferite = tipo == PREFERITE
        val usaEGetta = tipo == USA_E_GETTA

        val adattatore = CarteAdapter(
            suTocco = suTocco,
            suOrdineCambiato = { ids -> suOrdineCambiato(usaEGetta, ids) },
            suCestino = suCestino,
        )
        adattatori[posizione] = adattatore

        pagina.lista.layoutManager = LinearLayoutManager(pagina.lista.context)
        pagina.lista.adapter = adattatore

        // Nella scheda con la stella non si trascina: le preferite arrivano dai
        // due gruppi, che hanno due ordini loro, e riordinare qui vorrebbe dire
        // inventarne un terzo che poi nessuno rilegge.
        pagina.presa?.attachToRecyclerView(null)
        pagina.presa = if (preferite) {
            null
        } else {
            ItemTouchHelper(adattatore.trascinamento()).apply {
                attachToRecyclerView(pagina.lista)
            }
        }

        pagina.vuoto.setText(
            when {
                preferite -> R.string.nessuna_preferita
                usaEGetta -> R.string.nessuna_usa_e_getta
                else -> R.string.nessuna_carta
            }
        )

        carica(pagina, tipo, adattatore)
    }

    private fun carica(pagina: Pagina, tipo: Int, adattatore: CarteAdapter) {
        val preferite = tipo == PREFERITE
        val usaEGetta = tipo == USA_E_GETTA

        Dati.chiedi(
            { if (preferite) Core.getPreferite() else Core.getGruppo(usaEGetta) },
            { carte ->
                adattatore.mostra(carte.toList(), cestino = usaEGetta)
                pagina.vuoto.visibility = if (carte.isEmpty()) View.VISIBLE else View.GONE
            },
            { messaggio -> suErrore(messaggio) },
        )
    }

    /** Rilegge tutte e due le pagine: una modifica può spostare una carta di gruppo. */
    fun ricarica() = notifyDataSetChanged()
}
