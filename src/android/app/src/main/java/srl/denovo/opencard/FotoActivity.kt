/*
 * SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

package srl.denovo.opencard

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

/**
 * La foto di una carta a schermo pieno.
 *
 * Serve per leggere quello che sulla tessera è scritto piccolo: la scadenza
 * stampata, il numero del socio, le condizioni sul retro. Si apre toccando la
 * foto nella schermata della carta e si chiude con Indietro.
 */
class FotoActivity : AppCompatActivity() {

    companion object {
        private const val EXTRA_NOME = "nome"
        private const val EXTRA_LATO = "lato"

        fun apri(contesto: Context, nome: String, lato: Int) {
            contesto.startActivity(
                Intent(contesto, FotoActivity::class.java)
                    .putExtra(EXTRA_NOME, nome)
                    .putExtra(EXTRA_LATO, lato)
            )
        }
    }

    override fun onCreate(statoPrecedente: Bundle?) {
        super.onCreate(statoPrecedente)
        setContentView(R.layout.activity_foto)

        val nome = intent.getStringExtra(EXTRA_NOME).orEmpty()
        val lato = intent.getIntExtra(EXTRA_LATO, R.string.foto_fronte)
        val vista = findViewById<VistaZoom>(R.id.foto_grande)
        vista.contentDescription = getString(lato)

        // Qui si legge a piena risoluzione, entro il tetto del lato lungo con
        // cui e' stata salvata: e' l'unico posto dove i pixel servono davvero.
        val immagine = Foto.leggi(this, nome, latoMassimo = 2000)
        if (immagine == null) {
            finish()
            return
        }
        vista.setImageBitmap(immagine)
    }
}
