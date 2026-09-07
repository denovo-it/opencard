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

/**
 * Le impostazioni: il backup nel cloud e la lingua.
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
