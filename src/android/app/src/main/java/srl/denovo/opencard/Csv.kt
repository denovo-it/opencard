/*
 * SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

package srl.denovo.opencard

/**
 * Il CSV, nel formato di Catima.
 *
 * Serve per uscire e per entrare: chi lascia OpenCard deve potersi portare via
 * le carte in un formato che un'altra app legge, e chi arriva da Catima deve
 * poter entrare senza ribattere venti tessere a mano. Il formato è documentato
 * in `docs/EXPORT_FORMAT.md` del loro repository, e la scelta di adottarlo
 * invece di inventarne uno nostro è quella che rende il file utile a qualcuno.
 *
 * Il file ha tre tabelle separate da righe vuote: i gruppi, le carte, e i
 * collegamenti fra le due. I gruppi non li abbiamo, quindi in uscita quella
 * tabella è vuota e in entrata si salta.
 *
 * Quello che si perde passando di qui, ed è il motivo per cui l'archivio resta
 * il modo consigliato: le foto, che nel CSV non ci stanno, e la distinzione fra
 * carta normale e usa e getta, che nel loro formato non esiste.
 */
object Csv {

    private const val VERSIONE = "2"

    private val COLONNE = listOf(
        "_id", "store", "note", "validfrom", "expiry", "balance", "balancetype",
        "cardid", "barcodeid", "barcodetype", "barcodeencoding", "headercolor",
        "starstatus", "lastused", "archive",
    )

    /** I nomi delle simbologie come li scrive Catima, per le nostre diciotto. */
    private val NOMI_CATIMA = mapOf(
        0 to "CODE_128", 1 to "QR_CODE", 2 to "AZTEC", 3 to "CODABAR",
        4 to "CODE_39", 5 to "CODE_93", 6 to "DATA_MATRIX", 7 to "EAN_8",
        8 to "EAN_13", 9 to "ITF", 10 to "PDF_417", 11 to "UPC_A", 12 to "UPC_E",
        13 to "QR_CODE", 14 to "CODE_128", 15 to "RSS_14", 16 to "RSS_EXPANDED",
        17 to "CODE_128",
    )

    fun eCsv(dati: ByteArray): Boolean {
        val testa = String(dati.take(200).toByteArray(), Charsets.UTF_8)
        return testa.trimStart().startsWith(VERSIONE) && testa.contains("_id")
    }

    // ------------------------------------------------------------- in uscita

    private fun campo(testo: String): String =
        if (testo.any { it == ',' || it == '"' || it == '\n' || it == '\r' }) {
            "\"" + testo.replace("\"", "\"\"") + "\""
        } else {
            testo
        }

    fun scrivi(carte: Array<Carta>): ByteArray {
        val righe = StringBuilder()
        righe.append(VERSIONE).append("\n\n")
        righe.append("_id\n\n")                       // nessun gruppo
        righe.append(COLONNE.joinToString(",")).append("\n")

        for (carta in carte) {
            val valori = listOf(
                carta.id.toString(),
                carta.label,
                carta.note,
                "",                                   // validfrom, non ce l'abbiamo
                millisDaData(carta.scadenza),
                carta.saldo,
                "",                                   // balancetype
                carta.code,
                "",                                   // barcodeid
                NOMI_CATIMA[carta.simbologia] ?: "CODE_128",
                "UTF-8",
                coloreIntero(carta.colore),
                if (carta.preferita) "1" else "0",
                "",                                   // lastused
                "0",                                  // archive
            )
            righe.append(valori.joinToString(",") { campo(it) }).append("\n")
        }
        righe.append("\ncardId,groupId\n")
        return righe.toString().toByteArray(Charsets.UTF_8)
    }

