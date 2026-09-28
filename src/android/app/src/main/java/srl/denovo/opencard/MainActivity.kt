// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.os.Bundle
import android.annotation.SuppressLint
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.Menu
import android.view.View
import android.view.MenuItem
import android.view.inputmethod.InputMethodManager
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
import com.google.android.material.textfield.TextInputLayout

/**
 * Le carte, divise in schede: quelle di tutti i giorni, le usa e getta e, se
 * ce n'è almeno una, le preferite sotto la stella.
 *
 * Tocco su una carta: la apre. Pressione prolungata: la trascina su o giù e
 * prende il posto di quella che scavalca.
 */
class MainActivity : AppCompatActivity() {

    companion object {
        /**
         * Il campo di ricerca compare solo quando la scheda aperta ha più di
         * questo numero di carte. Con poche carte stanno tutte sullo schermo e
         * si fa prima a toccarle: il campo occuperebbe solo spazio. Lo stesso
         * valore è in OCListaViewController.m.
         */
        private const val CARTE_PER_LA_RICERCA = 5
    }

    private lateinit var pagine: ViewPager2
    private lateinit var carte: PagineCarte
    private lateinit var schede: TabLayout
    private lateinit var ricerca: EditText

    /**
     * Quante carte ha ogni scheda, prima del filtro, per tipo di scheda. Si
     * contano senza filtro: altrimenti, scrivendo, le carte trovate
     * scenderebbero sotto la soglia e il campo sparirebbe sotto le dita.
     */
    private var cartePerScheda = mapOf<Int, Int>()

