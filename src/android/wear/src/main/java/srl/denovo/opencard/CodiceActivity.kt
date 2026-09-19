// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Bundle
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.roundToInt

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

        /**
         * Il codice, zona bianca compresa, sta dentro un cerchio al 90% del
         * raggio: sul Watch7 da 44 mm resta libero un anello di 24 px, 2 mm.
         */
        private const val RAGGIO_UTILE = 0.9

        /** Il core disegna a scala 4, cioè 8 px per modulo. */
        private const val PIXEL_PER_MODULO = 8

        /** Zona bianca ai lati dei codici a barre, in moduli: 10, come Code 128, Code 39 e ITF. */
        private const val QUIETE_BARRE = 10

        /** Zona bianca intorno ai codici quadrati e a più righe, in moduli: 4, come il QR. */
        private const val QUIETE_QUADRATI = 4
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
     * Il codice dentro il cerchio dello schermo, lontano dal bordo.
     *
     * Il core disegna 8 px per modulo e mette la zona bianca solo a EAN e
     * UPC: qui si aggiunge quella che manca, ai lati dei codici a barre, tutto
     * intorno ai quadrati e a quelli a più righe. Poi il rettangolo, zona
     * bianca compresa, si iscrive nel cerchio utile. Col codice fino al bordo
     * tondo, con gli angoli sulla cornice nera, non tutti i lettori lo
     * leggevano.
     *
     * I codici a barre si rimpiccioliscono con il filtro, come faceva prima
     * l'ImageView: un EAN-13 sul Watch7 da 44 mm esce a 3,4 px per modulo,
     * 0,28 mm, sopra il minimo della norma. Gli altri tengono un numero intero
     * di pixel per modulo, così i moduli restano tutti uguali e netti.
     */
    private fun adattaAlCerchio(bitmap: Bitmap, simbologia: Int): Bitmap {
        val metriche = resources.displayMetrics
        val diametro = minOf(metriche.widthPixels, metriche.heightPixels) * RAGGIO_UTILE

        val unaRiga = Simbologie.eUnaRiga(simbologia)
        val bordoX = when {
            !unaRiga -> QUIETE_QUADRATI
            Simbologie.haLaSuaQuiete(simbologia) -> 0
            else -> QUIETE_BARRE
        } * PIXEL_PER_MODULO
        val bordoY = if (unaRiga) 0 else QUIETE_QUADRATI * PIXEL_PER_MODULO
        val larghezza = bitmap.width + 2 * bordoX
        val altezza = bitmap.height + 2 * bordoY

        var scala = diametro / hypot(larghezza.toDouble(), altezza.toDouble())
        if (!unaRiga) {
            scala = maxOf(1.0, floor(scala * PIXEL_PER_MODULO)) / PIXEL_PER_MODULO
        }

        val adattato = Bitmap.createBitmap(
            (larghezza * scala).roundToInt(),
            (altezza * scala).roundToInt(),
            Bitmap.Config.ARGB_8888,
        )
        val tela = Canvas(adattato)
        tela.drawColor(Color.WHITE)
        val dove = RectF(
            (bordoX * scala).toFloat(),
            (bordoY * scala).toFloat(),
            ((bordoX + bitmap.width) * scala).toFloat(),
            ((bordoY + bitmap.height) * scala).toFloat(),
        )
        tela.drawBitmap(bitmap, null, dove, Paint().apply { isFilterBitmap = unaRiga })
        return adattato
    }
}
