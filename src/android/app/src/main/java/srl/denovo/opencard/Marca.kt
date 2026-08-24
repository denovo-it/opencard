// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

/**
 * Canale di rilascio.
 *
 * Finche' è valorizzato, l'app lo dichiara nella barra e nella schermata
 * informativa: chi prova una versione deve sapere che la sta provando.
 * Alla prima versione di produzione si mette a null e la pastiglia sparisce
 * da sola.
 */
val CANALE: String? = null

/** Dove sta il codice, pubblico dal 17 agosto 2026. Lo mostra la schermata informativa. */
const val SORGENTE = "https://github.com/denovo-it/opencard"

/** La privacy policy dell'app, la stessa dichiarata nelle schede dei due store. */
const val PRIVACY = "https://denovo.srl/opencard-privacy/"

/** Software di altri incluso nell'app, con la licenza di ciascuno. */
object Librerie {

    /** (nome, licenza, indirizzo) */
    val NATIVE = listOf(
        Triple("zint", "BSD 3-Clause", "https://www.zint.org.uk"),
        Triple("cJSON", "MIT", "https://github.com/DaveGamble/cJSON"),
    )

    val ANDROID = listOf(
        Triple("Kotlin", "Apache 2.0", "https://kotlinlang.org"),
        Triple("AndroidX AppCompat", "Apache 2.0", "https://developer.android.com/jetpack/androidx"),
        Triple("AndroidX RecyclerView", "Apache 2.0", "https://developer.android.com/jetpack/androidx"),
        Triple("Material Components", "Apache 2.0", "https://m3.material.io"),
        Triple("CameraX", "Apache 2.0", "https://developer.android.com/training/camerax"),
        Triple("ML Kit Barcode Scanning", "Apache 2.0", "https://developers.google.com/ml-kit"),
    )
}
