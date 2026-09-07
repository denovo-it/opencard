// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import com.google.android.material.appbar.AppBarLayout
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.snackbar.Snackbar

/**
 * La carta a schermo intero, davanti al lettore della cassa.
 *
 * Lo schermo va al massimo della luminosità finché la schermata è aperta:
 * i lettori laser e le fotocamere delle casse leggono male uno schermo scuro.
 * Si tocca solo la finestra di questa schermata, non l'impostazione di sistema,
 * quindi uscendo torna tutto com'era senza dover rimettere niente a posto.
 */
class DettaglioActivity : AppCompatActivity() {

    private var id = 0
    private var carta: Carta? = null

    /** La voce della barra, per cambiarle icona quando la stella si accende. */
    private var vocePreferita: MenuItem? = null

    /**
     * La modifica torna qui, e se la carta è stata cancellata da lì questa
     * schermata non ha più niente da mostrare: si chiude e si torna all'elenco.
     */
    private val apriModifica = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { esito ->
        if (esito.data?.getBooleanExtra(FormActivity.EXTRA_ELIMINATA, false) == true) {
            finish()
        }
    }

    companion object {
        private const val EXTRA_ID = "id"

        fun intent(contesto: Context, id: Int) =
            Intent(contesto, DettaglioActivity::class.java).putExtra(EXTRA_ID, id)
    }

    override fun onCreate(statoSalvato: Bundle?) {
        super.onCreate(statoSalvato)
        setContentView(R.layout.activity_dettaglio)
        setSupportActionBar(findViewById(R.id.barra))
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        // Il nome lo scrive la vista dentro la barra, non il titolo di serie.
        // L'`title` dell'activity resta quello della carta: è quello che legge
        // chi usa il lettore di schermo.
        supportActionBar?.setDisplayShowTitleEnabled(false)

        id = intent.getIntExtra(EXTRA_ID, 0)
        alMassimoLaLuminosita()
    }

    override fun onResume() {
        super.onResume()
        carica()
    }

    private fun alMassimoLaLuminosita() {
        val parametri = window.attributes
        parametri.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
        window.attributes = parametri
    }

    private fun carica() {
        Dati.chiedi(
            { Core.get(id) },
            { trovata ->
                carta = trovata
                title = trovata.label
                findViewById<TextView>(R.id.titolo).text = trovata.label
                disegnaStella()
                findViewById<TextView>(R.id.codice).text = Core.groupedCode(trovata.code)
                mostraDettagli(trovata)
                tinta(trovata)
                disegna(trovata)
            },
            { messaggio ->
                Snackbar.make(findViewById(R.id.radice), messaggio, Snackbar.LENGTH_LONG).show()
            },
        )
    }

    /**
     * La banda in alto prende il colore della carta aperta.
     *
     * Vanno colorate tutte e due: la barra ha un fondo suo che arriva dallo stile
     * comune, e sotto la barra di sistema si vede l'AppBarLayout, perché è lui
     * a coprire lo spazio del margine alto.
     */
    /**
     * Nota, scadenza e saldo, uno per riga e solo se ci sono. Il riquadro
     * sparisce del tutto quando sono tutti vuoti: una carta senza questi campi
     * deve restare quella di prima.
     */
    private fun mostraDettagli(carta: Carta) {
        val righe = mutableListOf<String>()

        if (carta.saldo.isNotEmpty()) {
            righe += getString(R.string.saldo) + ": " + carta.saldo
        }
        if (carta.scadenza.isNotEmpty()) {
            righe += getString(R.string.scadenza) + ": " + carta.scadenza
        }
        if (carta.note.isNotEmpty()) {
            righe += carta.note
        }

        val vista = findViewById<TextView>(R.id.dettagli)
        vista.text = righe.joinToString("\n")
        vista.visibility = if (righe.isEmpty()) View.GONE else View.VISIBLE

        mostraFoto(carta)
    }

    /** Il richiamo del pager, tenuto per poterlo togliere alla ricarica. */
    private var cambioPagina: ViewPager2.OnPageChangeCallback? = null

