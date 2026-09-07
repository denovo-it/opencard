/*
 * SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

package srl.denovo.opencard

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Matrix
import android.graphics.RectF
import android.util.AttributeSet
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import androidx.appcompat.widget.AppCompatImageView

/**
 * L'immagine che si ingrandisce con due dita e si sposta con uno.
 *
 * È scritta qui invece di aggiungere una libreria: serve una foto che si
 * ingrandisce, non un visore completo, e ogni libreria in più va poi elencata
 * nella schermata Informazioni e tenuta aggiornata.
 *
 * Regole: la foto parte intera dentro lo schermo, non si rimpicciolisce sotto
 * quella misura e non si ingrandisce oltre cinque volte. Un doppio tocco fa
 * l'andata e ritorno fra intera e tre volte. Quando è ingrandita, il bordo non
 * si stacca mai dallo schermo: si vede sempre foto, mai fondo.
 */
class VistaZoom @JvmOverloads constructor(
    contesto: Context,
    attributi: AttributeSet? = null,
    stile: Int = 0,
) : AppCompatImageView(contesto, attributi, stile) {

    private val matrice = Matrix()
    private val valori = FloatArray(9)

    /** La scala a cui la foto sta esattamente dentro lo schermo. */
    private var scalaBase = 1f
    private var scalaMassima = 5f

    private val conDueDita = ScaleGestureDetector(
        contesto,
        object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(gesto: ScaleGestureDetector): Boolean {
                ingrandisci(gesto.scaleFactor, gesto.focusX, gesto.focusY)
                return true
            }
        },
    )

    private val conUnDito = GestureDetector(
        contesto,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onDoubleTap(evento: MotionEvent): Boolean {
                val quantoSiamo = scalaOra()
                val voluta = if (quantoSiamo > scalaBase * 1.2f) scalaBase else scalaBase * 3f
                ingrandisci(voluta / quantoSiamo, evento.x, evento.y)
                return true
            }

            override fun onScroll(
                giu: MotionEvent?,
                ora: MotionEvent,
                spostamentoX: Float,
                spostamentoY: Float,
            ): Boolean {
                matrice.postTranslate(-spostamentoX, -spostamentoY)
                rimettiInRiga()
                return true
            }
        },
    )

    init {
        scaleType = ScaleType.MATRIX
        isClickable = true
    }

    override fun onSizeChanged(largo: Int, alto: Int, primaLargo: Int, primaAlto: Int) {
        super.onSizeChanged(largo, alto, primaLargo, primaAlto)
        adatta()
    }

    override fun setImageBitmap(immagine: android.graphics.Bitmap?) {
        super.setImageBitmap(immagine)
        adatta()
    }

    /** Rimette la foto intera al centro: è lo stato di partenza. */
    private fun adatta() {
        val disegno = drawable ?: return
        if (width == 0 || height == 0) {
            return
        }
        val largoFoto = disegno.intrinsicWidth.toFloat()
        val altoFoto = disegno.intrinsicHeight.toFloat()
        if (largoFoto <= 0f || altoFoto <= 0f) {
            return
        }
        scalaBase = minOf(width / largoFoto, height / altoFoto)
        scalaMassima = scalaBase * 5f
        matrice.reset()
        matrice.postScale(scalaBase, scalaBase)
        matrice.postTranslate(
            (width - largoFoto * scalaBase) / 2f,
            (height - altoFoto * scalaBase) / 2f,
        )
        imageMatrix = matrice
    }

    private fun scalaOra(): Float {
        matrice.getValues(valori)
        return valori[Matrix.MSCALE_X]
    }

    private fun ingrandisci(fattore: Float, centroX: Float, centroY: Float) {
        val adesso = scalaOra()
        val voluta = (adesso * fattore).coerceIn(scalaBase, scalaMassima)
        if (adesso == 0f) {
            return
        }
        matrice.postScale(voluta / adesso, voluta / adesso, centroX, centroY)
        rimettiInRiga()
    }

    /**
     * Riporta la foto dentro i bordi.
     *
     * Quando è più piccola dello schermo su un lato resta centrata; quando è
     * più grande, il bordo si ferma contro quello dello schermo invece di
     * lasciare una striscia di fondo.
     */
    private fun rimettiInRiga() {
        val disegno = drawable ?: return
        val bordi = RectF(0f, 0f, disegno.intrinsicWidth.toFloat(), disegno.intrinsicHeight.toFloat())
        matrice.mapRect(bordi)

        var spostaX = 0f
        var spostaY = 0f
        if (bordi.width() <= width) {
            spostaX = (width - bordi.width()) / 2f - bordi.left
        } else if (bordi.left > 0) {
            spostaX = -bordi.left
        } else if (bordi.right < width) {
            spostaX = width - bordi.right
        }
        if (bordi.height() <= height) {
            spostaY = (height - bordi.height()) / 2f - bordi.top
        } else if (bordi.top > 0) {
            spostaY = -bordi.top
        } else if (bordi.bottom < height) {
            spostaY = height - bordi.bottom
        }

        matrice.postTranslate(spostaX, spostaY)
        imageMatrix = matrice
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(evento: MotionEvent): Boolean {
        // Finche' la foto e' ingrandita, chi sta sopra (il pager, la schermata
        // che scorre) non deve rubare il dito: si sposta la foto, non la pagina.
        parent?.requestDisallowInterceptTouchEvent(scalaOra() > scalaBase * 1.01f)
        conDueDita.onTouchEvent(evento)
        conUnDito.onTouchEvent(evento)
        return true
    }
}
