/*
 * SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

package srl.denovo.opencard

import android.content.Context

/**
 * Le poche cose che si scelgono e restano scelte.
 *
 * Un file di preferenze e basta: è un valore solo, e una libreria per tenerne
 * uno sarebbe più codice da aggiornare che codice da scrivere.
 */
object Impostazioni {

    const val FILE = "impostazioni"
    private const val BACKUP_CLOUD = "backup_cloud"

    private fun dove(contesto: Context) =
        contesto.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /**
     * Se le carte entrano nel backup del telefono verso il cloud di Google.
     *
     * Di serie è spento, che è come si è comportata l'app fino alla 1.0.2:
     * acceso vuol dire mandare i numeri delle tessere su un server, e quella è
     * una decisione di chi le possiede, non di un aggiornamento.
     */
    fun backupNelCloud(contesto: Context): Boolean =
        dove(contesto).getBoolean(BACKUP_CLOUD, false)

    fun cambiaBackupNelCloud(contesto: Context, acceso: Boolean) {
        dove(contesto).edit().putBoolean(BACKUP_CLOUD, acceso).apply()
    }
}
