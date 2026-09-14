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
    /** Quale codice è: l'indice vale quanto l'enum del core, vedi [Simbologie]. */
    val simbologia: Int,
    val note: String,
    /** "AAAA-MM-GG", oppure vuota. */
    val scadenza: String,
    val saldo: String,
    /** Nome del file, non il percorso: le foto stanno in una cartella a parte. */
    val fotoFronte: String,
    val fotoRetro: String,
)

/**
 * I nomi delle simbologie come si scrivono in elenco. L'ordine è quello
 * dell'enum del core: la posizione è il valore, quindi non si riordina.
 */
object Simbologie {
    val nomi = listOf(
        "Code 128", "QR code", "Aztec", "Codabar", "Code 39", "Code 93",
        "Data Matrix", "EAN-8", "EAN-13", "ITF", "PDF417", "UPC-A", "UPC-E",
        "Micro QR", "GS1-128", "GS1 DataBar", "DataBar Expanded", "MSI Plessey",
    )

    /** I due numeri del core che servono per nome anche qui fuori. */
    const val QR = 1
    const val MICROQR = 13

    /** Vero per le due che si disegnano come quadrato e non come barre. */
    fun eQuadrato(simbologia: Int) = simbologia == QR || simbologia == MICROQR

    /**
     * Nessuna scelta dell'utente: la simbologia la decide l'app.
     *
     * Non è un valore che il core conosce e non finisce mai nel file: al
     * salvataggio diventa la simbologia letta dal lettore, o quella che si
     * ricava dal codice. Nel file una carta ha sempre scritto come si disegna.
     */
    const val AUTO = -1

    /**
     * L'elenco che si vede ha Automatico in cima, quindi le posizioni sono
     * spostate di uno rispetto ai numeri del core. Le due conversioni stanno
     * qui e non sparse per le schermate.
     */
    fun voce(simbologia: Int) = simbologia + 1

    fun simbologiaDellaVoce(voce: Int) = voce - 1
}

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

/**
 * Errore del core.
 *
 * Porta il codice e i pezzi che servono a scrivere la frase, non la frase: il
 * core non sa in che lingua sta parlando l'app, e finché il messaggio lo
 * scriveva lui, su un telefono inglese l'app rispondeva in italiano appena
 * qualcosa andava storto. Le frasi stanno in [Errori], cioè nei file di lingua
 * insieme a tutte le altre.
 */
class OpenCardException(
    val codice: Int,
    val posizione: Int,
    val dettaglio: String,
    val schemaTrovato: Int,
) : Exception() {

    private var messaggioProprio: String? = null

    /**
     * Un errore che nasce nell'app e non nel core: la frase ce l'ha già, e non
     * c'è nessun codice da tradurre. Il file troppo grande scelto per errore,
     * per esempio.
     */
    constructor(messaggio: String) : this(0, 0, "", 0) {
        messaggioProprio = messaggio
    }

    override val message: String
        get() = messaggioProprio ?: Errori.testo(codice, posizione, dettaglio, schemaTrovato)
}

/**
 * I messaggi degli errori del core, nella lingua dell'app.
 *
 * I numeri sono quelli di `opencard_esito` in `store.h`: chi ne aggiunge uno
 * aggiunge una riga qui, una in `OCCore.m` e una nei due file di lingua.
 */
object Errori {
    private const val IO = -1
    private const val JSON = -2
    private const val FORMATO = -3
    private const val SCHEMA = -4
    private const val CARTA = -5
    private const val MEMORIA = -6
    private const val NON_TROVATA = -8
    private const val ALTRO_TRASF = -9
    private const val TRASF_INCOMPLETO = -10
    private const val TRASF_ROTTO = -11
    private const val TRASF_VERSIONE = -12
    private const val TRASF_TROPPE = -13
    private const val PASSWORD = -14

    /** Lo stesso numero di `OPENCARD_SCHEMA_VERSION` in `store.h`. */
    private const val SCHEMA_NOSTRO = 3

