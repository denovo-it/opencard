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
 * Gesti sull'immagine del codice alla cassa: pinch per il formato, un dito per
 * spostarlo in verticale, doppio tocco per ruotarlo di 90 gradi, tocco singolo
 * per copiare il numero.
 *
 * L'immagine sta dentro una NestedScrollView. Appena il dito tocca l'immagine
 * si chiede al genitore di non intercettare, cosi' lo scorrimento della pagina
 * non ruba il gesto. Lo scorrimento resta disponibile toccando fuori dal codice.
 *
 * Al doppio tocco l'immagine ruota di 90 gradi in senso orario, con
 * un'animazione breve. Il bottone nella barra fa la stessa cosa.
 *
 * Niente si ricorda fra un'apertura e l'altra: [azzera] riporta tutto come
 * all'inizio.
 */
class ZoomCodice(
    private val vista: ImageView,
    private val minimo: Int,
    massimo: Int,
) : View.OnTouchListener {

    private val massimo = maxOf(massimo, minimo)
    private var larghezza = 0
    private var rotazione = 0f

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
            override fun onSingleTapConfirmed(evento: MotionEvent): Boolean =
                vista.performClick()

            override fun onDoubleTap(evento: MotionEvent): Boolean {
                ruota()
                return true
            }

            override fun onScroll(
                e1: MotionEvent?,
                e2: MotionEvent,
                dx: Float,
                dy: Float,
            ): Boolean {
                vista.translationY -= dy
                return true
            }
        },
    )

    fun imposta(nuova: Int) {
        larghezza = nuova.coerceIn(minimo, massimo)
        vista.layoutParams = vista.layoutParams.apply { width = larghezza }
    }

    fun ruota() {
        rotazione = (rotazione + 90f) % 360f
        vista.animate().rotation(rotazione).setDuration(200).start()
    }

    fun azzera() {
        rotazione = 0f
        vista.rotation = 0f
        vista.translationY = 0f
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouch(v: View, evento: MotionEvent): Boolean {
        when (evento.actionMasked) {
            MotionEvent.ACTION_DOWN,
            MotionEvent.ACTION_POINTER_DOWN ->
                v.parent.requestDisallowInterceptTouchEvent(true)
        }
        rilevatore.onTouchEvent(evento)
        tocco.onTouchEvent(evento)
        return true
    }
}
