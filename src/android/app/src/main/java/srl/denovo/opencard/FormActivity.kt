// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.text.Editable
import android.text.TextWatcher
import android.os.ParcelFileDescriptor
import android.os.Bundle
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Spinner
import android.widget.TextView
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.exifinterface.media.ExifInterface
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.checkbox.MaterialCheckBox
import com.google.android.material.datepicker.MaterialDatePicker
import com.google.android.material.textfield.TextInputLayout
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.io.File
import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Aggiunta e modifica di una carta.
 *
 * Il codice si prende in tre modi, con lo stesso peso: dal vivo con la
 * fotocamera, da una foto della galleria, da un file. Le due strade
 * dall'immagine servono quando la tessera è già fotografata, o quando è
 * arrivata per messaggio.
 */
class FormActivity : AppCompatActivity() {

    private var id = 0
    private var usaEGetta = false
    private var coloreScelto: String? = null
    private var coloreProposto: String = "#E6642B"

    private lateinit var nome: EditText
    private lateinit var codice: EditText
    private lateinit var simbologia: Spinner

    /** Il tipo di codice della carta, l'unico posto dove sta scritto. */
    private var simbologiaScelta = Simbologie.AUTO

    /** Vero se la riga rossa sta mostrando l'avviso sul tipo di codice. */
    private var avvisoSimbologia = false

    /**
     * L'ultimo codice di cui si sa il tipo per certo, e qual e'.
     *
     * Lo riempie il lettore quando misura un codice, e la carta quando si apre
     * per modificarla. Automatico se ne serve finche' il codice resta quello:
     * e' un'informazione vera, e batte qualsiasi regola sulle cifre.
     */
    private var codiceNoto = ""
    private var simbologiaNota = Simbologie.AUTO
    private lateinit var nota: EditText
    private lateinit var scadenza: EditText
    private lateinit var riquadroScadenza: TextInputLayout
    private lateinit var saldo: EditText
    private lateinit var bottoneFronte: Button
    private lateinit var bottoneRetro: Button
    private lateinit var anteprimaFronte: ImageView
    private lateinit var anteprimaRetro: ImageView

    /**
     * Le foto scelte ma non ancora salvate.
     *
     * Per una carta nuova l'id non esiste finché non si preme Salva, e il nome
     * del file lo contiene: le foto restano qui in memoria e si scrivono su
     * disco quando l'id c'è. Null vuol dire "non toccata", che è diverso da
     * "tolta": per quello c'è [fotoTolte].
     */
    private var fotoNuove = arrayOfNulls<android.graphics.Bitmap>(2)
    private val fotoTolte = booleanArrayOf(false, false)
    /** I nomi che la carta ha adesso, per sapere cosa cancellare. */
    private var fotoAttuali = arrayOf("", "")
    /** Quale dei due riquadri ha aperto il selettore. */
    private var latoInCorso = 0
    private lateinit var casella: MaterialCheckBox
    private lateinit var stella: MaterialCheckBox
    private lateinit var tavolozza: LinearLayout
    private lateinit var errore: TextView

    private val scansiona = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { esito ->
        if (esito.resultCode == Activity.RESULT_OK) {
            val letto = esito.data?.getStringExtra(ScannerActivity.EXTRA_CODICE)
            val letta = esito.data?.getIntExtra(
                ScannerActivity.EXTRA_SIMBOLOGIA, Simbologie.AUTO
            ) ?: Simbologie.AUTO
            if (letto != null) accetta(letto, letta)
        }
    }

    private val dallaGalleria = registerForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { immagine -> immagine?.let { leggiDaImmagine(it) } }

    private val daFile = registerForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { immagine -> immagine?.let { leggiDaImmagine(it) } }

    private val fotoDaGalleria = registerForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { immagine -> immagine?.let { prendiLaFoto(it) } }

