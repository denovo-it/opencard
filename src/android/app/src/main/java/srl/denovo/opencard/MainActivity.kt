// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.annotation.SuppressLint
import android.view.Menu
import android.view.MenuItem
import android.widget.ImageView
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.view.menu.MenuBuilder
import androidx.viewpager2.widget.ViewPager2
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.google.android.material.snackbar.Snackbar
import com.google.android.material.tabs.TabLayout
import com.google.android.material.tabs.TabLayoutMediator

/**
 * Le carte, divise in schede: quelle di tutti i giorni, le usa e getta e, se
 * ce n'e' almeno una, le preferite sotto la stella.
 *
 * Tocco su una carta: la apre. Pressione prolungata: la trascina su o giu' e
 * prende il posto di quella che scavalca.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var pagine: ViewPager2
    private lateinit var carte: PagineCarte
    private lateinit var schede: TabLayout

    /** Scheda aperta: vero se e' quella delle usa e getta. */
    private val usaEGetta: Boolean
        get() = carte.tipoDi(pagine.currentItem) == PagineCarte.USA_E_GETTA

    /**
     * Vero fino alla prima ricarica dopo l'apertura dell'app.
     *
     * Serve a distinguere l'avvio dal ritorno da un'altra schermata: all'avvio
     * si sceglie la scheda da mostrare, tornando indietro si resta dov'era
     * l'utente. Girando il telefono l'activity si ricrea ma lo stato c'e',
     * quindi non e' un'apertura e la scheda non si sposta.
     */
    private var primaApertura = true

    private val apriForm = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { esito ->
        if (esito.resultCode != Activity.RESULT_OK) return@registerForActivityResult
        ricarica()
        // Solo il passaggio delle carte fra due telefoni torna con un numero:
        // le altre schermate non mettono l'extra e il conteggio resta a zero.
        val ricevute = esito.data?.getIntExtra(TrasferimentoActivity.EXTRA_RICEVUTE, 0) ?: 0
        if (ricevute > 0) {
            avvisa(resources.getQuantityString(R.plurals.carte_ricevute, ricevute, ricevute))
        }
    }

    private val salvaBackup = registerForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { destinazione ->
        if (destinazione != null) scriviBackup(destinazione) else avvisa(getString(R.string.backup_annullato))
    }

    private val scegliBackup = registerForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { sorgente -> if (sorgente != null) confermaRipristino(sorgente) }

    override fun onCreate(statoSalvato: Bundle?) {
        super.onCreate(statoSalvato)
        primaApertura = statoSalvato == null
        setContentView(R.layout.activity_main)
        setSupportActionBar(findViewById(R.id.barra))
        supportActionBar?.apply {
            // Il titolo e' il marchio, messo dentro la barra nel layout.
            setDisplayShowTitleEnabled(false)
            // A sinistra le informazioni, dove di solito c'e' il "torna indietro":
            // dalla lista non si torna da nessuna parte, quindi il posto e' libero.
            setDisplayHomeAsUpEnabled(true)
            setHomeAsUpIndicator(R.drawable.ic_info)
        }

        // La pastiglia del canale non sta piu' nella barra: il canale si legge
        // nelle informazioni e nella schermata di avvio, e in cima resta il
        // solo logo, centrato.

        pagine = findViewById(R.id.pagine)
        schede = findViewById(R.id.schede)

        carte = PagineCarte(
            suTocco = { carta -> apri(DettaglioActivity.intent(this, carta.id)) },
            suOrdineCambiato = { gruppo, ids -> salvaOrdine(gruppo, ids) },
            suCestino = { carta -> confermaEliminazione(carta) },
            suErrore = { messaggio -> avvisa(messaggio) },
        )
        pagine.adapter = carte

        // Le schede e lo scorrimento comandano la stessa cosa: toccando una
        // scheda la pagina scorre, scorrendo la pagina la scheda si sposta.
        TabLayoutMediator(schede, pagine) { scheda, posizione ->
            when (carte.tipoDi(posizione)) {
                // Una stella e basta: dice da se' cosa contiene, e una parola in
                // piu' stringerebbe le altre due.
                //
                // Va messa come vista propria e non con setIcon(): in una fila
                // dove le altre schede hanno del testo, l'icona da sola resta
                // schiacciata in basso e si vede a meta'. La tinta e' quella
                // del testo, cosi' la stella si accende quando la scheda e'
                // scelta e si smorza quando non lo e'.
                PagineCarte.PREFERITE -> scheda.customView = ImageView(this).apply {
                    setImageResource(R.drawable.ic_stella_piena)
                    imageTintList = schede.tabTextColors
                    contentDescription = getString(R.string.scheda_preferite)
                }
                PagineCarte.USA_E_GETTA -> scheda.setText(R.string.scheda_usa_e_getta)
                else -> scheda.setText(R.string.scheda_carte)
            }
        }.attach()

        findViewById<FloatingActionButton>(R.id.aggiungi).setOnClickListener {
            // La casella "usa e getta" parte come la scheda da cui hai premuto il +.
            apri(FormActivity.intentNuova(this, usaEGetta))
        }

        // Il back sulla lista non chiude di colpo: chiede conferma.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = chiediUscita { finish() }
        })
    }

    override fun onResume() {
        super.onResume()
        Dati.erroreDiApertura?.let { avvisa(it) }
        mostraUltimoErrore()
        ricarica()
    }

    /**
     * Se l'avvio precedente si e' chiuso male, lo dice e propone di mandare il
     * dettaglio: e' l'unico modo per sapere cosa e' successo senza collegare il
     * telefono a un computer.
     */
    private fun mostraUltimoErrore() {
        val errore = Diagnostica.ultimoErrore(this) ?: return
        AlertDialog.Builder(this)
            .setTitle(R.string.errore_precedente_titolo)
            .setMessage(getString(R.string.errore_precedente, errore.take(1500)))
            .setNegativeButton(R.string.chiudi) { _, _ -> Diagnostica.dimentica(this) }
            .setPositiveButton(R.string.condividi) { _, _ ->
                val invio = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_SUBJECT, "OpenCard: errore")
                    putExtra(Intent.EXTRA_TEXT, errore)
                }
                startActivity(Intent.createChooser(invio, getString(R.string.condividi)))
                Diagnostica.dimentica(this)
            }
            .show()
    }

    private fun apri(intento: Intent) = apriForm.launch(intento)

    /**
     * Ricarica le liste e decide se la scheda con la stella ci deve essere.
     *
     * Quando la scheda compare o sparisce le altre si spostano di posto: chi
     * stava guardando una scheda deve restare su quella, non trovarsi
     * all'improvviso su un'altra. Per questo ci si segna il tipo prima e si
     * ritorna li' dopo.
     */
    private fun ricarica() {
        Dati.chiedi(
            { Core.getPreferite().isNotEmpty() },
            { ce ->
                val guardava = carte.tipoDi(pagine.currentItem)
                if (carte.mostraPreferite(ce)) {
                    // Prima si torna a una posizione che esiste anche dopo, poi
                    // si cambia il numero di schede.
                    pagine.setCurrentItem(0, false)
                    carte.ricarica()
                    val dove = carte.posizioneDi(guardava)
                    if (dove > 0) pagine.setCurrentItem(dove, false)
                } else {
                    carte.ricarica()
                }
                apriSullaStella(ce)
            },
            {
                // Se la lettura fallisce lo dice gia' la pagina che si ricarica:
                // qui si lascia le schede come stanno e si va avanti.
                carte.ricarica()
                primaApertura = false
            },
        )
    }

    /**
     * All'apertura si parte dalla stella, quando c'e'.
     *
     * Sono le carte che si usano di piu': se la scheda esiste e' quella che
     * serve per prima, e senza questo si aprirebbe sempre su "Carte", perche'
     * la scheda con la stella compare solo dopo la prima lettura, quando la
     * pagina scelta e' gia' quella di partenza.
     */
    private fun apriSullaStella(cePreferite: Boolean) {
        if (!primaApertura) return
        primaApertura = false
        if (!cePreferite) return
        val dove = carte.posizioneDi(PagineCarte.PREFERITE)
        if (dove >= 0) pagine.setCurrentItem(dove, false)
    }

    private fun salvaOrdine(gruppo: Boolean, ids: IntArray) {
        Dati.fai({ Core.reorder(gruppo, ids) }, {}, { avvisa(it) })
    }

    private fun confermaEliminazione(carta: Carta) {
        AlertDialog.Builder(this)
            .setTitle(R.string.elimina_titolo)
            .setMessage(getString(R.string.elimina_domanda, carta.label))
            .setNegativeButton(R.string.annulla, null)
            .setPositiveButton(R.string.elimina) { _, _ ->
                Dati.fai({ Core.delete(carta.id) }, { ricarica() }, { avvisa(it) })
            }
            .show()
    }

    /** Condiviso dal tasto indietro e dall'icona di uscita. */
    private fun chiediUscita(esci: () -> Unit) {
        AlertDialog.Builder(this)
            .setTitle(R.string.esci_titolo)
            .setMessage(R.string.esci_domanda)
            .setNegativeButton(R.string.annulla, null)
            .setPositiveButton(R.string.esci) { _, _ -> esci() }
            .show()
    }

    @SuppressLint("RestrictedApi")
    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.principale, menu)
        // Nei menu a tendina Android nasconde le icone: qui servono, perche'
        // esporta e importa si distinguono a colpo d'occhio dal verso freccia.
        (menu as? MenuBuilder)?.setOptionalIconsVisible(true)
        return true
    }

    override fun onOptionsItemSelected(voce: MenuItem): Boolean = when (voce.itemId) {
        R.id.esporta -> {
            esporta()
            true
        }
        R.id.ripristina -> {
            // Nessun filtro sull'estensione: i provider di archiviazione espongono
            // i file senza un tipo affidabile, e un filtro li nasconderebbe.
            scegliBackup.launch(arrayOf("*/*"))
            true
        }
        R.id.trasferisci -> {
            apri(TrasferimentoActivity.intent(this))
            true
        }
        R.id.esci -> {
            chiediUscita { finishAffinity() }
            true
        }
        else -> super.onOptionsItemSelected(voce)
    }

    /** L'icona a sinistra nella barra apre le informazioni. */
    override fun onSupportNavigateUp(): Boolean {
        startActivity(Intent(this, InfoActivity::class.java))
        return true
    }

    private fun esporta() {
        Dati.chiedi(
            { Core.getAll().size },
            { quante ->
                if (quante == 0) {
                    avvisa(getString(R.string.niente_da_esportare))
                } else {
                    salvaBackup.launch(Core.backupNome(Core.oggi()))
                }
            },
            { avvisa(it) },
        )
    }

    private fun scriviBackup(destinazione: Uri) {
        Dati.chiedi(
            { Core.backupEsporta(Core.adesso()) },
            { testo ->
                try {
                    contentResolver.openOutputStream(destinazione)?.use {
                        it.write(testo.toByteArray())
                    } ?: return@chiedi avvisa(getString(R.string.backup_non_scritto))
                    avvisa(getString(R.string.backup_salvato))
                } catch (e: Exception) {
                    avvisa(getString(R.string.backup_non_scritto))
                }
            },
            { avvisa(it) },
        )
    }

    private fun confermaRipristino(sorgente: Uri) {
        AlertDialog.Builder(this)
            .setTitle(R.string.ripristina_titolo)
            .setMessage(R.string.ripristina_avviso)
            .setNegativeButton(R.string.annulla, null)
            .setPositiveButton(R.string.ripristina_conferma) { _, _ -> ripristina(sorgente) }
            .show()
    }

    private fun ripristina(sorgente: Uri) {
        // Lettura e ripristino insieme sul thread dei dati: il file puo' stare
        // su un provider lento (Drive) e sul thread dell'interfaccia sarebbe
        // un ANR. Il tetto tiene fuori il file sbagliato scelto per errore: un
        // backup vero pesa qualche decina di kilobyte.
        Dati.chiedi(
            {
                val dati = try {
                    contentResolver.openInputStream(sorgente)?.use { leggiConTetto(it) }
                } catch (e: OpenCardException) {
                    throw e
                } catch (e: Exception) {
                    null
                } ?: throw OpenCardException(getString(R.string.backup_non_letto))
                Core.backupRipristina(dati)
            },
            { quante ->
                ricarica()
                avvisa(resources.getQuantityString(R.plurals.carte_ripristinate, quante, quante))
            },
            { avvisa(it) },
        )
    }

    /** Legge tutto il flusso, ma si ferma se supera i dieci megabyte. */
    private fun leggiConTetto(flusso: java.io.InputStream): ByteArray {
        val tetto = 10 * 1024 * 1024
        val raccolta = java.io.ByteArrayOutputStream()
        val blocco = ByteArray(64 * 1024)
        while (true) {
            val letti = flusso.read(blocco)
            if (letti < 0) return raccolta.toByteArray()
            raccolta.write(blocco, 0, letti)
            if (raccolta.size() > tetto) {
                throw OpenCardException(getString(R.string.backup_troppo_grande))
            }
        }
    }

    private fun avvisa(messaggio: String) {
        Snackbar.make(findViewById(R.id.radice), messaggio, Snackbar.LENGTH_LONG).show()
    }
}
