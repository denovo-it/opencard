// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.pdf.PdfDocument
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.snackbar.Snackbar

/**
 * Passaggio delle carte fra due telefoni con dei QR.
 *
 * Chi cede mostra i codici, chi riceve li inquadra. Non c'è rete di mezzo, non
 * c'è un file da passare, non serve un account. Come sono fatti i codici sta
 * in `src/transfer.h`.
 *
 * Non c'è cifratura: il passaggio è pensato dentro la famiglia, coi due
 * telefoni uno davanti all'altro. Chi legge lo schermo legge le tessere, e su
 * questa schermata c'è scritto.
 */
class TrasferimentoActivity : AppCompatActivity() {

    private val orologio = Handler(Looper.getMainLooper())

    private var immagini: List<Bitmap> = emptyList()
    private var mostrato = 0

    /** Quante carte ci sono su questo telefono, per la domanda di chi riceve. */
    private var mie = 0

    /**
     * Un codice ogni 400 ms.
     *
     * Piu' veloce e la fotocamera dell'altro telefono ne perde la metà: ML Kit
     * lavora su un fotogramma alla volta e vuole il codice fermo per qualche
     * decimo di secondo. Piu' lento e un passaggio da tre codici diventa lungo
     * da stare fermi con la mano.
     */
    private val giostra = object : Runnable {
        override fun run() {
            if (immagini.isNotEmpty()) {
                mostrato = (mostrato + 1) % immagini.size
                disegnaCodice()
                orologio.postDelayed(this, 400)
            }
        }
    }

    private val apriLettore = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { esito ->
        val pezzi = esito.data?.getStringArrayListExtra(ScannerActivity.EXTRA_PEZZI)
        if (esito.resultCode == Activity.RESULT_OK && !pezzi.isNullOrEmpty()) {
            chiediComeMetterle(pezzi)
        }
    }

    companion object {
        /** Quante carte sono entrate, per il messaggio che mostra la lista. */
        const val EXTRA_RICEVUTE = "ricevute"

        fun intent(contesto: Context) = Intent(contesto, TrasferimentoActivity::class.java)
    }

    override fun onCreate(statoSalvato: Bundle?) {
        super.onCreate(statoSalvato)
        setContentView(R.layout.activity_trasferimento)
        setSupportActionBar(findViewById(R.id.barra))
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        title = getString(R.string.trasferimento_titolo)

        findViewById<MaterialButton>(R.id.mostra).setOnClickListener { preparaCodici() }
        findViewById<MaterialButton>(R.id.ricevi).setOnClickListener {
            apriLettore.launch(ScannerActivity.intentTrasferimento(this))
        }

        // Serve solo per la domanda da fare a chi riceve, quindi un errore qui
        // non blocca niente: al massimo la domanda dice "ne hai 0".
        Dati.chiedi({ Core.getAll().size }, { quante -> mie = quante })
    }

