// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Activity
import android.graphics.Bitmap
import android.os.Bundle
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView
import kotlin.math.sqrt

/**
 * Il codice della carta, da far leggere alla cassa. Si chiude scorrendo verso
 * destra, come ogni schermata di Wear OS.
 *
 * Lo schermo va al massimo finché la schermata è aperta: al lettore serve il
 * contrasto, e all'orologio la luminosità di solito è bassa.
 */
class CodiceActivity : Activity() {

    companion object {
        const val ID = "id"
    }

    override fun onCreate(stato: Bundle?) {
        super.onCreate(stato)
        setContentView(R.layout.activity_codice)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.attributes = window.attributes.apply {
            screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
        }

        val id = intent.getIntExtra(ID, 0)
        Dati.chiedi(
            {
                val carta = Core.get(id)
                Triple(
                    carta,
                    Core.renderCodeSimbologia(carta.code, carta.simbologia),
                    Core.groupedCode(carta.code),
                )
            },
            { (carta, immagine, numero) ->
                findViewById<TextView>(R.id.etichetta).text = carta.label
                findViewById<TextView>(R.id.codice).text = numero
                findViewById<ImageView>(R.id.immagine)
                    .setImageBitmap(adattaAlCerchio(immagine.aBitmap(), carta.simbologia))
            },
            { finish() },
        )
    }

    /**
     * Il codice dentro il cerchio dello schermo, senza sfocarlo.
     *
     * Le barre restano pixel per pixel come le disegna il core, 4 px per
     * modulo: sul Watch7 da 44 mm sono 0,32 mm, la misura nominale della
     * norma. Per entrare nel cerchio si accorciano in altezza, non in
     * larghezza: una fascia orizzontale qualsiasi di un codice a barre è il
     * codice intero. I codici quadrati e a più righe si ingrandiscono di un
     * fattore intero, a pixel grossi, fino al quadrato inscritto nel cerchio.
     * Solo un codice più largo dello schermo si riduce, e lo fa l'ImageView.
     */
    private fun adattaAlCerchio(bitmap: Bitmap, simbologia: Int): Bitmap {
        val metriche = resources.displayMetrics
        val diametro = minOf(metriche.widthPixels, metriche.heightPixels)
        val raggio = diametro / 2.0

        if (Simbologie.eUnaRiga(simbologia)) {
            if (bitmap.width >= diametro) return bitmap
            val semiLarghezza = bitmap.width / 2.0
            val altezzaMassima = (2 * sqrt(raggio * raggio - semiLarghezza * semiLarghezza)).toInt()
            if (bitmap.height <= altezzaMassima) return bitmap
            return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, altezzaMassima)
        }

        val lato = (diametro / sqrt(2.0)).toInt()
        val fattore = minOf(lato / bitmap.width, lato / bitmap.height)
        if (fattore <= 1) return bitmap
        return Bitmap.createScaledBitmap(bitmap, bitmap.width * fattore, bitmap.height * fattore, false)
    }
}
