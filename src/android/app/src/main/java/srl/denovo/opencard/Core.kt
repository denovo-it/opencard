// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.graphics.Bitmap
import android.graphics.Color
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Una carta come la tiene il core. */
data class Carta(
    val id: Int,
    val label: String,
    val code: String,
    val isQrcode: Boolean,
    /** Colore da usare: quello scelto a mano, oppure quello che spetta all'id. */
    val colore: String,
    /** Vero se il colore l'ha scelto l'utente, non l'id. */
    val coloreScelto: Boolean,
    val disposable: Boolean,
    /** Preferita: compare anche nella scheda con la stella. */
    val preferita: Boolean,
)

/** Immagine di un codice, come esce dal core: pixel ARGB. */
class ImmagineCodice(val larghezza: Int, val altezza: Int, val pixel: IntArray) {
    fun aBitmap(): Bitmap =
        Bitmap.createBitmap(pixel, larghezza, altezza, Bitmap.Config.ARGB_8888)
}

/** Un colore illeggibile nel file non deve far cadere l'interfaccia. */
fun coloreCarta(esadecimale: String): Int = try {
    Color.parseColor(esadecimale)
} catch (e: IllegalArgumentException) {
    Color.parseColor("#1E88E5")
}

/** Errore del core, col messaggio già pronto da mostrare. */
class OpenCardException(messaggio: String) : Exception(messaggio)

/**
 * Il core in C.
 *
 * Tutte le chiamate leggono o scrivono il file dei dati, quindi vanno fatte
 * fuori dal thread dell'interfaccia. Ci pensa [Dati].
 */
object Core {
    init {
        System.loadLibrary("opencardcore")
    }

    @JvmStatic external fun storeInit(directory: String)
    @JvmStatic external fun isFirstRun(): Boolean
    @JvmStatic external fun markFirstRunDone()

    @JvmStatic external fun getAll(): Array<Carta>
    @JvmStatic external fun getGruppo(disposable: Boolean): Array<Carta>

    /** Le carte con la stella, dei due gruppi insieme. */
    @JvmStatic external fun getPreferite(): Array<Carta>

    /** Accende o spegne la stella, lasciando il resto della carta com'è. */
    @JvmStatic external fun setPreferita(id: Int, preferita: Boolean)
    @JvmStatic external fun get(id: Int): Carta
    @JvmStatic external fun nextId(): Int

    @JvmStatic external fun insert(
        label: String, code: String, isQrcode: Boolean,
        colore: String, disposable: Boolean,
    ): Int

    @JvmStatic external fun update(
        id: Int, label: String, code: String, isQrcode: Boolean,
        colore: String, disposable: Boolean,
    )

    @JvmStatic external fun delete(id: Int)
    @JvmStatic external fun reorder(disposable: Boolean, ids: IntArray)

    @JvmStatic external fun colorForId(id: Int): String

    /** Il codice spezzato in blocchi di tre, per leggerlo e confrontarlo. */
    @JvmStatic external fun groupedCode(code: String): String

    @JvmStatic external fun renderCode(code: String, isQrcode: Boolean): ImmagineCodice

    @JvmStatic external fun backupNome(oggi: String): String
    @JvmStatic external fun backupEsporta(quando: String): String

    /** Legge un backup e lo applica. Restituisce quante carte sono entrate. */
    @JvmStatic external fun backupRipristina(dati: ByteArray): Int

    /* Passaggio delle carte fra due telefoni con i QR. Il formato e il perché
     * delle scelte stanno in src/transfer.h. */

    /** I testi dei QR da mostrare, in ordine, con dentro tutte le carte. */
    @JvmStatic external fun trasfPrepara(): Array<String>

    /** Quanti pezzi sono arrivati e quanti ne servono: `[ricevuti, totale]`.
     *  Totale a 0 vuol dire che fra i codici letti non ce n'è ancora uno di
     *  OpenCard, che non è un errore: la fotocamera inquadra di tutto. */
    @JvmStatic external fun trasfStato(letti: Array<String>): IntArray

    /** Le carte contenute nei QR letti, senza scrivere niente. */
    @JvmStatic external fun trasfLeggi(letti: Array<String>): Array<Carta>

    /** Scrive le carte ricevute e dice quante ne ha scritte.
     *  `azzera` acceso butta via quelle che c'erano. */
    @JvmStatic external fun trasfApplica(letti: Array<String>, azzera: Boolean): Int

    /** Data di oggi come la vuole il nome del file di backup. */
    fun oggi(): String = SimpleDateFormat("yyyyMMdd", Locale.ITALY).format(Date())

    /** Istante attuale in ISO 8601, per l'intestazione del backup. */
    fun adesso(): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.ITALY).format(Date())
}
