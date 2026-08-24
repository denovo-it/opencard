// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Size
import android.view.View
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors

/**
 * Lettura di codici con la fotocamera, in due modi.
 *
 * Normale: chiude appena riconosce qualcosa e restituisce il codice a chi
 * l'ha aperta, insieme al tipo, così il form non deve indovinare se è un QR
 * o un barcode.
 *
 * Raccolta: resta aperta e mette insieme i codici di un passaggio di carte,
 * che possono essere più d'uno e arrivare in qualsiasi ordine. Chiude quando
 * il core dice che ci sono tutti.
 */
class ScannerActivity : AppCompatActivity() {

    private val analizzatore = Executors.newSingleThreadExecutor()
    private val lettore = BarcodeScanning.getClient()

    /** Una lettura sola: senza questo si tornerebbe indietro più volte. */
    private var giaLetto = false

    /** Vero quando si raccolgono i pezzi di un passaggio di carte. */
    private var raccolta = false

    /** I testi letti finora, senza doppioni e nell'ordine in cui sono arrivati. */
    private val pezzi = LinkedHashSet<String>()

    /** Una verifica alla volta: i fotogrammi arrivano molto più in fretta. */
    private var inCorso = false

    /** L'ultimo messaggio mostrato, per non ripeterlo a ogni fotogramma. */
    private var ultimoAvviso: String? = null

    /** Il codice che sta accumulando conferme, e la sua simbologia. */
    private var candidato: String? = null
    private var candidatoFormato = 0

    /** Quante volte di fila è arrivato uguale, e quando è comparso la prima. */
    private var conferme = 0
    private var primaLettura = 0L

    /** Quando è partita la scansione, per l'avviso a chi non conclude. */
    private var inizioScansione = 0L

    private val chiediPermesso = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { concesso ->
        if (concesso) avvia() else mostraRifiuto()
    }

    companion object {
        /** Letture identiche di fila che rendono buono un codice. */
        private const val CONFERME = 3

        /** Distanza minima fra la prima e l'ultima, in millisecondi. */
        private const val ATTESA_MINIMA_MS = 300L

        /** Dopo quanto si dice all'utente di tenere fermo il telefono. */
        private const val AVVISO_MS = 2500L

        const val EXTRA_CODICE = "codice"
        const val EXTRA_QRCODE = "qrcode"

        /** Acceso, la schermata raccoglie i pezzi invece di chiudersi al primo. */
        const val EXTRA_TRASFERIMENTO = "trasferimento"

        /** I testi dei QR raccolti, restituiti a passaggio completo. */
        const val EXTRA_PEZZI = "pezzi"

        fun intentTrasferimento(contesto: android.content.Context) =
            Intent(contesto, ScannerActivity::class.java)
                .putExtra(EXTRA_TRASFERIMENTO, true)
    }

