// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.ExifInterface
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.TextView
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.checkbox.MaterialCheckBox
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.io.File

/**
 * Aggiunta e modifica di una carta.
 *
 * Il codice si prende in tre modi, con lo stesso peso: dal vivo con la
 * fotocamera, da una foto della galleria, da un file. Le due strade
 * dall'immagine servono quando la tessera e' gia' fotografata, o quando e'
 * arrivata per messaggio.
 */
class FormActivity : AppCompatActivity() {

    private var id = 0
    private var usaEGetta = false
    private var coloreScelto: String? = null
    private var coloreProposto: String = "#E6642B"

    private lateinit var nome: EditText
    private lateinit var codice: EditText
    private lateinit var qrcode: RadioButton
    private lateinit var barcode: RadioButton
    private lateinit var casella: MaterialCheckBox
    private lateinit var stella: MaterialCheckBox
    private lateinit var tavolozza: LinearLayout
    private lateinit var errore: TextView

    private val scansiona = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { esito ->
        if (esito.resultCode == Activity.RESULT_OK) {
            val letto = esito.data?.getStringExtra(ScannerActivity.EXTRA_CODICE)
            val eraQr = esito.data?.getBooleanExtra(ScannerActivity.EXTRA_QRCODE, false) ?: false
            if (letto != null) accetta(letto, eraQr)
        }
    }

    private val dallaGalleria = registerForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { immagine -> immagine?.let { leggiDaImmagine(it) } }

    private val daFile = registerForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { immagine -> immagine?.let { leggiDaImmagine(it) } }

    companion object {
        private const val EXTRA_ID = "id"
        private const val EXTRA_USA_E_GETTA = "usaEGetta"

        /** Lo legge la carta aperta: se e' stata cancellata deve chiudersi. */
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
        qrcode = findViewById(R.id.tipo_qrcode)
        barcode = findViewById(R.id.tipo_barcode)
        casella = findViewById(R.id.usa_e_getta)
        stella = findViewById(R.id.preferita)
        tavolozza = findViewById(R.id.tavolozza)
        errore = findViewById(R.id.errore)

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
            daFile.launch(arrayOf("image/*"))
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
            // Il colore proposto e' quello che la carta prenderebbe da se': chi
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
                codice.setText(carta.code)
                qrcode.isChecked = carta.isQrcode
                barcode.isChecked = !carta.isQrcode
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

    /** Codice letto, da qualunque strada sia arrivato. */
    private fun accetta(letto: String, eraQr: Boolean) {
        codice.setText(letto)
        qrcode.isChecked = eraQr
        barcode.isChecked = !eraQr
        errore.text = ""
    }

    /**
     * Legge il codice da un'immagine gia' esistente invece che dal vivo.
     * ML Kit lavora sul file, quindi va bene qualunque immagine il telefono
     * sappia aprire.
     */
    private fun leggiDaImmagine(immagine: Uri) {
        val lettore = BarcodeScanning.getClient()
        val copia = copiaInCache(immagine)
        val ridotta = copia?.let { decodificaRidotta(it) }
        try {
            val ingresso = if (copia != null && ridotta != null) {
                InputImage.fromBitmap(ridotta, rotazione(copia))
            } else {
                InputImage.fromFilePath(this, immagine)
            }
            lettore.process(ingresso)
                .addOnSuccessListener { codici ->
                    val primo = codici.firstOrNull { !it.rawValue.isNullOrEmpty() }
                    if (primo == null) {
                        avvisa(getString(R.string.nessun_codice_nell_immagine))
                    } else {
                        accetta(primo.rawValue!!, primo.format == Barcode.FORMAT_QR_CODE)
                    }
                }
                .addOnFailureListener { guasto ->
                    avvisa(getString(R.string.lettura_non_riuscita, guasto.message ?: ""))
                }
                .addOnCompleteListener {
                    lettore.close()
                    ridotta?.recycle()
                }
        } catch (guasto: Exception) {
            lettore.close()
            ridotta?.recycle()
            avvisa(getString(R.string.lettura_non_riuscita, guasto.message ?: ""))
        } finally {
            // La foto della tessera non resta in cache oltre la lettura: qui
            // l'immagine e' gia' in memoria e il file non serve piu' a nessuno,
            // nemmeno alla strada di scorta, che rilegge l'Uri di partenza.
            copia?.delete()
        }
    }

    /**
     * Il file dell'immagine, preso una volta sola.
     *
     * Sonda, decodifica e EXIF lavorano tutti su questa copia. L'immagine non
     * arriva dal disco ma da un provider (la galleria di sistema, Google Foto,
     * Drive), e ogni apertura dell'Uri puo' essere un nuovo scaricamento:
     * aprirlo tre volte erano tre scaricamenti e tre punti dove fallire a
     * meta'. Da un file in cache invece si rilegge quanto si vuole a costo
     * zero.
     *
     * Si copia invece di tenere i byte in memoria perche' un file arbitrario
     * scelto dall'utente non ha un tetto: un `ByteArray` grande quanto il file
     * puo' finire in [OutOfMemoryError], che non e' una [Exception] e non
     * verrebbe preso da nessun catch. Qui il travaso passa da un buffer di
     * pochi kB e l'unica cosa grande che si alloca resta la bitmap ridotta.
     *
     * Torna null se la copia non riesce: si ricade su [InputImage.fromFilePath],
     * che e' quello che faceva prima.
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
     * Decodifica l'immagine gia' rimpicciolita.
     *
     * Una foto da 12 megapixel diventa una cinquantina di MB di bitmap, e il
     * telefono li paga tutti in una volta: qui si decodifica a scala ridotta,
     * senza mai scendere sotto [LATO_MINIMO] sul lato lungo. Le immagini gia'
     * piccole restano come sono. Null se il file non e' un'immagine.
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
     * Di quanto e' girata la foto secondo l'EXIF.
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
     * I colori fra cui scegliere. Il primo e' quello che spetta alla carta:
     * lasciandolo com'e' non si scrive niente nel file, ed e' il caso normale.
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
            errore.text = getString(R.string.manca_etichetta)
            return
        }
        if (valore.isEmpty()) {
            errore.text = getString(R.string.manca_codice)
            return
        }

        val isQr = qrcode.isChecked
        val colore = coloreScelto ?: ""
        val disposable = casella.isChecked
        val preferita = stella.isChecked

        Dati.fai(
            {
                // La stella si scrive a parte, perche' non passa da insert e
                // update: quelle due lasciano stare il campo apposta, cosi'
                // modificare una carta non le toglie la preferenza.
                val quale = if (id == 0) {
                    Core.insert(etichetta, valore, isQr, colore, disposable)
                } else {
                    Core.update(id, etichetta, valore, isQr, colore, disposable)
                    id
                }
                Core.setPreferita(quale, preferita)
            },
            {
                setResult(Activity.RESULT_OK)
                finish()
            },
            { avvisa(it) },
        )
    }

    /**
     * Cancella la carta che si sta modificando.
     *
     * La domanda e' la stessa del cestino nell'elenco, con lo stesso titolo e
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
                    { Core.delete(id) },
                    {
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
        errore.text = messaggio
    }
}

/** Gli stessi colori che assegna il core, per la scelta a mano. */
private val COLORI = listOf(
    "#E53935", "#8E24AA", "#1E88E5", "#00897B", "#43A047", "#FB8C00",
    "#6D4C41", "#039BE5", "#D81B60", "#3949AB", "#00ACC1", "#7CB342",
)