    fun testo(codice: Int, posizione: Int, dettaglio: String, schemaTrovato: Int): String {
        val dove = Applicazione.contesto ?: return "Errore $codice."
        return when (codice) {
            IO -> dove.getString(R.string.core_io)
            JSON -> dove.getString(R.string.core_json)
            FORMATO -> dove.getString(R.string.core_formato)
            SCHEMA -> dove.getString(R.string.core_schema, schemaTrovato, SCHEMA_NOSTRO)
            CARTA -> if (dettaglio.isEmpty()) {
                dove.getString(R.string.core_carta_senza_dettaglio, posizione)
            } else {
                dove.getString(R.string.core_carta, posizione, dettaglio)
            }
            MEMORIA -> dove.getString(R.string.core_memoria)
            NON_TROVATA -> dove.getString(R.string.core_non_trovata)
            ALTRO_TRASF -> dove.getString(R.string.core_altro_trasferimento)
            TRASF_INCOMPLETO -> dove.getString(R.string.core_trasferimento_incompleto)
            TRASF_ROTTO -> dove.getString(R.string.core_trasferimento_rotto)
            TRASF_VERSIONE -> dove.getString(R.string.core_trasferimento_versione, schemaTrovato)
            TRASF_TROPPE -> dove.getString(R.string.core_trasferimento_troppe)
            PASSWORD -> dove.getString(R.string.core_password)
            else -> dove.getString(R.string.errore_imprevisto)
        }
    }
}

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

    /**
     * La chiave con cui il file delle carte sta cifrato sul telefono, 32 byte.
     * Va data subito dopo [storeInit] e prima di leggere qualsiasi cosa.
     * Null la toglie, e il file torna a scriversi in chiaro.
     */
    @JvmStatic external fun storeChiave(chiave: ByteArray?)
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

    /** Cambia la simbologia e basta: la carta resta com'è. */
    @JvmStatic external fun setSimbologia(id: Int, simbologia: Int)

    /**
     * Note, scadenza e saldo. Stringa vuota svuota il campo; la scadenza vuole
     * "AAAA-MM-GG" e qualsiasi altra cosa fa fallire la chiamata senza
     * scrivere niente.
     */
    @JvmStatic external fun setDettagli(id: Int, note: String, scadenza: String, saldo: String)

    /** I nomi dei file delle due foto. I file li scrive e li cancella la UI. */
    @JvmStatic external fun setFoto(id: Int, fronte: String, retro: String)

    /** Il codice disegnato con la simbologia scelta, non con quella indovinata. */
    @JvmStatic external fun renderCodeSimbologia(code: String, simbologia: Int): ImmagineCodice

    /** Quale simbologia proporre per un codice appena letto o scritto. */
    @JvmStatic external fun simbologiaIndovinata(code: String, isQrcode: Boolean): Int

    /**
     * Se un codice si può disegnare in una simbologia, senza disegnarlo.
     *
     * Il modulo lo chiede prima di salvare: una scelta che non porta da nessuna
     * parte va detta subito, non scoperta più tardi aprendo la carta e trovando
     * il posto del codice vuoto.
     */
    @JvmStatic external fun codiceSta(code: String, simbologia: Int): Boolean

    @JvmStatic external fun delete(id: Int)

    /** Cancella tutte le carte in una scrittura sola. Le foto le toglie la UI. */
    @JvmStatic external fun azzeraTutto()
    @JvmStatic external fun reorder(disposable: Boolean, ids: IntArray)

    @JvmStatic external fun colorForId(id: Int): String

    /** Il codice spezzato in blocchi di tre, per leggerlo e confrontarlo. */
    @JvmStatic external fun groupedCode(code: String): String

    @JvmStatic external fun renderCode(code: String, isQrcode: Boolean): ImmagineCodice

    @JvmStatic external fun backupNome(oggi: String): String
    @JvmStatic external fun backupEsporta(quando: String): String

    /** Legge un backup e lo applica. Restituisce quante carte sono entrate. */
    @JvmStatic external fun backupRipristina(dati: ByteArray): Int

    /**
     * Il backup chiuso con una password. Password vuota non si accetta: la
     * scelta di cifrare o no la fa l'interfaccia, non il core.
     */
    @JvmStatic external fun backupEsportaCifrato(quando: String, password: String): ByteArray

    /** Vero se il file letto è un backup cifrato: serve per sapere se chiedere la password. */
    @JvmStatic external fun backupCifrato(dati: ByteArray): Boolean

    /**
     * Ripristina da un file che può essere in chiaro o cifrato. Password vuota
     * per i file in chiaro. Torna quante carte sono entrate.
     */
    @JvmStatic external fun backupRipristinaFile(dati: ByteArray, password: String): Int

    /**
     * Cifra e decifra un pacchetto qualsiasi con la stessa cassaforte del
     * backup. Servono allo ZIP: dentro ci sono le foto, quindi si chiude tutto
     * l'archivio invece del solo elenco delle carte.
     */
    @JvmStatic external fun backupCifra(dati: ByteArray, password: String): ByteArray

    @JvmStatic external fun backupDecifra(dati: ByteArray, password: String): ByteArray

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

    /** Istante attuale in ISO 8601, per l'intestazione del backup. In UTC con
     *  la Z scritta, come `BackupNelCloud.quandoIso()`: il fuso con `XXX`
     *  Android lo conosce solo dall'API 24, e su Android 6 l'esportazione
     *  chiudeva l'app. Il campo, `exported_at`, non lo rilegge nessuno. */
    fun adesso(): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.ITALY)
            .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
            .format(Date())
}