    /**
     * Lo schermo al massimo della luminosità mentre i codici girano.
     *
     * E' la stessa ragione della schermata di una carta: la fotocamera
     * dell'altro telefono legge male uno schermo scuro, e qui i codici sono
     * fitti. Si tocca solo la finestra, non l'impostazione di sistema.
     */
    private fun alMassimoLaLuminosita() {
        window.attributes = window.attributes.apply {
            screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private val salvaCodici = registerForActivityResult(
        ActivityResultContracts.CreateDocument("application/pdf")
    ) { destinazione -> if (destinazione != null) scriviCodici(destinazione) }

    /**
     * I codici su un PDF, uno per pagina.
     *
     * Serve a chi non ha l'altro telefono davanti adesso: si stampa o si tiene
     * il file, e il passaggio si fa quando capita, inquadrando le pagine.
     *
     * Un PDF e non tante immagini perche' i codici vanno letti in fila e nel
     * loro ordine: file separati si mescolano, e chi riceve non se ne accorge
     * finche' il pacchetto non torna.
     */
    private fun scriviCodici(destinazione: Uri) {
        if (immagini.isEmpty()) {
            return
        }
        Dati.fai(
            {
                val documento = PdfDocument()
                immagini.forEachIndexed { quale, codice ->
                    // A4 in punti, la misura che tutti stampano.
                    val pagina = documento.startPage(
                        PdfDocument.PageInfo.Builder(595, 842, quale + 1).create()
                    )
                    val lato = 595 - 80
                    val scala = lato.toFloat() / maxOf(codice.width, codice.height)
                    val largo = (codice.width * scala).toInt()
                    val alto = (codice.height * scala).toInt()
                    pagina.canvas.drawColor(Color.WHITE)
                    pagina.canvas.drawBitmap(
                        codice,
                        null,
                        Rect((595 - largo) / 2, (842 - alto) / 2,
                             (595 + largo) / 2, (842 + alto) / 2),
                        null,
                    )
                    val etichetta = Paint().apply {
                        color = Color.DKGRAY
                        textSize = 14f
                        textAlign = Paint.Align.CENTER
                    }
                    // Il numero sul foglio: chi le stampa deve poterle
                    // rimettere in ordine se gli cadono di mano.
                    pagina.canvas.drawText(
                        getString(R.string.trasferimento_pezzo, quale + 1, immagini.size),
                        297f, 800f, etichetta,
                    )
                    documento.finishPage(pagina)
                }
                contentResolver.openOutputStream(destinazione)?.use { documento.writeTo(it) }
                documento.close()
            },
            {
                avvisa(getString(R.string.qr_salvato))
            },
            { messaggio -> avvisa(messaggio) },
        )
    }

    private fun preparaCodici() {
        Dati.chiedi(
            {
                // I bitmap si generano qui, sul thread dei dati: sono immagini
                // grandi e farle mentre la giostra gira farebbe scattare tutto.
                Core.trasfPrepara().map { testo ->
                    Core.renderCode(testo, isQrcode = true).aBitmap()
                }
            },
            { generate ->
                if (generate.isEmpty()) {
                    avvisa(getString(R.string.trasferimento_niente_carte))
                    return@chiedi
                }
                immagini = generate
                mostrato = 0
                findViewById<View>(R.id.scelta).visibility = View.GONE
                findViewById<View>(R.id.vetrina).visibility = View.VISIBLE
                findViewById<View>(R.id.salva_qr).setOnClickListener {
                    salvaCodici.launch(Core.backupNome(Core.oggi())
                        .removeSuffix(".json") + "-codici.pdf")
                }
                alMassimoLaLuminosita()
                disegnaCodice()
                if (immagini.size > 1) {
                    orologio.postDelayed(giostra, 400)
                }
            },
            { messaggio -> avvisa(messaggio) },
        )
    }

    private fun disegnaCodice() {
        findViewById<ImageView>(R.id.codice).setImageBitmap(immagini[mostrato])
        findViewById<TextView>(R.id.contatore).text =
            if (immagini.size == 1) {
                getString(R.string.trasferimento_pezzo_unico)
            } else {
                getString(R.string.trasferimento_pezzo, mostrato + 1, immagini.size)
            }
    }

    /**
     * Le due strade, chieste prima di scrivere qualsiasi cosa.
     *
     * Il conteggio delle carte in arrivo si fa leggendo i pezzi senza toccare
     * il file: se la domanda dicesse un numero sbagliato, chi risponde
     * "azzera e sostituisci" perderebbe le sue per niente.
     */
    private fun chiediComeMetterle(pezzi: ArrayList<String>) {
        Dati.chiedi(
            { Core.trasfLeggi(pezzi.toTypedArray()).size },
            { quante ->
                if (quante == 0) {
                    avvisa(getString(R.string.trasferimento_niente_ricevuto))
                    return@chiedi
                }
                AlertDialog.Builder(this)
                    .setTitle(R.string.trasferimento_scelta_titolo)
                    .setMessage(getString(R.string.trasferimento_scelta_domanda, quante, mie))
                    .setNeutralButton(R.string.annulla, null)
                    .setNegativeButton(R.string.trasferimento_sostituisci) { _, _ ->
                        confermaSostituzione(pezzi, quante)
                    }
                    .setPositiveButton(R.string.trasferimento_aggiungi) { _, _ ->
                        applica(pezzi, azzera = false)
                    }
                    .show()
            },
            { messaggio -> avvisa(messaggio) },
        )
    }

    /** L'unica delle due strade da cui non si torna indietro: si chiede due volte. */
    private fun confermaSostituzione(pezzi: ArrayList<String>, quante: Int) {
        AlertDialog.Builder(this)
            .setTitle(R.string.trasferimento_sostituisci_titolo)
            .setMessage(getString(R.string.trasferimento_sostituisci_avviso, mie, quante))
            .setNegativeButton(R.string.annulla, null)
            .setPositiveButton(R.string.trasferimento_sostituisci) { _, _ ->
                applica(pezzi, azzera = true)
            }
            .show()
    }

    private fun applica(pezzi: ArrayList<String>, azzera: Boolean) {
        Dati.chiedi(
            { Core.trasfApplica(pezzi.toTypedArray(), azzera) },
            { quante ->
                setResult(Activity.RESULT_OK, Intent().putExtra(EXTRA_RICEVUTE, quante))
                finish()
            },
            { messaggio -> avvisa(messaggio) },
        )
    }

    private fun avvisa(messaggio: String) {
        Snackbar.make(findViewById(R.id.radice), messaggio, Snackbar.LENGTH_LONG).show()
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    override fun onDestroy() {
        super.onDestroy()
        orologio.removeCallbacks(giostra)
    }
}