    /** "AAAA-MM-GG" nei millisecondi che vuole Catima, o vuoto. */
    private fun millisDaData(data: String): String {
        if (data.length != 10) {
            return ""
        }
        return try {
            val formato = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).apply {
                timeZone = java.util.TimeZone.getTimeZone("UTC")
            }
            formato.parse(data)?.time?.toString() ?: ""
        } catch (guasto: Exception) {
            ""
        }
    }

    private fun coloreIntero(colore: String): String = try {
        android.graphics.Color.parseColor(colore).toString()
    } catch (guasto: Exception) {
        ""
    }

    // ------------------------------------------------------------- in entrata

    /**
     * Le righe di un CSV, tenendo conto delle virgolette.
     *
     * Una nota può contenere virgole e andare a capo: spezzare per righe e per
     * virgole senza guardare le virgolette spaccherebbe proprio le carte con
     * una nota lunga, che sono quelle a cui chi le ha scritte tiene di più.
     */
    private fun spezza(testo: String): List<List<String>> {
        val righe = mutableListOf<List<String>>()
        var riga = mutableListOf<String>()
        val campo = StringBuilder()
        var fraVirgolette = false
        var i = 0

        while (i < testo.length) {
            val c = testo[i]
            when {
                fraVirgolette && c == '"' && i + 1 < testo.length && testo[i + 1] == '"' -> {
                    campo.append('"')
                    i++
                }
                c == '"' -> fraVirgolette = !fraVirgolette
                !fraVirgolette && c == ',' -> {
                    riga.add(campo.toString()); campo.clear()
                }
                !fraVirgolette && (c == '\n' || c == '\r') -> {
                    if (c == '\r' && i + 1 < testo.length && testo[i + 1] == '\n') i++
                    riga.add(campo.toString()); campo.clear()
                    righe.add(riga); riga = mutableListOf()
                }
                else -> campo.append(c)
            }
            i++
        }
        riga.add(campo.toString())
        if (riga.any { it.isNotEmpty() }) righe.add(riga)
        return righe
    }

    /** Una carta letta dal CSV, con quello che ci sta dentro. */
    class Letta(
        val label: String,
        val code: String,
        val simbologia: Int,
        val colore: String,
        val preferita: Boolean,
        val note: String,
        val scadenza: String,
        val saldo: String,
    )

    fun leggi(dati: ByteArray): List<Letta> {
        val righe = spezza(String(dati, Charsets.UTF_8))
        val intestazione = righe.indexOfFirst { it.firstOrNull() == "_id" && it.size > 5 }
        if (intestazione < 0) {
            return emptyList()
        }
        val colonne = righe[intestazione]
        val carte = mutableListOf<Letta>()

        for (riga in righe.drop(intestazione + 1)) {
            // La tabella finisce dove finiscono le colonne: dopo c'e' la riga
            // vuota e poi i collegamenti ai gruppi.
            if (riga.size < colonne.size || riga.all { it.isEmpty() }) {
                break
            }
            fun valore(nome: String): String =
                colonne.indexOf(nome).let { if (it in riga.indices) riga[it] else "" }

            val nome = valore("store")
            val codice = valore("cardid")
            if (nome.isEmpty() || codice.isEmpty()) {
                continue
            }
            carte += Letta(
                label = nome,
                code = codice,
                simbologia = simbologiaDaCatima(valore("barcodetype"), codice),
                colore = coloreDaIntero(valore("headercolor")),
                preferita = valore("starstatus") == "1",
                note = valore("note"),
                scadenza = dataDaMillis(valore("expiry")),
                saldo = saldoLeggibile(valore("balance"), valore("balancetype")),
            )
        }
        return carte
    }

    private fun simbologiaDaCatima(nome: String, codice: String): Int {
        val dritto = NOMI_CATIMA.entries.firstOrNull { it.value == nome.uppercase() }?.key
        // Un tipo che non conosciamo, o assente, si indovina dal codice come
        // fa il core: meglio un EAN riconosciuto che un Code 128 a caso.
        return dritto ?: Core.simbologiaIndovinata(codice, false)
    }

    private fun coloreDaIntero(testo: String): String = try {
        if (testo.isEmpty()) "" else String.format("#%06X", testo.toInt() and 0xFFFFFF)
    } catch (guasto: Exception) {
        ""
    }

    private fun dataDaMillis(testo: String): String = try {
        if (testo.isEmpty() || testo == "0") {
            ""
        } else {
            java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).apply {
                timeZone = java.util.TimeZone.getTimeZone("UTC")
            }.format(java.util.Date(testo.toLong()))
        }
    } catch (guasto: Exception) {
        ""
    }

    /**
     * Il saldo di Catima è un numero con accanto il tipo, il nostro è testo
     * libero: si uniscono. Zero senza tipo vuol dire "non compilato", ed è il
     * valore che mettono a tutte le carte che non hanno un saldo.
     */
    private fun saldoLeggibile(quanto: String, tipo: String): String {
        val numero = quanto.trim().trimEnd('0').trimEnd('.', ',')
        if (quanto.isEmpty() || numero.isEmpty() || numero == "0") {
            return ""
        }
        return if (tipo.isEmpty()) quanto.trim() else "${quanto.trim()} ${tipo.trim()}"
    }
}