    companion object {
        private const val FRONTE = 0
        private const val RETRO = 1

        private const val EXTRA_ID = "id"
        private const val EXTRA_USA_E_GETTA = "usaEGetta"

        /** Lo legge la carta aperta: se è stata cancellata deve chiudersi. */
        const val EXTRA_ELIMINATA = "eliminata"

        /**
         * Lato lungo sotto cui non si scende leggendo un'immagine dal telefono.
         * Sopra questa misura ML Kit legge lo stesso, sotto comincia a perdere i
         * barcode stretti.
         */
        private const val LATO_MINIMO = 1600

        fun intentNuova(contesto: Context, usaEGetta: Boolean) =
            Intent(contesto, FormActivity::class.java)
                .putExtra(EXTRA_USA_E_GETTA, usaEGetta)

        fun intentModifica(contesto: Context, id: Int) =
            Intent(contesto, FormActivity::class.java).putExtra(EXTRA_ID, id)
    }

    override fun onCreate(statoSalvato: Bundle?) {
        super.onCreate(statoSalvato)
        setContentView(R.layout.activity_form)
        setSupportActionBar(findViewById(R.id.barra))
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        nome = findViewById(R.id.nome)
        codice = findViewById(R.id.codice)
        nota = findViewById(R.id.nota)
        scadenza = findViewById(R.id.scadenza)
        saldo = findViewById(R.id.saldo)
        scadenza.setOnClickListener { chiediLaData() }
        // La X che svuota il campo. Va messa a mano invece di usare
        // endIconMode="clear_text": quella compare solo quando il campo ha il
        // fuoco, e questo campo il fuoco non lo prende mai apposta, perche' la
        // data si sceglie dal calendario e non si scrive.
        riquadroScadenza = findViewById(R.id.riquadro_scadenza)
        riquadroScadenza.setEndIconOnClickListener { scadenza.setText("") }
        scadenza.addTextChangedListener(object : TextWatcher {
            override fun afterTextChanged(testo: Editable?) {
                riquadroScadenza.isEndIconVisible = !testo.isNullOrEmpty()
            }

            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
        })
        riquadroScadenza.isEndIconVisible = false

        bottoneFronte = findViewById(R.id.foto_fronte)
        bottoneRetro = findViewById(R.id.foto_retro)
        anteprimaFronte = findViewById(R.id.anteprima_fronte)
        anteprimaRetro = findViewById(R.id.anteprima_retro)
        bottoneFronte.setOnClickListener { scegliFoto(FRONTE) }
        bottoneRetro.setOnClickListener { scegliFoto(RETRO) }
        anteprimaFronte.setOnClickListener { togliFoto(FRONTE) }
        anteprimaRetro.setOnClickListener { togliFoto(RETRO) }
        simbologia = findViewById(R.id.simbologia)
        // Automatico è la prima voce ed è quella di partenza: chi aggiunge una
        // tessera non sa che codice ha in mano, e non deve saperlo.
        simbologia.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_item,
            listOf(getString(R.string.simbologia_auto)) + Simbologie.nomi,
        ).apply { setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }
        simbologia.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(
                elenco: AdapterView<*>?, vista: View?, posizione: Int, quale: Long,
            ) {
                simbologiaScelta = Simbologie.simbologiaDellaVoce(posizione)
                controllaSimbologia()
            }

