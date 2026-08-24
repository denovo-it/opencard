// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/**
 * Schermata di benvenuto: marchio, nome e versione.
 *
 * Compare al primo avvio e basta. Si rivede quando si vuole, toccando il logo
 * nella schermata informativa: è l'unico posto da cui si può richiamare.
 */
class SplashActivity : AppCompatActivity() {

    private val principale = Handler(Looper.getMainLooper())
    private var prosegui: Runnable? = null

    companion object {
        private const val DURATA_MS = 3000L
        private const val EXTRA_SOLO_MOSTRA = "soloMostra"

        /** Richiamo volontario dalla schermata informativa: al termine torna indietro. */
        fun intentRivedi(contesto: Context) =
            Intent(contesto, SplashActivity::class.java).putExtra(EXTRA_SOLO_MOSTRA, true)
    }

    override fun onCreate(statoSalvato: Bundle?) {
        super.onCreate(statoSalvato)

        val soloMostra = intent.getBooleanExtra(EXTRA_SOLO_MOSTRA, false)

        // Dal secondo avvio in poi si va dritti alle carte, senza far
        // lampeggiare il benvenuto.
        if (!soloMostra && !Core.isFirstRun()) {
            startActivity(Intent(this, MainActivity::class.java))
            finish()
            return
        }

        setContentView(R.layout.activity_splash)

        findViewById<TextView>(R.id.versione).text =
            if (CANALE != null) {
                getString(
                    R.string.versione_e_build_canale,
                    BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, CANALE.uppercase(),
                )
            } else {
                getString(
                    R.string.versione_e_build,
                    BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE,
                )
            }

        prosegui = Runnable {
            if (soloMostra) {
                finish()
            } else {
                Core.markFirstRunDone()
                startActivity(Intent(this, MainActivity::class.java))
                finish()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Il conteggio parte quando la schermata è davvero a video: partendo
        // dalla costruzione, il tempo di disegno finirebbe dentro i tre secondi.
        prosegui?.let { principale.postDelayed(it, DURATA_MS) }
    }

    override fun onPause() {
        super.onPause()
        prosegui?.let { principale.removeCallbacks(it) }
    }
}
