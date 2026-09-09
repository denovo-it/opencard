// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.annotation.SuppressLint
import android.text.InputType
import android.view.Menu
import android.view.View
import android.view.MenuItem
import android.widget.EditText
import android.widget.FrameLayout
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
 * ce n'è almeno una, le preferite sotto la stella.
 *
 * Tocco su una carta: la apre. Pressione prolungata: la trascina su o giù e
 * prende il posto di quella che scavalca.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var pagine: ViewPager2
    private lateinit var carte: PagineCarte
    private lateinit var schede: TabLayout

    /** Scheda aperta: vero se è quella delle usa e getta. */
    private val usaEGetta: Boolean
        get() = carte.tipoDi(pagine.currentItem) == PagineCarte.USA_E_GETTA

    /**
     * Vero fino alla prima ricarica dopo l'apertura dell'app.
     *
     * Serve a distinguere l'avvio dal ritorno da un'altra schermata: all'avvio
     * si sceglie la scheda da mostrare, tornando indietro si resta dov'era
     * l'utente. Girando il telefono l'activity si ricrea ma lo stato c'è,
     * quindi non è un'apertura e la scheda non si sposta.
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

    /** Il file cifrato non e' JSON: si salva col suo tipo e la sua estensione. */
    private val salvaBackupCifrato = registerForActivityResult(
        ActivityResultContracts.CreateDocument("application/octet-stream")
    ) { destinazione ->
        if (destinazione != null) scriviBackup(destinazione) else avvisa(getString(R.string.backup_annullato))
    }

    private val scegliBackup = registerForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { sorgente -> if (sorgente != null) confermaRipristino(sorgente) }

    /** La password scelta per l'esportazione in corso. Vuota vuol dire in chiaro. */
    private var passwordBackup = ""

    /** Vero se l'esportazione in corso è in CSV invece che in archivio. */
    private var esportaCsv = false

    /**
     * Archivio o CSV.
     *
     * L'archivio è il modo di casa e porta tutto, foto comprese. Il CSV serve
     * per uscire: è il formato che leggono le altre app, e chi esporta per
     * andarsene deve poterlo fare senza chiedere il permesso a nessuno. Nel
     * CSV non ci stanno le foto, e la domanda lo dice.
     */
    private fun chiediFormato(poi: (Boolean) -> Unit) {
        val scelte = arrayOf(
            getString(R.string.esporta_archivio),
            getString(R.string.esporta_csv),
        )
        AlertDialog.Builder(this)
            .setTitle(R.string.esporta_come)
            .setItems(scelte) { _, quale -> poi(quale == 1) }
            .setNegativeButton(R.string.annulla, null)
            .show()
    }

    /**
     * Chiede una password, o la conferma di non metterne.
     *
     * Si usa in tutti e due i sensi: quando si esporta, dove lasciare vuoto e'
     * legittimo e vuol dire file leggibile; e quando si apre un file cifrato,
     * dove vuoto non va bene.
     */
    private fun chiediPassword(
        titolo: Int,
        spiega: Int,
        vuotoAmmesso: Boolean,
        bottone: Int,
        poi: (String) -> Unit,
    ) {
        val campo = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            hint = getString(R.string.password)
        }
        val riquadro = FrameLayout(this).apply {
            val bordo = (24 * resources.displayMetrics.density).toInt()
            setPadding(bordo, bordo / 2, bordo, 0)
            addView(campo)
        }
        AlertDialog.Builder(this)
            .setTitle(titolo)
            .setMessage(spiega)
            .setView(riquadro)
            .setNegativeButton(R.string.annulla, null)
            .apply {
                if (vuotoAmmesso) {
                    setNeutralButton(R.string.senza_password) { _, _ -> poi("") }
                }
            }
            .setPositiveButton(bottone) { _, _ ->
                val scritta = campo.text.toString()
                if (scritta.isEmpty() && !vuotoAmmesso) {
                    avvisa(getString(R.string.password_apri_spiega))
                } else {
                    poi(scritta)
                }
            }
            .show()
    }

    override fun onCreate(statoSalvato: Bundle?) {
        super.onCreate(statoSalvato)
        primaApertura = statoSalvato == null
        setContentView(R.layout.activity_main)
        setSupportActionBar(findViewById(R.id.barra))
        supportActionBar?.apply {
            // Il titolo è il marchio, messo dentro la barra nel layout.
            setDisplayShowTitleEnabled(false)
            // A sinistra le informazioni, dove di solito c'è il "torna indietro":
            // dalla lista non si torna da nessuna parte, quindi il posto è libero.
            setDisplayHomeAsUpEnabled(true)
            setHomeAsUpIndicator(R.drawable.ic_info)
        }

        // La pastiglia del canale non sta più nella barra: il canale si legge
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
                // Una stella e basta: dice da sé cosa contiene, e una parola in
                // più stringerebbe le altre due.
                //
                // Va messa come vista propria e non con setIcon(): in una fila
                // dove le altre schede hanno del testo, l'icona da sola resta
                // schiacciata in basso e si vede a metà. La tinta è quella
                // del testo, così la stella si accende quando la scheda è
                // scelta e si smorza quando non lo è.
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
     * Se l'avvio precedente si è chiuso male, lo dice e propone di mandare il
     * dettaglio: è l'unico modo per sapere cosa è successo senza collegare il
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

    /**
     * La lingua dell'app, scelta a mano.
     *
     * Di serie la decide il telefono, ed e' quello che vuole quasi tutti. Ma
     * chi ha il telefono in una lingua e preferisce l'app in un'altra, o chi
     * vuole leggere l'inglese pur avendo il telefono in italiano, da qui puo'
     * farlo senza cambiare le impostazioni di sistema.
     *
     * Se la sceglie AppCompat, che da Android 13 in su la passa al sistema e
     * prima se la ricorda da sola: in tutti e due i casi resta dopo il
     * riavvio, e le schermate si ridisegnano subito.
     *
     * In elenco ci sono le sigle, IT e EN, e non si traducono: due lettere si
     * riconoscono anche se l'app sta parlando una lingua che non si capisce,
     * che e' esattamente il momento in cui questo menu serve.
     */
    private fun apri(intento: Intent) = apriForm.launch(intento)

    /**
     * Ricarica le liste e decide quali schede facoltative ci devono essere.
     *
     * Sono due, la stella e l'usa e getta, e valgono la stessa regola: senza
     * carte dentro, la scheda non si mostra. Una scheda vuota occupa spazio in
     * cima allo schermo e non serve a niente.
     *
     * Quando una scheda compare o sparisce le altre si spostano di posto: chi
     * stava guardando una scheda deve restare su quella, non trovarsi
     * all'improvviso su un'altra. Per questo ci si segna il tipo prima e si
     * ritorna lì dopo.
     */
    private fun ricarica() {
        Dati.chiedi(
            { Core.getPreferite().isNotEmpty() to Core.getGruppo(true).isNotEmpty() },
            { (ce, ceUsaEGetta) ->
                val guardava = carte.tipoDi(pagine.currentItem)
                if (carte.mostraSchede(ce, ceUsaEGetta)) {
                    // Prima si torna a una posizione che esiste anche dopo, poi
                    // si cambia il numero di schede.
                    pagine.setCurrentItem(0, false)
                    carte.ricarica()
                    val dove = carte.posizioneDi(guardava)
                    if (dove > 0) pagine.setCurrentItem(dove, false)
                } else {
                    carte.ricarica()
                }
                // Una scheda sola non e' una scheda: non c'e' niente fra cui
                // scegliere, e la fila in cima allo schermo diventa un
                // ornamento. Sparisce, e con essa la barra all'apertura di chi
                // non ha ancora nessuna carta.
                schede.visibility = if (carte.itemCount > 1) View.VISIBLE else View.GONE
                apriSullaStella(ce)
            },
            {
                // Se la lettura fallisce lo dice già la pagina che si ricarica:
                // qui si lascia le schede come stanno e si va avanti.
                carte.ricarica()
                primaApertura = false
            },
        )
    }

    /**
     * All'apertura si parte dalla stella, quando c'è.
     *
     * Sono le carte che si usano di più: se la scheda esiste è quella che
     * serve per prima, e senza questo si aprirebbe sempre su "Carte", perché
     * la scheda con la stella compare solo dopo la prima lettura, quando la
     * pagina scelta è già quella di partenza.
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
                Dati.fai(
                    { Core.delete(carta.id) },
                    { ricarica(); WidgetCarta.aggiornaTutti(this) },
                    { avvisa(it) },
                )
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
        // Nei menu a tendina Android nasconde le icone: qui servono, perché
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
        R.id.impostazioni -> {
            startActivity(Intent(this, ImpostazioniActivity::class.java))
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
                    chiediFormato { csv ->
                    esportaCsv = csv
                    chiediPassword(
                        R.string.password_esporta_titolo,
                        R.string.password_esporta_spiega,
                        vuotoAmmesso = true,
                        bottone = R.string.salva,
                    ) { password ->
                        passwordBackup = password
                        val nome = Core.backupNome(Core.oggi()).removeSuffix(".json")
                        // Un archivio si chiama .zip, e uno chiuso con la
                        // password .opencard: l'estensione deve dire cosa
                        // trova chi apre il file, non cosa c'e' dentro.
                        if (password.isEmpty()) {
                            salvaBackupCifrato.launch(nome + if (csv) ".csv" else ".zip")
                        } else {
                            salvaBackupCifrato.launch("$nome.opencard")
                        }
                    }
                    }
                }
            },
            { avvisa(it) },
        )
    }

    private fun scriviBackup(destinazione: Uri) {
        val password = passwordBackup
        Dati.chiedi(
            {
                // Dentro l'archivio vanno l'elenco e le foto. La password
                // chiude l'archivio intero: lo zip da solo cifra male, e le
                // foto resterebbero in chiaro.
                val contenuto = if (esportaCsv) {
                    Csv.scrivi(Core.getAll())
                } else {
                    Archivio.scrivi(
                        this,
                        Core.backupEsporta(Core.adesso()).toByteArray(),
                        Core.getAll(),
                    )
                }
                if (password.isEmpty()) contenuto else Core.backupCifra(contenuto, password)
            },
            { byte ->
                try {
                    contentResolver.openOutputStream(destinazione)?.use {
                        it.write(byte)
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
        Dati.chiedi(
            { Core.getAll().isEmpty() },
            { vuoto ->
                // Con zero carte non c'e' niente da sostituire: la domanda
                // sarebbe solo un passaggio in piu' prima di una cosa che non
                // toglie nulla a nessuno.
                if (vuoto) {
                    ripristina(sorgente)
                } else {
                    AlertDialog.Builder(this)
                        .setTitle(R.string.ripristina_titolo)
                        .setMessage(R.string.ripristina_avviso)
                        .setNegativeButton(R.string.annulla, null)
                        .setPositiveButton(R.string.ripristina_conferma) { _, _ -> ripristina(sorgente) }
                        .show()
                }
            },
            { avvisa(it) },
        )
    }

    private fun ripristina(sorgente: Uri) {
        // Lettura e ripristino insieme sul thread dei dati: il file può stare
        // su un provider lento (Drive) e sul thread dell'interfaccia sarebbe
        // un ANR. Il tetto tiene fuori il file sbagliato scelto per errore: un
        // backup vero pesa qualche decina di kilobyte.
        Dati.chiedi(
            {
                try {
                    contentResolver.openInputStream(sorgente)?.use { leggiConTetto(it) }
                } catch (e: OpenCardException) {
                    throw e
                } catch (e: Exception) {
                    null
                } ?: throw OpenCardException(getString(R.string.backup_non_letto))
            },
            { dati ->
                // La password si chiede solo se il file ce l'ha: chi non l'ha
                // mai usata non vede niente di nuovo.
                if (Core.backupCifrato(dati)) {
                    chiediPassword(
                        R.string.password_apri_titolo,
                        R.string.password_apri_spiega,
                        vuotoAmmesso = false,
                        // Qui non si salva niente: si apre un file che c'e' gia'.
                        bottone = R.string.apri,
                    ) { password -> scriviLeCarte(dati, password) }
                } else {
                    scriviLeCarte(dati, "")
                }
            },
            { avvisa(it) },
        )
    }

    /** Le carte di un CSV entrano una per una, con i campi che portano. */
    private fun aggiungiDaCsv(carte: List<Csv.Letta>): Int {
        for (carta in carte) {
            val id = Core.insert(
                carta.label,
                carta.code,
                Simbologie.eQuadrato(carta.simbologia),
                carta.colore,
                false,
            )
            Core.setSimbologia(id, carta.simbologia)
            Core.setDettagli(id, carta.note, carta.scadenza, carta.saldo)
            if (carta.preferita) {
                Core.setPreferita(id, true)
            }
        }
        return carte.size
    }

    private fun scriviLeCarte(dati: ByteArray, password: String) {
        Dati.chiedi(
            {
                // Tre forme, in ordine di quanto sono recenti: archivio chiuso
                // con la password, archivio in chiaro, e il solo JSON dei
                // backup fatti prima delle foto.
                val aperto = if (password.isEmpty()) dati else Core.backupDecifra(dati, password)
                when {
                    Archivio.eArchivio(aperto) -> {
                        val elenco = Archivio.leggi(this, aperto)
                            ?: throw OpenCardException(getString(R.string.backup_non_letto))
                        Core.backupRipristina(elenco)
                    }
                    // Il CSV non sostituisce: si aggiunge in fondo. Chi arriva
                    // da un'altra app di solito ha gia' qualcosa qui dentro, e
                    // cancellarglielo sarebbe un modo brutto di dare il benvenuto.
                    Csv.eCsv(aperto) -> aggiungiDaCsv(Csv.leggi(aperto))
                    else -> Core.backupRipristinaFile(aperto, "")
                }
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
