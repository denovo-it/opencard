// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import android.graphics.Typeface

/**
 * Il poco Markdown che serve allo storico delle revisioni.
 *
 * Non e' un interprete completo e non deve diventarlo: il changelog usa titoli,
 * punti elenco, grassetto e qualche nota, e basta riconoscere quelli. Mostrarlo
 * come testo grezzo lascerebbe i trattini e gli asterischi sotto gli occhi di
 * chi legge.
 */
object Markdown {

    /** Un pezzo di documento, gia' deciso come va mostrato. */
    sealed class Blocco {
        data class Titolo(val testo: CharSequence) : Blocco()
        data class Punto(val testo: CharSequence) : Blocco()
        data class Nota(val testo: CharSequence) : Blocco()
        data class Paragrafo(val testo: CharSequence) : Blocco()
    }

    fun analizza(documento: String): List<Blocco> {
        val blocchi = mutableListOf<Blocco>()

        documento.lines().forEach { riga ->
            val pulita = riga.trim()
            when {
                pulita.isEmpty() -> Unit
                pulita.startsWith("## ") ->
                    blocchi.add(Blocco.Titolo(inline(pulita.removePrefix("## "))))
                pulita.startsWith("# ") ->
                    blocchi.add(Blocco.Titolo(inline(pulita.removePrefix("# "))))
                pulita.startsWith("- ") ->
                    blocchi.add(Blocco.Punto(inline(pulita.removePrefix("- "))))
                pulita.startsWith("> ") ->
                    blocchi.add(Blocco.Nota(inline(pulita.removePrefix("> "))))
                else -> blocchi.add(Blocco.Paragrafo(inline(pulita)))
            }
        }
        return blocchi
    }

    /**
     * Grassetto fra doppi asterischi e codice fra apici inversi.
     *
     * Si scorre una volta sola, tenendo da parte dove ogni pezzo comincia:
     * cosi' non serve nessuna espressione regolare e le marcature spaiate
     * restano testo, invece di far sparire meta' riga.
     */
    fun inline(testo: String): CharSequence {
        val uscita = SpannableStringBuilder()
        var i = 0

        while (i < testo.length) {
            when {
                testo.startsWith("**", i) -> {
                    val fine = testo.indexOf("**", i + 2)
                    if (fine < 0) {
                        uscita.append(testo.substring(i))
                        i = testo.length
                    } else {
                        val inizio = uscita.length
                        uscita.append(testo, i + 2, fine)
                        uscita.setSpan(
                            StyleSpan(Typeface.BOLD), inizio, uscita.length,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                        )
                        i = fine + 2
                    }
                }
                testo[i] == '`' -> {
                    val fine = testo.indexOf('`', i + 1)
                    if (fine < 0) {
                        uscita.append(testo.substring(i))
                        i = testo.length
                    } else {
                        val inizio = uscita.length
                        uscita.append(testo, i + 1, fine)
                        uscita.setSpan(
                            TypefaceSpan("monospace"), inizio, uscita.length,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                        )
                        i = fine + 1
                    }
                }
                else -> {
                    uscita.append(testo[i])
                    i++
                }
            }
        }
        return uscita
    }
}