            override fun onNothingSelected(elenco: AdapterView<*>?) = Unit
        }
        casella = findViewById(R.id.usa_e_getta)
        stella = findViewById(R.id.preferita)
        tavolozza = findViewById(R.id.tavolozza)
        errore = findViewById(R.id.errore)

        // L'avviso sul tipo di codice segue anche il codice: cambiandolo a mano
        // una scelta che prima non ci stava puo' andare bene, e viceversa.
        codice.addTextChangedListener(object : TextWatcher {
            override fun afterTextChanged(testo: Editable?) = controllaSimbologia()

            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
        })

        id = intent.getIntExtra(EXTRA_ID, 0)
        usaEGetta = intent.getBooleanExtra(EXTRA_USA_E_GETTA, false)

        preparaBottone(R.id.da_fotocamera, R.string.da_fotocamera, R.drawable.ic_fotocamera) {
            scansiona.launch(Intent(this, ScannerActivity::class.java))
        }
        preparaBottone(R.id.da_galleria, R.string.da_galleria, R.drawable.ic_galleria) {
            dallaGalleria.launch(
                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
            )
        }
        preparaBottone(R.id.da_file, R.string.da_file, R.drawable.ic_file) {
            daFile.launch(arrayOf("image/*", "application/pdf"))
        }

        findViewById<Button>(R.id.annulla).setOnClickListener { finish() }
        findViewById<Button>(R.id.salva).setOnClickListener { salva() }

        if (id != 0) {
            title = getString(R.string.modifica_codice)
            findViewById<Button>(R.id.elimina).apply {
                visibility = View.VISIBLE
                setOnClickListener { confermaEliminazione() }
            }
            carica()
        } else {
            title = getString(R.string.aggiungi_codice)
            casella.isChecked = usaEGetta
            // Il colore proposto è quello che la carta prenderebbe da sé: chi
            // non ci bada trova la stessa app di prima, chi ci bada lo cambia.
            Dati.chiedi({ Core.nextId() }, { prossimo ->
                coloreProposto = Core.colorForId(prossimo)
                costruisciTavolozza()
            })
        }
    }

    private fun preparaBottone(idVista: Int, testo: Int, icona: Int, azione: () -> Unit) {
        findViewById<MaterialButton>(idVista).apply {
            text = getString(testo)
            setIconResource(icona)
            setOnClickListener { azione() }
        }
    }

    private fun carica() {
        Dati.chiedi(
            { Core.get(id) },
            { carta ->
                nome.setText(carta.label)
                codiceNoto = carta.code.trim()
                simbologiaNota = carta.simbologia
                codice.setText(carta.code)
                mostraSimbologia(carta.simbologia)
                nota.setText(carta.note)
                scadenza.setText(carta.scadenza)
                saldo.setText(carta.saldo)
                fotoAttuali = arrayOf(carta.fotoFronte, carta.fotoRetro)
                mostraAnteprime()
                casella.isChecked = carta.disposable
                stella.isChecked = carta.preferita
                usaEGetta = carta.disposable
                coloreProposto = carta.colore
                if (carta.coloreScelto) coloreScelto = carta.colore
                costruisciTavolozza()
            },
            { avvisa(it) },
        )
    }

    /**
     * Il calendario per la scadenza.
     *
     * Il campo non si scrive a mano apposta: una data battuta a mano arriva in
     * dieci formati diversi e il core ne accetta uno solo. Il calendario parte
     * dalla data che c'e' gia', o da oggi se il campo e' vuoto, e restituisce
     * sempre "AAAA-MM-GG".
     */
    private fun chiediLaData() {
        val formato = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val scritta = scadenza.text.toString().trim()
        val partenza = try {
            if (scritta.isEmpty()) MaterialDatePicker.todayInUtcMilliseconds()
            else formato.parse(scritta)?.time ?: MaterialDatePicker.todayInUtcMilliseconds()
        } catch (guasto: ParseException) {
            MaterialDatePicker.todayInUtcMilliseconds()
        }

        val calendario = MaterialDatePicker.Builder.datePicker()
            .setTitleText(getString(R.string.scadenza))
            .setSelection(partenza)
            .build()
        calendario.addOnPositiveButtonClickListener { quando ->
            scadenza.setText(formato.format(Date(quando)))
        }
        calendario.show(supportFragmentManager, "scadenza")
    }

    /**
     * Le tre funzioni delle foto.
     *
     * Sceglierne una la tiene in memoria e basta: il nome del file contiene
     * l'id, e per una carta nuova l'id arriva solo al salvataggio. Toglierla
     * segna il lato, senza cancellare niente subito: se poi si esce senza
     * salvare, la foto che c'era deve essere ancora li'.
     */
    private fun scegliFoto(lato: Int) {
        latoInCorso = lato
        fotoDaGalleria.launch(
            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
        )
    }

    private fun prendiLaFoto(immagine: Uri) {
        val copia = copiaInCache(immagine)
        val letta = copia?.let { decodificaRidotta(it) }
        copia?.delete()
        if (letta == null) {
            avvisa(getString(R.string.immagine_non_letta))
            return
        }
        fotoNuove[latoInCorso] = Foto.riduci(letta)
        fotoTolte[latoInCorso] = false
        mostraAnteprime()
    }

    private fun togliFoto(lato: Int) {
        fotoNuove[lato] = null
        fotoTolte[lato] = true
        mostraAnteprime()
    }

    /** Quello che si vede: la foto appena scelta, quella salvata, o niente. */
    private fun mostraAnteprime() {
        for (lato in 0..1) {
            val vista = if (lato == FRONTE) anteprimaFronte else anteprimaRetro
            val immagine = fotoNuove[lato]
                ?: if (fotoTolte[lato]) null else Foto.leggi(this, fotoAttuali[lato], 400)
            if (immagine == null) {
                vista.setImageDrawable(null)
                vista.visibility = View.GONE
            } else {
                vista.setImageBitmap(immagine)
                vista.visibility = View.VISIBLE
            }
        }
        bottoneFronte.setText(if (anteprimaFronte.visibility == View.VISIBLE) R.string.togli_foto else R.string.foto_fronte)
        bottoneRetro.setText(if (anteprimaRetro.visibility == View.VISIBLE) R.string.togli_foto else R.string.foto_retro)
    }

    /**
     * Scrive le foto e torna i due nomi da mettere nella carta. Si chiama a
     * salvataggio fatto, quando l'id c'e' di sicuro.
     */
    private fun salvaLeFoto(id: Int): Array<String> {
        val nomi = fotoAttuali.copyOf()
        for (lato in 0..1) {
            val fronte = lato == FRONTE
            val nuova = fotoNuove[lato]
            when {
                nuova != null -> {
                    val scritta = Foto.salva(this, nuova, id, fronte)
                    if (scritta != null) {
                        nomi[lato] = scritta
                    }
                }
                fotoTolte[lato] -> {
                    Foto.cancella(this, nomi[lato])
                    nomi[lato] = ""
                }
            }
        }
        return nomi
    }

    /** Scrive il tipo di codice nell'elenco, e con lui il valore vero. */
    private fun mostraSimbologia(quale: Int) {
        simbologiaScelta = quale
        simbologia.setSelection(Simbologie.voce(quale))
        controllaSimbologia()
    }

    /**
     * L'avviso quando il tipo scelto non puo' contenere il codice che c'e'.
     *
     * Arriva scegliendo, non premendo Salva: cosi' si vede subito che quella
     * strada non porta da nessuna parte, e si vede anche aprendo una carta
     * salvata storta da una versione precedente. Salva poi si rifiuta lo stesso.
     *
     * Con Automatico non compare mai: quella strada una simbologia buona la
     * trova sempre.
     */
    private fun controllaSimbologia() {
        val valore = codice.text.toString().trim()
        val quale = simbologiaScelta

        if (valore.isEmpty() || quale == Simbologie.AUTO || Core.codiceSta(valore, quale)) {
            if (avvisoSimbologia) mostraErrore("")
            return
        }
        mostraErrore(getString(R.string.simbologia_non_ci_sta, Simbologie.nomi[quale]))
        avvisoSimbologia = true
    }

    /**
     * La simbologia che sceglie l'app quando l'elenco è su Automatico.
     *
     * Si parte da quella che si ricava dal codice, che è la regola di sempre.
     * Se il codice non ci sta si ripiega sul QR, che tiene tutto: il contenuto
     * di un QR in un Code 128 non entra, e Automatico non deve mai finire in un
     * errore, perché è la voce di chi non vuole scegliere.
     */
    private fun automatica(codice: String): Int {
        // Quello che il lettore ha misurato, o quello con cui la carta era
        // salvata: e' un fatto, non una supposizione, e vale finche' il codice
        // non cambia. Senza questo un QR letto dalla fotocamera, lasciato su
        // Automatico, tornerebbe un Code 128 solo perche' il suo contenuto ci
        // sta dentro.
        if (codice == codiceNoto && simbologiaNota != Simbologie.AUTO) {
            return simbologiaNota
        }
        val proposta = Core.simbologiaIndovinata(codice, false)
        return if (Core.codiceSta(codice, proposta)) proposta else Simbologie.QR
    }

    /** Codice letto, da qualunque strada sia arrivato. */
    private fun accetta(letto: String, letta: Int) {
        codiceNoto = letto.trim()
        simbologiaNota = letta
        codice.setText(letto)
        // Il lettore ha misurato che codice era: si scrive quello nell'elenco,
        // cosi' chi ha inquadrato la tessera vede subito cosa ha preso e non
        // deve decidere niente. Resta cambiabile a mano.
        //
        // Se il formato non e' fra quelli che sappiamo disegnare si resta su
        // Automatico, e la simbologia la sceglie il salvataggio.
        mostraSimbologia(letta)
        mostraErrore("")
    }

    /**
     * Legge il codice da un'immagine già esistente invece che dal vivo.
     * ML Kit lavora sul file, quindi va bene qualunque immagine il telefono
     * sappia aprire.
     *
     * Si legge prima l'immagine rimpicciolita, che costa poca memoria. Se non
     * trova niente si riprova una volta sola con [senzaRidurre], perché su una
     * tessera fotografata da lontano la riduzione porta le barre a due pixel e
     * il lettore si ferma.
     */
    /**
     * Il PDF: la prima pagina diventa un'immagine e poi segue la strada di
     * sempre.
     *
     * Le tessere in PDF arrivano dalle email dei negozi e dai biglietti, e
     * hanno il codice su una pagina sola. Si rende a 2000 pixel di lato: sotto,
     * le barre sottili si impastano e il lettore non le riconosce.
     */
    private fun bitmapDaPdf(copia: File): Bitmap? = try {
        ParcelFileDescriptor.open(copia, ParcelFileDescriptor.MODE_READ_ONLY).use { presa ->
            PdfRenderer(presa).use { lettore ->
                if (lettore.pageCount < 1) {
                    null
                } else {
                    lettore.openPage(0).use { pagina ->
                        val scala = 2000f / maxOf(pagina.width, pagina.height).toFloat()
                        val larghezza = (pagina.width * scala).toInt().coerceAtLeast(1)
                        val altezza = (pagina.height * scala).toInt().coerceAtLeast(1)
                        val foglio = Bitmap.createBitmap(larghezza, altezza, Bitmap.Config.ARGB_8888)
                        // Il PDF disegna solo quello che c'e': il fondo bianco
                        // lo mettiamo noi, altrimenti resta trasparente e il
                        // lettore di codici vede nero su nero.
                        Canvas(foglio).drawColor(Color.WHITE)
                        pagina.render(foglio, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        foglio
                    }
                }
            }
        }
    } catch (guasto: Exception) {
        null
    }

    private fun leggiDaImmagine(immagine: Uri, senzaRidurre: Boolean = false) {
        val lettore = BarcodeScanning.getClient()
        val copia = copiaInCache(immagine)
        // Un PDF non si decodifica come immagine: prima si rende la pagina.
        val eUnPdf = copia != null && contentResolver.getType(immagine) == "application/pdf"
        val bitmap = copia?.let {
            when {
                eUnPdf -> bitmapDaPdf(it)
                senzaRidurre -> decodificaPiena(it)
                else -> decodificaRidotta(it)
            }
        }
        try {
            val ingresso = if (copia != null && bitmap != null) {
                InputImage.fromBitmap(bitmap, if (eUnPdf) 0 else rotazione(copia))
            } else {
                InputImage.fromFilePath(this, immagine)
            }
            lettore.process(ingresso)
                .addOnSuccessListener { codici ->
                    val primo = codici.firstOrNull { !it.rawValue.isNullOrEmpty() }
                    if (primo != null) {
                        accetta(
                            primo.rawValue!!,
                            ScannerActivity.simbologiaDelFormato(primo.format),
                        )
                    } else if (!senzaRidurre && !eUnPdf && copia != null && bitmap != null) {
                        leggiDaImmagine(immagine, senzaRidurre = true)
                    } else {
                        avvisa(getString(R.string.nessun_codice_nell_immagine))
                    }
                }
                .addOnFailureListener { guasto ->
                    avvisa(getString(R.string.lettura_non_riuscita, guasto.message ?: ""))
                }
                .addOnCompleteListener {
                    lettore.close()
                    bitmap?.recycle()
                }
        } catch (guasto: Exception) {
            lettore.close()
            bitmap?.recycle()
            avvisa(getString(R.string.lettura_non_riuscita, guasto.message ?: ""))
        } finally {
            // La foto della tessera non resta in cache oltre la lettura: qui
            // l'immagine è già in memoria e il file non serve più a nessuno,
            // nemmeno alla strada di scorta, che rilegge l'Uri di partenza.
            copia?.delete()
        }
    }

    /**
     * Il file dell'immagine, preso una volta sola.
     *
     * Sonda, decodifica e EXIF lavorano tutti su questa copia. L'immagine non
     * arriva dal disco ma da un provider (la galleria di sistema, Google Foto,
     * Drive), e ogni apertura dell'Uri può essere un nuovo scaricamento:
     * aprirlo tre volte erano tre scaricamenti e tre punti dove fallire a
     * metà. Da un file in cache invece si rilegge quanto si vuole a costo
     * zero.
     *
     * Si copia invece di tenere i byte in memoria perché un file arbitrario
     * scelto dall'utente non ha un tetto: un `ByteArray` grande quanto il file
     * può finire in [OutOfMemoryError], che non è una [Exception] e non
     * verrebbe preso da nessun catch. Qui il travaso passa da un buffer di
     * pochi kB e l'unica cosa grande che si alloca resta la bitmap ridotta.
     *
     * Torna null se la copia non riesce: si ricade su [InputImage.fromFilePath],
     * che è quello che faceva prima.
     */
    private fun copiaInCache(immagine: Uri): File? = try {
        val copia = File.createTempFile("scansione", null, cacheDir)
        val presa = contentResolver.openInputStream(immagine)?.use { sorgente ->
            copia.outputStream().use { sorgente.copyTo(it) }
        }
        if (presa == null) {
            copia.delete()
            null
        } else {
            copia
        }
    } catch (guasto: Exception) {
        null
    }

    /**
     * Decodifica l'immagine già rimpicciolita.
     *
     * Una foto da 12 megapixel diventa una cinquantina di MB di bitmap, e il
     * telefono li paga tutti in una volta: qui si decodifica a scala ridotta,
     * senza mai scendere sotto [LATO_MINIMO] sul lato lungo. Le immagini già
     * piccole restano come sono. Null se il file non è un'immagine.
     */
    private fun decodificaRidotta(copia: File): Bitmap? = try {
        val misura = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(copia.path, misura)
        val lato = maxOf(misura.outWidth, misura.outHeight)
        if (lato <= 0) {
            null
        } else {
            var scala = 1
            while (lato / (scala * 2) >= LATO_MINIMO) scala *= 2
            val opzioni = BitmapFactory.Options().apply { inSampleSize = scala }
            BitmapFactory.decodeFile(copia.path, opzioni)
        }
    } catch (guasto: Exception) {
        null
    }

    /**
     * L'immagine senza riduzione, per il secondo tentativo.
     *
     * `inSampleSize` a 1 è esplicito e non è di forma: il controllo di
     * `verifica-aab.sh` vuole un [BitmapFactory.Options] su ogni decodifica, e
     * Play segnala le decodifiche che non ce l'hanno.
     */
    private fun decodificaPiena(copia: File): Bitmap? = try {
        val opzioni = BitmapFactory.Options().apply { inSampleSize = 1 }
        BitmapFactory.decodeFile(copia.path, opzioni)
    } catch (guasto: Exception) {
        null
    }

    /**
     * Di quanto è girata la foto secondo l'EXIF.
     *
     * Leggendo il file da soli questo pezzo tocca a noi: [InputImage.fromFilePath]
     * lo faceva per conto suo, e senza una foto in verticale si legge storta.
     */
    private fun rotazione(copia: File): Int = try {
        val orientamento = ExifInterface(copia.path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        )
        when (orientamento) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90
            ExifInterface.ORIENTATION_ROTATE_180 -> 180
            ExifInterface.ORIENTATION_ROTATE_270 -> 270
            else -> 0
        }
    } catch (guasto: Exception) {
        0
    }

    /**
     * I colori fra cui scegliere. Il primo è quello che spetta alla carta:
     * lasciandolo com'è non si scrive niente nel file, ed è il caso normale.
     */
    private fun costruisciTavolozza() {
        val colori = (listOf(coloreProposto) + COLORI).distinct()
        val attuale = coloreScelto ?: coloreProposto

        tavolozza.removeAllViews()
        colori.forEach { colore ->
            val quadretto = layoutInflater.inflate(R.layout.item_colore, tavolozza, false)
            val scheda = quadretto.findViewById<MaterialCardView>(R.id.quadretto)
            scheda.setCardBackgroundColor(Color.parseColor(colore))
            scheda.strokeWidth = if (colore.equals(attuale, ignoreCase = true)) 8 else 0
            scheda.setOnClickListener {
                coloreScelto = colore
                costruisciTavolozza()
            }
            tavolozza.addView(quadretto)
        }
    }

    private fun salva() {
        val etichetta = nome.text.toString().trim()
        val valore = codice.text.toString().trim()

        if (etichetta.isEmpty()) {
            mostraErrore(getString(R.string.manca_etichetta))
            return
        }
        if (valore.isEmpty()) {
            mostraErrore(getString(R.string.manca_codice))
            return
        }

        // Automatico non e' una simbologia: e' l'app che ne sceglie una al
        // posto dell'utente. Qui si scioglie, guardando il codice come faceva
        // l'app prima che l'elenco esistesse, e nel file finisce la simbologia
        // vera: una carta salvata sa sempre come si disegna.
        val scelta = if (simbologiaScelta == Simbologie.AUTO) {
            automatica(valore)
        } else {
            simbologiaScelta
        }
        // Un contenuto letto da un QR in un Code 128 non ci sta, e finora la
        // carta si salvava lo stesso: il codice si scopriva mancante aprendola,
        // con un avviso che spariva da solo. Si dice qui, prima di salvare.
        // Con Automatico non succede: quella strada una simbologia buona la
        // trova sempre.
        if (!Core.codiceSta(valore, scelta)) {
            mostraErrore(getString(R.string.simbologia_non_ci_sta, Simbologie.nomi[scelta]))
            return
        }
        val isQr = Simbologie.eQuadrato(scelta)
        val quandoScade = scadenza.text.toString().trim()
        // La data la controlla anche il core, che rifiuta la carta: qui si
        // guarda prima, per dirlo con parole nostre invece che con
        // un'eccezione, e per non salvare niente a meta'.
        val dataScritta = quandoScade.length == 10 &&
            quandoScade[4] == '-' && quandoScade[7] == '-' &&
            quandoScade.filterIndexed { i, _ -> i != 4 && i != 7 }.all { it.isDigit() }
        if (quandoScade.isNotEmpty() && !dataScritta) {
            mostraErrore(getString(R.string.scadenza_non_valida))
            return
        }
        val colore = coloreScelto ?: ""
        val disposable = casella.isChecked
        val preferita = stella.isChecked

        Dati.fai(
            {
                // La stella si scrive a parte, perché non passa da insert e
                // update: quelle due lasciano stare il campo apposta, così
                // modificare una carta non le toglie la preferenza.
                val quale = if (id == 0) {
                    Core.insert(etichetta, valore, isQr, colore, disposable)
                } else {
                    Core.update(id, etichetta, valore, isQr, colore, disposable)
                    id
                }
                Core.setPreferita(quale, preferita)
                // Anche la simbologia si scrive a parte: insert e update sanno
                // dire solo QR o non QR, e una carta Aztec tornerebbe Code 128.
                Core.setSimbologia(quale, scelta)
                Core.setDettagli(
                    quale,
                    nota.text.toString().trim(),
                    quandoScade,
                    saldo.text.toString().trim(),
                )
                val nomiFoto = salvaLeFoto(quale)
                Core.setFoto(quale, nomiFoto[FRONTE], nomiFoto[RETRO])
            },
            {
                // Un nome o un colore cambiati si vedono anche sulla schermata
                // iniziale, se quella carta ci sta.
                WidgetCarta.aggiornaTutti(this)
                setResult(Activity.RESULT_OK)
                finish()
            },
            { avvisa(it) },
        )
    }

    /**
     * Cancella la carta che si sta modificando.
     *
     * La domanda è la stessa del cestino nell'elenco, con lo stesso titolo e
     * lo stesso nome fra virgolette: chi cancella deve leggere la stessa cosa
     * da qualunque parte sia arrivato.
     */
    private fun confermaEliminazione() {
        AlertDialog.Builder(this)
            .setTitle(R.string.elimina_titolo)
            .setMessage(getString(R.string.elimina_domanda, nome.text.toString().trim()))
            .setNegativeButton(R.string.annulla, null)
            .setPositiveButton(R.string.elimina) { _, _ ->
                Dati.fai(
                    {
                        Core.delete(id)
                        // I file delle foto non li guarderebbe piu' nessuno:
                        // restare li' vorrebbe dire occupare spazio per sempre.
                        Foto.cancellaDiCarta(this, id)
                    },
                    {
                        WidgetCarta.aggiornaTutti(this)
                        setResult(
                            Activity.RESULT_OK,
                            Intent().putExtra(EXTRA_ELIMINATA, true),
                        )
                        finish()
                    },
                    { avvisa(it) },
                )
            }
            .show()
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private fun avvisa(messaggio: String) {
        mostraErrore(messaggio)
    }

    /**
     * Il messaggio di errore, o niente se la stringa e' vuota.
     *
     * Da vuoto il riquadro sparisce invece di restare alto zero: sta fra i
     * pulsanti e il primo campo, e un margine appeso li' si vedrebbe.
     */
    private fun mostraErrore(messaggio: String) {
        avvisoSimbologia = false
        errore.text = messaggio
        errore.visibility = if (messaggio.isEmpty()) View.GONE else View.VISIBLE
    }
}

/** Gli stessi colori che assegna il core, per la scelta a mano. */
private val COLORI = listOf(
    "#E53935", "#8E24AA", "#1E88E5", "#00897B", "#43A047", "#FB8C00",
    "#6D4C41", "#039BE5", "#D81B60", "#3949AB", "#00ACC1", "#7CB342",
)
