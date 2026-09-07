/*
 * SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

package srl.denovo.opencard

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * La chiave con cui il file delle carte sta cifrato sul telefono.
 *
 * Due chiavi, non una. Quella che cifra il file è trentadue byte a caso, e sta
 * in un file accanto ai dati; quella che protegge lei vive nel **Keystore di
 * Android**, da dove non esce mai, perché una chiave hardware non si può
 * leggere: si può solo chiedere al sistema di cifrare e decifrare con essa.
 *
 * Questo giro doppio serve perché il core cifra il file da sé, con lo stesso
 * codice su Android e su iPhone, e per farlo ha bisogno dei byte veri. Il
 * Keystore glieli consegna al momento dell'apertura e nessuno li scrive mai
 * sul disco in chiaro.
 *
 * La chiave non chiede l'impronta né il codice di sblocco: chiederli
 * significherebbe non poter aprire l'app senza, e OpenCard si apre alla cassa
 * con le mani occupate. Quello che protegge è il disco: chi tira fuori il file
 * da un telefono spento, o da un backup, trova byte a caso.
 */
object ChiaveDati {

    private const val PORTACHIAVI = "AndroidKeyStore"
    private const val ETICHETTA = "opencard-dati"
    private const val NOME_FILE = "chiave.bin"
    private const val NONCE_N = 12
    private const val CHIAVE_N = 32

    /**
     * I byte della chiave del file, creandola al primo avvio.
     *
     * Null se il portachiavi non risponde: in quel caso il file resta in
     * chiaro, che è come si comportava l'app fino alla 1.0.2. Meglio un file
     * leggibile che un'app che non si apre.
     */
    fun dammi(contesto: Context): ByteArray? = try {
        val dove = File(contesto.filesDir, NOME_FILE)
        if (dove.exists()) apri(dove) else crea(dove)
    } catch (guasto: Exception) {
        null
    }

    private fun protezione(): SecretKey {
        val portachiavi = KeyStore.getInstance(PORTACHIAVI).apply { load(null) }
        val esistente = portachiavi.getKey(ETICHETTA, null) as? SecretKey
        if (esistente != null) {
            return esistente
        }
        val generatore = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PORTACHIAVI)
        generatore.init(
            KeyGenParameterSpec.Builder(
                ETICHETTA,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generatore.generateKey()
    }

    private fun crea(dove: File): ByteArray {
        val chiave = ByteArray(CHIAVE_N).also { java.security.SecureRandom().nextBytes(it) }
        val cifratore = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, protezione())
        }
        val chiusa = cifratore.doFinal(chiave)
        // Il nonce davanti, poi la chiave chiusa: un file solo, senza formati.
        dove.outputStream().use {
            it.write(cifratore.iv)
            it.write(chiusa)
        }
        return chiave
    }

    private fun apri(dove: File): ByteArray? {
        val byte = dove.readBytes()
        if (byte.size <= NONCE_N) {
            return null
        }
        val cifratore = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(
                Cipher.DECRYPT_MODE,
                protezione(),
                GCMParameterSpec(128, byte, 0, NONCE_N),
            )
        }
        val chiave = cifratore.doFinal(byte, NONCE_N, byte.size - NONCE_N)
        return if (chiave.size == CHIAVE_N) chiave else null
    }
}
