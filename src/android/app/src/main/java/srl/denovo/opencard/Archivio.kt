/*
 * SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

package srl.denovo.opencard

import android.content.Context
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/**
 * Il backup in archivio: l'elenco delle carte e le foto in un file solo.
 *
 * Il JSON da solo non basta più da quando le carte hanno le foto: dentro ci
 * finiscono i nomi dei file, non i byte, e un backup ripristinato su un altro
 * telefono tornerebbe senza immagini.
 *
 * Dentro l'archivio ci sono `opencard.json` e le foto con il nome che hanno
 * nella carta, `card_<id>_front.jpg` e `card_<id>_back.jpg`. È lo stesso
 * schema di Catima, che nel suo ZIP mette un CSV e le immagini con quei nomi:
 * il giorno che si legge il loro archivio, il codice che cerca le foto è
 * questo.
 *
 * La password non la mette lo ZIP, che sa cifrare male: si chiude tutto
 * l'archivio con la cassaforte del core, la stessa del backup semplice. Così
 * anche le foto stanno al riparo, e chi apre il file trova la stessa magia di
 * sempre.
 */
object Archivio {

    const val NOME_ELENCO = "opencard.json"

    /** I primi due byte di uno zip: "PK". */
    private val MAGIA_ZIP = byteArrayOf(0x50, 0x4B)

    fun eArchivio(dati: ByteArray): Boolean =
        dati.size > 4 && dati[0] == MAGIA_ZIP[0] && dati[1] == MAGIA_ZIP[1]

    /**
     * L'archivio con dentro l'elenco e le foto che esistono davvero.
     *
     * Le foto nominate da una carta ma sparite dal disco si saltano: meglio un
     * archivio con una foto in meno che nessun archivio.
     */
    fun scrivi(contesto: Context, elenco: ByteArray, carte: Array<Carta>): ByteArray {
        val fuori = ByteArrayOutputStream()
        ZipOutputStream(fuori).use { zip ->
            zip.putNextEntry(ZipEntry(NOME_ELENCO))
            zip.write(elenco)
            zip.closeEntry()

            for (carta in carte) {
                for (nome in listOf(carta.fotoFronte, carta.fotoRetro)) {
                    if (nome.isEmpty()) {
                        continue
                    }
                    val file = Foto.file(contesto, nome)
                    if (!file.exists()) {
                        continue
                    }
                    zip.putNextEntry(ZipEntry(nome))
                    file.inputStream().use { it.copyTo(zip) }
                    zip.closeEntry()
                }
            }
        }
        return fuori.toByteArray()
    }

    /**
     * Tira fuori l'elenco e rimette le foto al loro posto.
     *
     * Torna i byte dell'elenco, che poi vanno al core. Le foto si scrivono
     * subito: se il ripristino delle carte fallisce restano lì, ma sono file
     * che nessuna carta nomina e alla prossima esportazione non escono.
     *
     * I nomi dentro l'archivio si prendono senza cartelle: un archivio
     * costruito male potrebbe portare percorsi tipo `../../altro`, e un file
     * scritto fuori dalla cartella delle foto sarebbe un guaio.
     */
    fun leggi(contesto: Context, archivio: ByteArray): ByteArray? {
        var elenco: ByteArray? = null
        ZipInputStream(archivio.inputStream()).use { zip ->
            while (true) {
                val voce = zip.nextEntry ?: break
                val nome = voce.name.substringAfterLast('/')
                when {
                    voce.isDirectory || nome.isEmpty() -> Unit
                    nome == NOME_ELENCO -> elenco = zip.readBytes()
                    nome.startsWith("card_") -> {
                        Foto.file(contesto, nome).outputStream().use { zip.copyTo(it) }
                    }
                }
                zip.closeEntry()
            }
        }
        return elenco
    }
}
