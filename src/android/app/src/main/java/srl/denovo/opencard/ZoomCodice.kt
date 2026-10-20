// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.annotation.SuppressLint
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.widget.ImageView

/**
 * Il pinch sull'immagine del codice: due dita la allargano o la stringono,
 * fra un minimo e la larghezza della colonna. L'altezza segue da sola, con
 * `adjustViewBounds`. La misura non si ricorda: alla prossima apertura il
 * codice torna a quella naturale.
 *
 * L'immagine sta dentro una NestedScrollView: appena c'è il secondo dito si
 * chiede al genitore di non intercettare, se no lo scorrimento si mangia il
 * gesto. Con un dito solo lo scorrimento resta suo.
 *
 * Un tocco solo, senza pinch, arriva all'immagine come un clic normale.
 */
class ZoomCodice(
    private val vista: ImageView,
    private val minimo: Int,
    massimo: Int,
) : View.OnTouchListener {

    private val massimo = maxOf(massimo, minimo)
    private var larghezza = 0

    private val rilevatore = ScaleGestureDetector(
        vista.context,
        object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(gesto: ScaleGestureDetector): Boolean {
                imposta((larghezza * gesto.scaleFactor).toInt())
                return true
            }
        },
    )

    private val tocco = GestureDetector(
        vista.context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onSingleTapUp(evento: MotionEvent): Boolean = vista.performClick()
        },
    )

    /** La larghezza in pixel, portata dentro i limiti. */
    fun imposta(nuova: Int) {
        larghezza = nuova.coerceIn(minimo, massimo)
        vista.layoutParams = vista.layoutParams.apply { width = larghezza }
    }

    // Il performClick lo fa il rilevatore del tocco, solo quando è un tocco.
    @SuppressLint("ClickableViewAccessibility")
    override fun onTouch(v: View, evento: MotionEvent): Boolean {
        if (evento.actionMasked == MotionEvent.ACTION_POINTER_DOWN) {
            v.parent.requestDisallowInterceptTouchEvent(true)
        }
        rilevatore.onTouchEvent(evento)
        // Il secondo dito annulla il tocco: un pinch non copia niente.
        tocco.onTouchEvent(evento)
        return true
    }
}
