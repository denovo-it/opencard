// generato da src/lingue/genera.py: non modificarlo a mano

package srl.denovo.opencard

/** L'id del testo di un errore del core, dalla chiave di opencard_errore_scomponi(). */
internal fun testoCore(chiave: String): Int = when (chiave) {
    "core_io" -> R.string.core_io
    "core_json" -> R.string.core_json
    "core_formato" -> R.string.core_formato
    "core_schema" -> R.string.core_schema
    "core_carta" -> R.string.core_carta
    "core_carta_senza_dettaglio" -> R.string.core_carta_senza_dettaglio
    "core_memoria" -> R.string.core_memoria
    "core_non_trovata" -> R.string.core_non_trovata
    "core_altro_trasferimento" -> R.string.core_altro_trasferimento
    "core_trasferimento_incompleto" -> R.string.core_trasferimento_incompleto
    "core_trasferimento_rotto" -> R.string.core_trasferimento_rotto
    "core_trasferimento_versione" -> R.string.core_trasferimento_versione
    "core_trasferimento_troppe" -> R.string.core_trasferimento_troppe
    "core_password" -> R.string.core_password
    "core_troppo_grande" -> R.string.core_troppo_grande
    else -> R.string.errore_imprevisto
}
