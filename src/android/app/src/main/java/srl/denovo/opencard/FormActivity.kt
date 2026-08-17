// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
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
        try {
            lettore.process(InputImage.fromFilePath(this, immagine))
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
                .addOnCompleteListener { lettore.close() }
        } catch (guasto: Exception) {
            lettore.close()
            avvisa(getString(R.string.lettura_non_riuscita, guasto.message ?: ""))
        }
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
