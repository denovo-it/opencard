/*
 * SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

package srl.denovo.opencard

import android.os.Bundle
import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import com.google.android.material.materialswitch.MaterialSwitch
import com.google.android.material.snackbar.Snackbar

/**
 * Le impostazioni: il backup nel cloud, la lingua e l'azzeramento.
 *
 * La riga sotto l'interruttore cambia con la scelta invece di stare ferma:
 * quello che succede acceso e quello che succede spento sono due cose diverse,
 * e scriverle tutte e due insieme obbligherebbe a leggerle tutte e due per
 * capire in quale dei due casi si è.
 */
class ImpostazioniActivity : AppCompatActivity() {

    override fun onCreate(statoSalvato: Bundle?) {
        super.onCreate(statoSalvato)
        setContentView(R.layout.activity_impostazioni)
        setSupportActionBar(findViewById(R.id.barra))
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        val spiega = findViewById<TextView>(R.id.backup_cloud_spiega)
        val interruttore = findViewById<MaterialSwitch>(R.id.backup_cloud)

        interruttore.isChecked = Impostazioni.backupNelCloud(this)
        spiega.setText(testo(interruttore.isChecked))

        interruttore.setOnCheckedChangeListener { _, acceso ->
            Impostazioni.cambiaBackupNelCloud(this, acceso)
            spiega.setText(testo(acceso))
        }

        findViewById<View>(R.id.riga_lingua).setOnClickListener { scegliLingua() }
        mostraLingua()

        findViewById<View>(R.id.riga_azzera).setOnClickListener { confermaAzzeramento() }
    }

    /**
     * Azzera le carte, con la domanda prima.
     *
     * La domanda dice due cose: che non si torna indietro, e che il backup si
     * fa dal menu dell'elenco. Chi arriva a questa voce per sbaglio deve
     * trovare la strada per non perdere niente.
     */
    private fun confermaAzzeramento() {
        AlertDialog.Builder(this)
            .setTitle(R.string.azzera_titolo)
            .setMessage(R.string.azzera_avviso)
            .setNegativeButton(R.string.annulla, null)
            .setPositiveButton(R.string.azzera_conferma) { _, _ -> azzera() }
            .show()
    }

    private fun azzera() {
        Dati.fai(
            {
                Core.azzeraTutto()
                // Le foto non le tocca il core: senza questa resterebbero file
                // di carte che non esistono piu'.
                Foto.cancellaTutte(this)
                // E i file temporanei: le copie delle immagini da cui si legge
                // un codice finiscono in cache, e se una lettura si interrompe
                // possono restare li'. Le carte non ci sono mai state, ma chi
                // chiede di cancellare tutto intende anche quelli.
                cacheDir.listFiles()?.forEach { it.deleteRecursively() }
            },
            {
                // L'elenco si rilegge da solo tornando indietro, perche'
                // MainActivity ricarica in onResume.
                WidgetCarta.aggiornaTutti(this)
                avvisa(getString(R.string.azzerate))
            },
            { avvisa(it) },
        )
    }

    private fun avvisa(messaggio: String) {
        Snackbar.make(findViewById(R.id.radice), messaggio, Snackbar.LENGTH_LONG).show()
    }

    /** Le sigle, non i nomi per esteso: due lettere si riconoscono sempre. */
    private val codici = listOf("", "it", "en")
    private val sigle = listOf(null, "IT", "EN")

    private fun quale(): Int {
        val adesso = AppCompatDelegate.getApplicationLocales()
            .toLanguageTags().substringBefore('-')
        return codici.indexOf(adesso).let { if (it < 0) 0 else it }
    }

    private fun mostraLingua() {
        val scelta = quale()
        findViewById<TextView>(R.id.lingua_adesso).text =
            sigle[scelta] ?: getString(R.string.lingua_sistema)
    }

    private fun scegliLingua() {
        val nomi = arrayOf(getString(R.string.lingua_sistema), "IT", "EN")

        AlertDialog.Builder(this)
            .setTitle(R.string.lingua)
            .setSingleChoiceItems(nomi, quale()) { finestra, scelta ->
                AppCompatDelegate.setApplicationLocales(
                    if (codici[scelta].isEmpty()) {
                        LocaleListCompat.getEmptyLocaleList()
                    } else {
                        LocaleListCompat.forLanguageTags(codici[scelta])
                    }
                )
                finestra.dismiss()
                // La schermata si ricrea da sola con la lingua nuova: questa
                // riga serve ai telefoni da Android 13 in su, dove il cambio
                // passa dal sistema e la ricreazione può arrivare dopo.
                mostraLingua()
            }
            .setNegativeButton(R.string.annulla, null)
            .show()
    }

    private fun testo(acceso: Boolean) =
        if (acceso) R.string.backup_cloud_acceso_android else R.string.backup_cloud_spento_android

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }
}
