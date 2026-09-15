// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.annotation.SuppressLint
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

    /** La larghezza in pixel, portata dentro i limiti. */
    fun imposta(nuova: Int) {
        larghezza = nuova.coerceIn(minimo, massimo)
        vista.layoutParams = vista.layoutParams.apply { width = larghezza }
    }

    // Niente performClick: sull'immagine non c'è un tocco da fare.
    @SuppressLint("ClickableViewAccessibility")
    override fun onTouch(v: View, evento: MotionEvent): Boolean {
        if (evento.actionMasked == MotionEvent.ACTION_POINTER_DOWN) {
            v.parent.requestDisallowInterceptTouchEvent(true)
        }
        rilevatore.onTouchEvent(evento)
        return true
    }
}
