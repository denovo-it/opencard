// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

package srl.denovo.opencard

import android.content.Intent
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import com.google.android.material.tabs.TabLayout
import com.google.android.material.tabs.TabLayoutMediator

/**
 * Logo, sito e versione fissi in testa, poi due schede.
 *
 * "Informazioni": perché l'app esiste, lo storico delle revisioni e il software
 * open source che contiene. "Legale": licenza d'uso, marchi e testo integrale
 * della AGPL v3.
 */
class InfoActivity : AppCompatActivity() {


    override fun onCreate(statoSalvato: Bundle?) {
        super.onCreate(statoSalvato)
        setContentView(R.layout.activity_info)
        setSupportActionBar(findViewById(R.id.barra))
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        // Qui la sigla del canale non si scrive: la dicono la schermata di
        // avvio e le note di rilascio, e in tre posti diversi diventa rumore.
        findViewById<TextView>(R.id.versione).text = getString(
            R.string.versione_e_build,
            BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE,
        )

        findViewById<Button>(R.id.sito).setOnClickListener { apri("https://denovo.srl") }

        // Toccando il logo si rivede la schermata di benvenuto.
        findViewById<ImageView>(R.id.logo).setOnClickListener {
            startActivity(SplashActivity.intentRivedi(this))
        }

        val pagine = findViewById<ViewPager2>(R.id.pagine)
        pagine.adapter = Pagine()

        TabLayoutMediator(findViewById<TabLayout>(R.id.schede), pagine) { scheda, posizione ->
            scheda.setText(if (posizione == 1) R.string.legale else R.string.informazioni)
        }.attach()
    }

    /** Le due schede come pagine affiancate, scorrevoli con il dito. */
    private inner class Pagine : RecyclerView.Adapter<Pagina>() {
        override fun getItemCount() = 2

        override fun onCreateViewHolder(genitore: ViewGroup, tipo: Int): Pagina {
            val vista = layoutInflater.inflate(R.layout.pagina_info, genitore, false)
            return Pagina(vista)
        }

        override fun onBindViewHolder(pagina: Pagina, posizione: Int) {
            pagina.contenuto.removeAllViews()
            if (posizione == 0) riempiInformazioni(pagina.contenuto) else riempiLegale(pagina.contenuto)
        }
    }

    private inner class Pagina(vista: android.view.View) : RecyclerView.ViewHolder(vista) {
        val contenuto: LinearLayout = vista.findViewById(R.id.contenuto)
    }

    private fun riempiInformazioni(contenuto: LinearLayout) {
        contenuto.addView(paragrafo(getString(R.string.perche_esiste), 15f))
        contenuto.addView(riga())

        contenuto.addView(titolo(getString(R.string.pagina_titolo)))
        contenuto.addView(paragrafo(getString(R.string.pagina_intro), 13f, colore = R.color.muted))
        contenuto.addView(
            voceCollegamento(
                getString(R.string.pagina_riga), getString(R.string.pagina_apri), PAGINA
            )
        )
        contenuto.addView(riga())

        contenuto.addView(titolo(getString(R.string.sorgente_titolo)))
        contenuto.addView(paragrafo(getString(R.string.sorgente_intro), 13f, colore = R.color.muted))
        contenuto.addView(
            voceCollegamento(
                getString(R.string.sorgente_riga), getString(R.string.sorgente_licenza), SORGENTE
            )
        )
        contenuto.addView(riga())

        contenuto.addView(titolo(getString(R.string.revisioni)))
        mostraChangelog(contenuto)
        contenuto.addView(riga())

        contenuto.addView(titolo(getString(R.string.software_open_source)))
        contenuto.addView(paragrafo(getString(R.string.oss_intro), 13f, colore = R.color.muted))

        contenuto.addView(sottotitolo(getString(R.string.componenti_native)))
        Librerie.NATIVE.forEach { contenuto.addView(voceCollegamento(it.first, it.second, it.third)) }

        contenuto.addView(sottotitolo(getString(R.string.librerie_android)))
        Librerie.ANDROID.forEach { contenuto.addView(voceCollegamento(it.first, it.second, it.third)) }
    }

    private fun riempiLegale(contenuto: LinearLayout) {
        contenuto.addView(titolo(getString(R.string.privacy_titolo)))
        contenuto.addView(paragrafo(getString(R.string.privacy_intro), 14f))
        contenuto.addView(
            voceCollegamento(
                getString(R.string.privacy_riga), getString(R.string.privacy_apri), PRIVACY
            )
        )
        contenuto.addView(sottotitolo(getString(R.string.backup_sottotitolo)))
        contenuto.addView(paragrafo(getString(R.string.backup_privacy), 13f, colore = R.color.muted))
        contenuto.addView(riga())

        contenuto.addView(titolo(getString(R.string.licenza_uso_titolo)))
        contenuto.addView(paragrafo(getString(R.string.licenza_uso), 15f))
        contenuto.addView(riga())

        contenuto.addView(titolo(getString(R.string.marchi_titolo)))
        contenuto.addView(paragrafo(getString(R.string.marchi), 14f))
        contenuto.addView(riga())

        contenuto.addView(titolo(getString(R.string.licenza_completa_titolo)))
        contenuto.addView(
            paragrafo(leggiAsset("LICENSE.txt"), 11f, colore = R.color.muted, monospazio = true)
        )
    }

