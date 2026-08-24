// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
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
    private fun tinta(carta: Carta) {
        val colore = coloreCarta(carta.colore)
        findViewById<AppBarLayout>(R.id.intestazione).setBackgroundColor(colore)
        findViewById<MaterialToolbar>(R.id.barra).setBackgroundColor(colore)
    }

    private fun disegna(carta: Carta) {
        Dati.chiedi(
            { Core.renderCode(carta.code, carta.isQrcode) },
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
