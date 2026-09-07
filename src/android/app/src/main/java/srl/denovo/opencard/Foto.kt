/*
 * SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

package srl.denovo.opencard

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File

/**
 * Le foto delle carte: fronte e retro.
 *
 * I byte stanno in file dentro la memoria privata dell'app, e nella carta
 * viaggia solo il nome. Metterle nel file delle carte le farebbe crescere da
 * qualche decina di kB a qualche MB per carta, e il passaggio a QR fra due
 * telefoni diventerebbe impossibile.
 *
 * I nomi seguono lo schema di Catima, `card_<id>_<lato>`, perché è la sola
 * cosa che serve per leggere un giorno il loro archivio con lo stesso codice
 * che legge il nostro. L'estensione no: loro scrivono PNG, qui si scrive JPEG,
 * perché la foto di una tessera in PNG pesa quattro o cinque volte tanto senza
 * dare niente in cambio. Chi legge guarda il nome che trova scritto nella
 * carta, quindi le due cose convivono.
 */
object Foto {

    /** Il lato lungo a cui si riducono le foto prima di salvarle. */
    private const val LATO_MASSIMO = 1600

    /** Qualità del JPEG: sopra il 90 il file cresce e l'occhio non se ne accorge. */
    private const val QUALITA = 85

    private fun cartella(contesto: Context): File =
        File(contesto.filesDir, "foto").apply { mkdirs() }

    fun nome(id: Int, fronte: Boolean): String =
        "card_${id}_${if (fronte) "front" else "back"}.jpg"

    /** Il file di una foto, dal nome che sta scritto nella carta. */
    fun file(contesto: Context, nome: String): File = File(cartella(contesto), nome)

    /**
     * Salva una foto e torna il nome da scrivere nella carta, oppure null se
     * la scrittura non riesce. Un file che c'era già viene sostituito: le foto
     * di una carta sono al massimo due.
     */
    fun salva(contesto: Context, immagine: Bitmap, id: Int, fronte: Boolean): String? {
        val comeSiChiama = nome(id, fronte)
        val dove = file(contesto, comeSiChiama)
        return try {
            dove.outputStream().use { immagine.compress(Bitmap.CompressFormat.JPEG, QUALITA, it) }
            comeSiChiama
        } catch (guasto: Exception) {
            dove.delete()
            null
        }
    }

    /**
     * La foto, decodificata già ridotta, o null se il file non c'è più.
     *
     * Si passa sempre da `inSampleSize`: una foto da 1600 pixel decodificata
     * intera sono otto MB di bitmap, e il riquadro del form ne mostra 400. Il
     * controllo del bundle se ne accorge e blocca il caricamento, ma il motivo
     * vero è che quei MB li paga il telefono a ogni apertura.
     */
    fun leggi(contesto: Context, nome: String, latoMassimo: Int = 1200): Bitmap? {
        if (nome.isEmpty()) {
            return null
        }
        val dove = file(contesto, nome)
        if (!dove.exists()) {
            return null
        }
        return try {
            val misura = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(dove.path, misura)
            val lato = maxOf(misura.outWidth, misura.outHeight)
            if (lato <= 0) {
                return null
            }
            var scala = 1
            while (lato / (scala * 2) >= latoMassimo) {
                scala *= 2
            }
            BitmapFactory.decodeFile(
                dove.path,
                BitmapFactory.Options().apply { inSampleSize = scala },
            )
        } catch (guasto: Exception) {
            null
        }
    }

    /** Riduce il lato lungo, così sul disco non finisce una foto da 12 megapixel. */
    fun riduci(immagine: Bitmap): Bitmap {
        val lato = maxOf(immagine.width, immagine.height)
        if (lato <= LATO_MASSIMO) {
            return immagine
        }
        val scala = LATO_MASSIMO.toFloat() / lato
        return Bitmap.createScaledBitmap(
            immagine,
            (immagine.width * scala).toInt(),
            (immagine.height * scala).toInt(),
            true,
        )
    }

    fun cancella(contesto: Context, nome: String) {
        if (nome.isNotEmpty()) {
            file(contesto, nome).delete()
        }
    }

    /** Tutte le foto, quando si azzerano le carte. */
    fun cancellaTutte(contesto: Context) {
        cartella(contesto).listFiles()?.forEach { it.delete() }
    }

    /**
     * Le foto di una carta cancellata. Si chiama dopo la cancellazione: i file
     * restati indietro non li guarderebbe più nessuno e occuperebbero spazio
     * per sempre.
     */
    fun cancellaDiCarta(contesto: Context, id: Int) {
        cancella(contesto, nome(id, fronte = true))
        cancella(contesto, nome(id, fronte = false))
    }
}