    override fun onCreate(statoSalvato: Bundle?) {
        super.onCreate(statoSalvato)
        setContentView(R.layout.activity_scanner)
        setSupportActionBar(findViewById(R.id.barra))
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        raccolta = intent.getBooleanExtra(EXTRA_TRASFERIMENTO, false)
        title = getString(
            if (raccolta) R.string.trasferimento_ricevi else R.string.inquadra_codice
        )
        if (raccolta) {
            findViewById<TextView>(R.id.progresso).apply {
                visibility = View.VISIBLE
                setText(R.string.trasferimento_attesa)
            }
        }

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED
        ) {
            avvia()
        } else {
            chiediPermesso.launch(Manifest.permission.CAMERA)
        }
    }

    private fun mostraRifiuto() {
        // Senza fotocamera la carta si aggiunge lo stesso, scrivendo il codice
        // a mano: si torna indietro e basta, senza insistere col permesso.
        findViewById<TextView>(R.id.avviso).apply {
            visibility = View.VISIBLE
            setText(R.string.fotocamera_negata)
        }
    }

    private fun avvia() {
        val anteprima = findViewById<PreviewView>(R.id.anteprima)
        anteprima.visibility = View.VISIBLE

        val futuro = ProcessCameraProvider.getInstance(this)
        futuro.addListener({
            val fornitore = futuro.get()

            val vista = Preview.Builder().build().also {
                it.surfaceProvider = anteprima.surfaceProvider
            }

            val analisi = ImageAnalysis.Builder()
                .setTargetResolution(Size(1280, 720))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()

            analisi.setAnalyzer(analizzatore) { fotogramma -> esamina(fotogramma) }

            try {
                fornitore.unbindAll()
                fornitore.bindToLifecycle(
                    this, CameraSelector.DEFAULT_BACK_CAMERA, vista, analisi
                )
            } catch (e: Exception) {
                findViewById<TextView>(R.id.avviso).apply {
                    visibility = View.VISIBLE
                    setText(R.string.fotocamera_non_disponibile)
                }
            }
        }, ContextCompat.getMainExecutor(this))
    }

    @androidx.camera.core.ExperimentalGetImage
    private fun esamina(fotogramma: androidx.camera.core.ImageProxy) {
        val immagine = fotogramma.image
        if (immagine == null || giaLetto) {
            fotogramma.close()
            return
        }
        val ingresso = InputImage.fromMediaImage(
            immagine, fotogramma.imageInfo.rotationDegrees
        )
        lettore.process(ingresso)
            .addOnSuccessListener { codici ->
                if (raccolta) {
                    raccogli(codici.mapNotNull { it.rawValue }.filter { it.isNotEmpty() })
                    return@addOnSuccessListener
                }
                val primo = codici.firstOrNull { !it.rawValue.isNullOrEmpty() }
                if (primo != null && !giaLetto) {
                    conferma(primo)
                }
            }
            .addOnCompleteListener { fotogramma.close() }
    }

    /**
     * Una lettura sola non basta.
     *
     * Col telefono in movimento il lettore restituisce numeri plausibili ma
     * sbagliati, e su una tessera un numero sbagliato non si vede: si scopre
     * alla cassa. Si prende per buono un codice solo quando arriva **tre volte
     * di fila identico**, stesso testo e stessa simbologia, e quando fra la
     * prima e la terza lettura sono passati almeno 300 ms.
     *
     * I 300 ms non sono un'attesa aggiunta: sono un pavimento. Senza, tre
     * fotogrammi dello stesso istante di sfocatura passerebbero il controllo,
     * perché sono lo stesso errore contato tre volte. Col codice fermo il
     * lettore ne consegna una trentina al secondo, quindi la conferma arriva
     * in poco più di quel terzo di secondo.
     *
     * Un fotogramma senza codici non azzera niente: capita al buio o mentre si
     * mette a fuoco, e non contraddice le letture precedenti. Azzera solo un
     * codice diverso.
     */
    private fun conferma(codice: Barcode) {
        val valore = codice.rawValue ?: return
        val adesso = android.os.SystemClock.elapsedRealtime()

        // L'avviso prima di tutto: il caso in cui serve davvero è proprio
        // quello in cui le letture continuano a cambiare e non si conferma
        // niente, cioè quando da qui si esce subito.
        if (inizioScansione == 0L) {
            inizioScansione = adesso
        } else if (adesso - inizioScansione >= AVVISO_MS) {
            mostraTieniFermo()
        }

        if (valore != candidato || codice.format != candidatoFormato) {
            candidato = valore
            candidatoFormato = codice.format
            conferme = 1
            primaLettura = adesso
            return
        }

        conferme++
        if (conferme >= CONFERME && adesso - primaLettura >= ATTESA_MINIMA_MS) {
            giaLetto = true
            restituisci(valore, codice.format == Barcode.FORMAT_QR_CODE)
        }
    }

    private fun mostraTieniFermo() {
        val testo = getString(R.string.scanner_tieni_fermo)
        if (testo == ultimoAvviso) return
        ultimoAvviso = testo
        findViewById<TextView>(R.id.progresso).apply {
            visibility = View.VISIBLE
            text = testo
        }
    }

    /**
     * Un giro di codici letti dal fotogramma.
     *
     * Chi dei due telefoni sta mostrando fa girare i codici da solo, quindi qui
     * si accumula e basta: i doppioni li scarta il Set, e quello che non è di
     * OpenCard lo ignora il core senza dire niente. Il conteggio lo tiene il
     * core, che è l'unico a sapere quanti pezzi ha il passaggio.
     */
    private fun raccogli(letti: List<String>) {
        if (giaLetto || inCorso) return
        if (!pezzi.addAll(letti)) return

        inCorso = true
        val adesso = pezzi.toTypedArray()
        Dati.chiedi(
            { Core.trasfStato(adesso) },
            { stato ->
                inCorso = false
                val ricevuti = stato[0]
                val totale = stato[1]
                if (totale == 0) {
                    return@chiedi
                }
                ultimoAvviso = null
                findViewById<TextView>(R.id.progresso).text =
                    getString(R.string.trasferimento_raccolta, ricevuti, totale)
                if (ricevuti >= totale && !giaLetto) {
                    giaLetto = true
                    restituisciPezzi()
                }
            },
            { messaggio ->
                inCorso = false
                // Pezzi di due passaggi diversi, o un formato che questa
                // versione non conosce: si riparte da zero, altrimenti i
                // codici buoni che arrivano dopo restano attaccati a quelli
                // vecchi e non si completa mai.
                pezzi.clear()
                if (messaggio != ultimoAvviso) {
                    ultimoAvviso = messaggio
                    findViewById<TextView>(R.id.progresso).text = messaggio
                }
            },
        )
    }

    private fun restituisciPezzi() {
        val esito = Intent().putStringArrayListExtra(EXTRA_PEZZI, ArrayList(pezzi))
        setResult(Activity.RESULT_OK, esito)
        finish()
    }

    private fun restituisci(codice: String, qrcode: Boolean) {
        val esito = Intent()
            .putExtra(EXTRA_CODICE, codice)
            .putExtra(EXTRA_QRCODE, qrcode)
        setResult(Activity.RESULT_OK, esito)
        finish()
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    override fun onDestroy() {
        super.onDestroy()
        analizzatore.shutdown()
        lettore.close()
    }
}