    /** Vero mentre [ricarica] sposta le pagine per rifare le schede. */
    private var rifacendoSchede = false

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
    ) { sorgente -> if (sorgente != null) leggiBackup(sorgente) }

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

        // Il campo segue la scheda aperta: si decide a ogni cambio di pagina.
        pagine.registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(posizione: Int) {
                if (!rifacendoSchede) aggiornaRicerca()
            }
        })

        // Si filtra a ogni tasto, senza aspettare l'invio. La X a destra del
        // campo lo svuota e fa tornare tutte le carte.
        ricerca = findViewById(R.id.ricerca)
        val contenitore = findViewById<TextInputLayout>(R.id.ricerca_contenitore)
        contenitore.setEndIconOnClickListener { ricerca.setText("") }
        contenitore.isEndIconVisible = false
        ricerca.addTextChangedListener(object : TextWatcher {
            override fun afterTextChanged(testo: Editable?) {
                contenitore.isEndIconVisible = !testo.isNullOrEmpty()
                carte.filtra(testo?.toString().orEmpty())
            }

            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
        })
        ricerca.setOnEditorActionListener { campo, _, _ ->
            // Il tasto di ricerca chiude la tastiera: le carte trovate sono
            // già lì, e la tastiera ne coprirebbe metà. Non si guarda quale
            // azione arriva: l'invio di una tastiera fisica non porta
            // IME_ACTION_SEARCH, e deve fare la stessa cosa.
            getSystemService(InputMethodManager::class.java)
                .hideSoftInputFromWindow(campo.windowToken, 0)
            campo.clearFocus()
            true
        }

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
            {
                mapOf(
                    PagineCarte.PREFERITE to Core.getPreferite().size,
                    PagineCarte.CARTE to Core.getGruppo(false).size,
                    PagineCarte.USA_E_GETTA to Core.getGruppo(true).size,
                )
            },
            { quante ->
                cartePerScheda = quante
                val ce = quante.getValue(PagineCarte.PREFERITE) > 0
                val ceUsaEGetta = quante.getValue(PagineCarte.USA_E_GETTA) > 0
                val guardava = carte.tipoDi(pagine.currentItem)
                if (carte.mostraSchede(ce, ceUsaEGetta)) {
                    // Prima si torna a una posizione che esiste anche dopo, poi
                    // si cambia il numero di schede. Il passaggio per la prima
                    // pagina non è un cambio di scheda: il campo di ricerca non
                    // lo deve vedere, o si svuoterebbe per niente.
                    rifacendoSchede = true
                    pagine.setCurrentItem(0, false)
                    carte.ricarica()
                    val dove = carte.posizioneDi(guardava)
                    if (dove > 0) pagine.setCurrentItem(dove, false)
                    rifacendoSchede = false
                } else {
                    carte.ricarica()
                }
                // Una scheda sola non e' una scheda: non c'e' niente fra cui
                // scegliere, e la fila in cima allo schermo diventa un
                // ornamento. Sparisce, e con essa la barra all'apertura di chi
                // non ha ancora nessuna carta.
                schede.visibility = if (carte.itemCount > 1) View.VISIBLE else View.GONE
                aggiornaRicerca()
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
     * Il campo di ricerca c'è solo se la scheda aperta ha più di
     * [CARTE_PER_LA_RICERCA] carte: con poche carte non c'è niente da
     * cercare. Quando sparisce si svuota, sia che si passi a una scheda più
     * piccola sia che si scenda sotto la soglia eliminando una carta:
     * nascosto, il filtro resterebbe acceso senza che si veda.
     */
    private fun aggiornaRicerca() {
        val quante = cartePerScheda[carte.tipoDi(pagine.currentItem)] ?: 0
        val conRicerca = quante > CARTE_PER_LA_RICERCA
        if (!conRicerca) ricerca.text?.clear()
        findViewById<View>(R.id.ricerca_riquadro).visibility =
            if (conRicerca) View.VISIBLE else View.GONE
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
                // Archivio con le foto o CSV, e la password che chiude tutto:
                // lo fa il core, uguale su iPhone.
                Core.esporta(esportaCsv, Core.adesso(), password)
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

    private fun leggiBackup(sorgente: Uri) {
        // Lettura sul thread dei dati: il file può stare su un provider lento
        // (Drive) e sul thread dell'interfaccia sarebbe un ANR. Il tetto è
        // quello del core, lo stesso dell'esportazione: tiene fuori il file
        // sbagliato scelto per errore e lascia entrare ogni backup dell'app.
        // Si legge prima di fare domande, perché la domanda giusta dipende da
        // che file è.
        Dati.chiedi(
            {
                val dati = try {
                    val misura = misura(sorgente)
                    contentResolver.openInputStream(sorgente)?.use { leggiConTetto(it, misura) }
                } catch (e: OpenCardException) {
                    throw e
                } catch (e: OutOfMemoryError) {
                    // Un Error, non un'eccezione: senza, l'app si chiude.
                    throw OpenCardException(Core.ERRORE_MEMORIA, 0, "", 0)
                } catch (e: Exception) {
                    null
                } ?: throw OpenCardException(getString(R.string.backup_non_letto))
                dati to Core.getAll().isEmpty()
            },
            { (dati, vuoto) -> confermaRipristino(dati, vuoto) },
            { avvisa(it) },
        )
    }

    private fun confermaRipristino(dati: ByteArray, vuoto: Boolean) {
        // Un CSV è un'altra cosa rispetto a un backup: può aggiungersi alle
        // carte che ci sono, che è quello che vuole chi arriva da un'altra
        // app, oppure prendere il loro posto. Lo decide chi importa, con due
        // risposte che dicono quello che fanno: fino alla 1.0.3 la domanda
        // diceva «Sostituisci» e l'app aggiungeva.
        if (Core.fileTipo(dati) == Core.FILE_CSV) {
            if (vuoto) {
                scriviLeCarte(dati, "", sostituisciCsv = false)
                return
            }
            AlertDialog.Builder(this)
                .setTitle(R.string.csv_titolo)
                .setMessage(R.string.csv_avviso)
                .setNegativeButton(R.string.annulla, null)
                .setNeutralButton(R.string.csv_aggiungi) { _, _ -> scriviLeCarte(dati, "", sostituisciCsv = false) }
                .setPositiveButton(R.string.ripristina_conferma) { _, _ -> scriviLeCarte(dati, "", sostituisciCsv = true) }
                .show()
            return
        }
        // Con zero carte non c'e' niente da sostituire: la domanda sarebbe
        // solo un passaggio in piu' prima di una cosa che non toglie nulla a
        // nessuno.
        if (vuoto) {
            chiediPasswordSeServe(dati)
            return
        }
        AlertDialog.Builder(this)
            .setTitle(R.string.ripristina_titolo)
            .setMessage(R.string.ripristina_avviso)
            .setNegativeButton(R.string.annulla, null)
            .setPositiveButton(R.string.ripristina_conferma) { _, _ -> chiediPasswordSeServe(dati) }
            .show()
    }

    /** La password si chiede solo se il file ce l'ha: chi non l'ha mai usata non vede niente di nuovo. */
    private fun chiediPasswordSeServe(dati: ByteArray) {
        // Qui si arriva dopo «Sostituisci», o senza carte: anche un CSV chiuso
        // con la password prende il posto di quelle che ci sono. Con false si
        // aggiungeva, e le carte finivano doppie.
        if (Core.fileTipo(dati) == Core.FILE_CIFRATO) {
            chiediPassword(
                R.string.password_apri_titolo,
                R.string.password_apri_spiega,
                vuotoAmmesso = false,
                // Qui non si salva niente: si apre un file che c'e' gia'.
                bottone = R.string.apri,
            ) { password -> scriviLeCarte(dati, password, sostituisciCsv = true) }
        } else {
            scriviLeCarte(dati, "", sostituisciCsv = true)
        }
    }

    private fun scriviLeCarte(dati: ByteArray, password: String, sostituisciCsv: Boolean) {
        Dati.chiedi(
            // Archivio, CSV o JSON, con o senza password: il core riconosce il
            // file, rimette a posto le foto e scrive le carte in una volta.
            { Core.importa(dati, password, sostituisciCsv) },
            { quante ->
                ricarica()
                avvisa(resources.getQuantityString(R.plurals.carte_ripristinate, quante, quante))
            },
            { avvisa(it) },
        )
    }

    /** Quanto è grande il file secondo il sistema, -1 se non lo sa. */
    private fun misura(sorgente: Uri): Long =
        contentResolver.query(sorgente, arrayOf(OpenableColumns.SIZE), null, null, null)?.use {
            if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else -1L
        } ?: -1L

    /**
     * Legge tutto il file, ma non oltre il tetto del core.
     *
     * Conta la memoria: raccolto in un ByteArrayOutputStream, un file oltre i
     * 64 MB faceva chiedere un buffer da 128, e su Bliss l'app si chiudeva.
     * Con la misura nota si legge in un array della misura giusta, senza
     * raddoppi e senza la copia finale; senza, la raccolta si ferma prima di
     * scrivere il blocco che la porterebbe oltre il tetto.
     */
    private fun leggiConTetto(flusso: java.io.InputStream, misura: Long): ByteArray {
        val tetto = Core.fileMassimo()
        val troppoGrande = OpenCardException(Core.ERRORE_TROPPO_GRANDE, 0, "", 0)
        if (misura > tetto) throw troppoGrande
        if (misura >= 0) {
            val dati = ByteArray(misura.toInt())
            var letti = 0
            while (letti < dati.size) {
                val n = flusso.read(dati, letti, dati.size - letti)
                if (n < 0) return dati.copyOf(letti)
                letti += n
            }
            // Più lungo di quanto diceva il sistema: meglio non fidarsi.
            if (flusso.read() >= 0) throw OpenCardException(getString(R.string.backup_non_letto))
            return dati
        }
        val raccolta = java.io.ByteArrayOutputStream()
        val blocco = ByteArray(64 * 1024)
        while (true) {
            val letti = flusso.read(blocco)
            if (letti < 0) return raccolta.toByteArray()
            if (raccolta.size() + letti > tetto) throw troppoGrande
            raccolta.write(blocco, 0, letti)
        }
    }

    private fun avvisa(messaggio: String) {
        Snackbar.make(findViewById(R.id.radice), messaggio, Snackbar.LENGTH_LONG).show()
    }
}