    /**
     * Quale faccia si sta guardando.
     *
     * La schermata si ricarica ogni volta che torna in primo piano, anche solo
     * tornando indietro dalla foto a schermo pieno, e rimettere l'adapter
     * riporta il pager alla prima pagina: senza questa, chi ingrandiva il retro
     * si ritrovava il fronte.
     */
    private var facciaMostrata = 0

    /**
     * Le foto della carta, una per pagina: si passa da fronte a retro
     * scorrendo di lato. Se ce n'e' una sola non c'e' niente da scorrere e
     * l'etichetta lo dice lo stesso; se non ce n'e' nessuna sparisce tutto.
     */
    private fun mostraFoto(carta: Carta) {
        val facce = mutableListOf<Faccia>()
        Foto.leggi(this, carta.fotoFronte)?.let {
            facce += Faccia(it, R.string.foto_fronte, carta.fotoFronte)
        }
        Foto.leggi(this, carta.fotoRetro)?.let {
            facce += Faccia(it, R.string.foto_retro, carta.fotoRetro)
        }

        val pagine = findViewById<ViewPager2>(R.id.foto)
        val riga = findViewById<View>(R.id.riga_foto)
        val etichetta = findViewById<TextView>(R.id.foto_lato)
        val indietro = findViewById<ImageButton>(R.id.foto_indietro)
        val avanti = findViewById<ImageButton>(R.id.foto_avanti)
        if (facce.isEmpty()) {
            pagine.visibility = View.GONE
            riga.visibility = View.GONE
            return
        }

        val voluta = facciaMostrata.coerceIn(0, facce.size - 1)
        pagine.adapter = FacceAdapter(facce)
        pagine.visibility = View.VISIBLE
        riga.visibility = View.VISIBLE
        etichetta.text = getString(facce[0].etichetta)

        // Con una foto sola non c'e' niente da girare: le frecce sparirebbero
        // comunque appena premute, tanto vale non mostrarle.
        val dueFacce = facce.size > 1
        indietro.visibility = if (dueFacce) View.VISIBLE else View.GONE
        avanti.visibility = if (dueFacce) View.VISIBLE else View.GONE
        indietro.setOnClickListener { pagine.currentItem = pagine.currentItem - 1 }
        avanti.setOnClickListener { pagine.currentItem = pagine.currentItem + 1 }
        aggiornaFrecce(indietro, avanti, 0, facce.size)
        // La schermata si ricarica quando si torna dalla modifica: senza
        // togliere quello di prima, i richiami si accumulerebbero uno per giro.
        cambioPagina?.let { pagine.unregisterOnPageChangeCallback(it) }
        cambioPagina = object : ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(quale: Int) {
                facciaMostrata = quale
                etichetta.text = getString(facce[quale].etichetta)
                aggiornaFrecce(indietro, avanti, quale, facce.size)
            }
        }
        pagine.registerOnPageChangeCallback(cambioPagina!!)
        // Senza animazione: la schermata si sta ricostruendo, e vedere le
        // pagine scorrere da sole sembrerebbe un tocco che non c'e' stato.
        pagine.setCurrentItem(voluta, false)
    }

    /**
     * La freccia che porta fuori dalle pagine si spegne invece di sparire: se
     * sparisse, l'altra si sposterebbe al centro a ogni giro e l'occhio la
     * perderebbe.
     */
    private fun aggiornaFrecce(indietro: ImageButton, avanti: ImageButton, quale: Int, quante: Int) {
        indietro.isEnabled = quale > 0
        avanti.isEnabled = quale < quante - 1
        indietro.alpha = if (indietro.isEnabled) 1f else 0.3f
        avanti.alpha = if (avanti.isEnabled) 1f else 0.3f
    }

    /** Una faccia della carta: l'immagine da mostrare e il file da riaprire grande. */
    private class Faccia(val immagine: Bitmap, val etichetta: Int, val file: String)

    /** Una foto per pagina. Toccandola si apre a schermo pieno. */
    private class FacceAdapter(
        private val facce: List<Faccia>,
    ) : RecyclerView.Adapter<FacceAdapter.Riquadro>() {

        class Riquadro(val vista: ImageView) : RecyclerView.ViewHolder(vista)

        override fun onCreateViewHolder(genitore: ViewGroup, tipo: Int): Riquadro {
            val vista = ImageView(genitore.context).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
                scaleType = ImageView.ScaleType.FIT_CENTER
            }
            return Riquadro(vista)
        }

        override fun onBindViewHolder(riquadro: Riquadro, posizione: Int) {
            val faccia = facce[posizione]
            riquadro.vista.setImageBitmap(faccia.immagine)
            riquadro.vista.contentDescription =
                riquadro.vista.context.getString(faccia.etichetta)
            riquadro.vista.setOnClickListener { vista ->
                FotoActivity.apri(vista.context, faccia.file, faccia.etichetta)
            }
        }

        override fun getItemCount() = facce.size
    }

    private fun tinta(carta: Carta) {
        val colore = coloreCarta(carta.colore)
        findViewById<AppBarLayout>(R.id.intestazione).setBackgroundColor(colore)
        findViewById<MaterialToolbar>(R.id.barra).setBackgroundColor(colore)
    }

    private fun disegna(carta: Carta) {
        Dati.chiedi(
            // Con la simbologia scelta, non con quella indovinata: una carta
            // Aztec disegnata a indovinare tornerebbe un Code 128.
            { Core.renderCodeSimbologia(carta.code, carta.simbologia) },
            { immagine -> findViewById<ImageView>(R.id.immagine).setImageBitmap(immagine.aBitmap()) },
            { messaggio ->
                Snackbar.make(findViewById(R.id.radice), messaggio, Snackbar.LENGTH_LONG).show()
            },
        )
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.dettaglio, menu)
        vocePreferita = menu.findItem(R.id.preferita)
        disegnaStella()
        return true
    }

    /**
     * Stella vuota se la carta non è preferita, piena se lo è.
     *
     * Si chiama sia quando arriva la carta sia quando il menu viene creato:
     * chi dei due arriva per ultimo trova l'altro pronto, e l'ordine fra
     * lettura dal file e creazione del menu non è garantito.
     */
    private fun disegnaStella() {
        val preferita = carta?.preferita ?: false
        vocePreferita?.apply {
            setIcon(if (preferita) R.drawable.ic_stella_piena else R.drawable.ic_stella_vuota)
            setTitle(if (preferita) R.string.togli_preferita else R.string.preferita)
        }
    }

    /**
     * Accende o spegne la stella.
     *
     * Il risultato torna alla lista, che deve ricaricarsi: la scheda con la
     * stella compare quando arriva la prima preferita e sparisce quando si
     * spegne l'ultima.
     */
    private fun cambiaStella() {
        val attuale = carta ?: return
        val nuova = !attuale.preferita

        Dati.fai(
            { Core.setPreferita(attuale.id, nuova) },
            {
                carta = attuale.copy(preferita = nuova)
                disegnaStella()
                setResult(Activity.RESULT_OK)
                Snackbar.make(
                    findViewById(R.id.radice),
                    getString(if (nuova) R.string.aggiunta_preferite else R.string.tolta_preferite),
                    Snackbar.LENGTH_SHORT,
                ).show()
            },
            { messaggio ->
                Snackbar.make(findViewById(R.id.radice), messaggio, Snackbar.LENGTH_LONG).show()
            },
        )
    }

    override fun onOptionsItemSelected(voce: MenuItem): Boolean = when (voce.itemId) {
        android.R.id.home -> {
            finish()
            true
        }
        R.id.preferita -> {
            cambiaStella()
            true
        }
        R.id.modifica -> {
            carta?.let {
                apriModifica.launch(FormActivity.intentModifica(this, it.id))
                setResult(Activity.RESULT_OK)
            }
            true
        }
        else -> super.onOptionsItemSelected(voce)
    }
}