    /**
     * Lo storico, con titoli e punti elenco al posto delle marcature.
     *
     * Ogni voce diventa una riga con il pallino a sinistra e il testo rientrato:
     * su più righe il testo resta allineato sotto se stesso, non sotto il
     * pallino.
     */
    private fun mostraChangelog(contenuto: LinearLayout) {
        Markdown.analizza(leggiAsset("CHANGELOG.md")).forEach { blocco ->
            when (blocco) {
                is Markdown.Blocco.Titolo -> contenuto.addView(
                    TextView(this).apply {
                        text = blocco.testo
                        textSize = 15f
                        setTypeface(typeface, Typeface.BOLD)
                        setTextColor(ContextCompat.getColor(this@InfoActivity, R.color.brand))
                        setPadding(0, dp(16), 0, dp(4))
                        layoutParams = larghezzaPiena()
                    }
                )
                is Markdown.Blocco.Punto -> contenuto.addView(puntoElenco(blocco.testo))
                is Markdown.Blocco.Nota -> contenuto.addView(
                    TextView(this).apply {
                        text = blocco.testo
                        textSize = 13f
                        setTypeface(typeface, Typeface.ITALIC)
                        setTextColor(ContextCompat.getColor(this@InfoActivity, R.color.muted))
                        setPadding(dp(12), dp(6), 0, dp(6))
                        layoutParams = larghezzaPiena()
                    }
                )
                is Markdown.Blocco.Paragrafo -> contenuto.addView(
                    paragrafo(blocco.testo.toString(), 14f)
                )
            }
        }
    }

    private fun puntoElenco(testo: CharSequence) = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        setPadding(0, dp(3), 0, dp(3))
        // Larghezza piena: aggiunta senza parametri la riga nascerebbe
        // WRAP_CONTENT, e lì dentro il peso del testo non si comporta come
        // deve, sfondando il margine della colonna.
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        )

        addView(TextView(this@InfoActivity).apply {
            text = "\u2022"
            textSize = 14f
            setPadding(0, 0, dp(8), 0)
        })
        addView(TextView(this@InfoActivity).apply {
            text = testo
            textSize = 14f
            setTextIsSelectable(true)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        })
    }

    /** Il testo integrale della licenza e lo storico stanno negli asset. */
    private fun leggiAsset(nome: String): String = try {
        assets.open(nome).bufferedReader().use { it.readText() }
    } catch (e: Exception) {
        "Contenuto non disponibile."
    }

    private fun titolo(testo: String) = TextView(this).apply {
        text = testo
        textSize = 16f
        setTypeface(typeface, Typeface.BOLD)
        setPadding(0, dp(8), 0, dp(4))
        layoutParams = larghezzaPiena()
    }

    /// Tutti i blocchi occupano la colonna intera, così vanno a capo allo
    /// stesso punto e il margine resta uno solo.
    private fun larghezzaPiena() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
    )

    private fun sottotitolo(testo: String) = TextView(this).apply {
        text = testo
        textSize = 13f
        setTypeface(typeface, Typeface.BOLD)
        setTextColor(ContextCompat.getColor(this@InfoActivity, R.color.muted))
        setPadding(0, dp(12), 0, dp(4))
        layoutParams = larghezzaPiena()
    }

    private fun paragrafo(
        testo: String,
        dimensione: Float,
        colore: Int? = null,
        monospazio: Boolean = false,
    ) = TextView(this).apply {
        text = testo
        textSize = dimensione
        setTextIsSelectable(true)
        setPadding(0, dp(4), 0, dp(4))
        layoutParams = larghezzaPiena()
        colore?.let { setTextColor(ContextCompat.getColor(this@InfoActivity, it)) }
        if (monospazio) typeface = Typeface.MONOSPACE
    }

    private fun riga() = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(1))
            .also { it.topMargin = dp(12); it.bottomMargin = dp(4) }
        setBackgroundColor(ContextCompat.getColor(this@InfoActivity, R.color.faint))
        alpha = 0.4f
    }

    /** Riga toccabile: nome a sinistra, etichetta a destra, tocco per aprire la pagina. */
    private fun voceCollegamento(nome: String, etichetta: String, url: String) = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(0, dp(8), 0, dp(8))
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        )
        isClickable = true
        setOnClickListener { apri(url) }

        addView(TextView(this@InfoActivity).apply {
            text = nome
            textSize = 14f
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        })
        addView(TextView(this@InfoActivity).apply {
            text = etichetta
            textSize = 12f
            setTextColor(ContextCompat.getColor(this@InfoActivity, R.color.muted))
        })
    }

    private fun apri(url: String) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (e: Exception) {
            // Nessun browser installato: non c'è niente di utile da dire.
        }
    }

    private fun dp(valore: Int): Int = (valore * resources.displayMetrics.density).toInt()

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }
}
