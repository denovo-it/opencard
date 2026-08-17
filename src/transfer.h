/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 *
 * Passaggio delle carte da un telefono all'altro con uno o piu' QR.
 *
 * Chi cede mostra i codici, chi riceve li inquadra. Niente rete, niente file,
 * niente account. Serve dentro la famiglia, quindi il contenuto non e' cifrato:
 * chi legge lo schermo legge le tessere, ed e' una scelta presa sapendola.
 *
 * Come e' fatto un trasferimento, dall'interno verso l'esterno:
 *
 *   carte  ->  formato binario compatto  ->  deflate  ->  fette da 950 byte
 *          ->  intestazione per fetta    ->  base44    ->  testo del QR
 *
 * Le tre scelte che contano:
 *
 * - **Binario e non JSON.** Il JSON del backup costa 126 byte a carta, il
 *   binario compresso ne costa 20: e' la differenza fra due carte e quaranta
 *   dentro lo stesso QR.
 * - **base44 e non base64.** L'alfabeto di base44 sta tutto dentro la modalita'
 *   alfanumerica del QR, che impacchetta due caratteri in 11 bit: costa il 3
 *   per cento di capacita' invece del 25. Rispetto al base45 dello standard
 *   manca solo lo spazio, tolto apposta perche' il QR di OpenCard passa per
 *   funzioni che tagliano gli spazi ai due capi di una stringa.
 * - **Fette da 950 byte.** Ci entrano in un QR di versione 25, 117 moduli per
 *   lato: mezzo millimetro per modulo su uno schermo da sei pollici, che
 *   qualsiasi fotocamera prende al volo. La versione 40 porterebbe il triplo,
 *   ma a tre decimi di millimetro per modulo.
 *
 * Le fette si mostrano a rotazione e si possono leggere in qualsiasi ordine:
 * ogni QR dice quale pezzo e' e quanti sono in tutto, e porta il CRC32
 * dell'insieme, che fa anche da nome del trasferimento. Un pezzo di un altro
 * trasferimento viene riconosciuto e rifiutato invece di mescolarsi.
 */

#ifndef OPENCARD_TRANSFER_H
#define OPENCARD_TRANSFER_H

#include <stddef.h>

#include "store.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Versione del formato che viaggia nel QR. Sale solo se cambia il modo di
 * scrivere i byte: un telefono che riceve un formato piu' alto del suo si
 * ferma e dice di aggiornare, invece di leggere numeri a caso. */
#define OPENCARD_TRASF_FORMATO 1

/* Quante carte stanno in un trasferimento. Il conteggio viaggia in un byte. */
#define OPENCARD_TRASF_CARTE_MAX 255

/* Quanti QR al massimo. Con 950 byte a pezzo sono piu' di duecento carte. */
#define OPENCARD_TRASF_PEZZI_MAX 255

/* I testi dei QR da mostrare, in ordine. */
typedef struct {
    char **pezzi;   /* stringhe base44 terminate da NUL */
    size_t n;
} opencard_trasf_pezzi;

/* Prepara i QR con tutte le carte che ci sono adesso.
 * Chi chiama libera con opencard_trasf_pezzi_free(). */
opencard_esito opencard_trasf_prepara(opencard_trasf_pezzi *out,
                                      opencard_errore *errore);

/* Come sopra ma su una lista data, senza toccare il file dei dati.
 * La usa il banco di prova. */
opencard_esito opencard_trasf_prepara_lista(const opencard_lista *lista,
                                            opencard_trasf_pezzi *out,
                                            opencard_errore *errore);

void opencard_trasf_pezzi_free(opencard_trasf_pezzi *pezzi);

/* A che punto e' la raccolta, dati i QR letti finora.
 *
 * Non e' un errore passare doppioni o testi che non c'entrano niente: quelli
 * che non sono di OpenCard vengono ignorati, e *totale resta 0 finche' non
 * arriva il primo pezzo buono. Chi arriva da un altro trasferimento fa
 * tornare OPENCARD_ERR_ALTRO_TRASF: e' l'unico caso in cui la UI deve dire
 * qualcosa, perche' vuol dire che i due telefoni si sono disallineati.
 */
opencard_esito opencard_trasf_stato(const char *const *letti, size_t n,
                                    int *ricevuti, int *totale,
                                    opencard_errore *errore);

/* Le carte contenute nei QR letti. Non tocca il file dei dati: sta a chi
 * chiama decidere cosa farne, come per il ripristino di un backup. */
opencard_esito opencard_trasf_leggi(const char *const *letti, size_t n,
                                    opencard_lista *out, opencard_errore *errore);

/* Scrive le carte ricevute.
 *
 * `azzera` acceso butta via le carte che ci sono e lascia solo quelle
 * arrivate; spento le mette in fondo alle proprie, senza guardare i doppioni:
 * se una tessera c'e' gia' ci finisce due volte, e a toglierla e' l'utente.
 * E' la scelta fatta il 2026-08-11: confrontare le carte per unirle da sole
 * indovina, e indovinando si perdono le tessere.
 *
 * In *quante, se non NULL, il numero di carte scritte.
 */
opencard_esito opencard_trasf_applica(const char *const *letti, size_t n,
                                      int azzera, int *quante,
                                      opencard_errore *errore);

/* base44, esposte per il banco di prova.
 *
 * codifica: servono (byte + 1) / 2 * 3 + 1 caratteri in out.
 * decodifica: servono (caratteri / 3 + 1) * 2 byte in out.
 * Tutte e due ritornano la lunghezza scritta, oppure -1 se out e' troppo
 * piccolo o l'ingresso non e' valido.
 */
long opencard_base44_codifica(const unsigned char *dati, size_t n,
                              char *out, size_t out_size);
long opencard_base44_decodifica(const char *testo, size_t n,
                                unsigned char *out, size_t out_size);

#ifdef __cplusplus
}
#endif

#endif /* OPENCARD_TRANSFER_H */
