/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

#include "csv.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VERSIONE "2"

static const char *const COLONNE =
    "_id,store,note,validfrom,expiry,balance,balancetype,cardid,barcodeid,"
    "barcodetype,barcodeencoding,headercolor,starstatus,lastused,archive";

/* I nomi delle simbologie come li scrive Catima, per le nostre diciotto, in
 * ordine di numero. Le cinque che loro non hanno cadono sulla più vicina che
 * sanno disegnare; in lettura vince il primo nome uguale. */
static const char *const NOMI_CATIMA[] = {
    "CODE_128", "QR_CODE", "AZTEC", "CODABAR", "CODE_39", "CODE_93",
    "DATA_MATRIX", "EAN_8", "EAN_13", "ITF", "PDF_417", "UPC_A", "UPC_E",
    "QR_CODE", "CODE_128", "RSS_14", "RSS_EXPANDED", "CODE_128"
};
#define N_NOMI ((int)(sizeof(NOMI_CATIMA) / sizeof(NOMI_CATIMA[0])))

static opencard_esito segnala(opencard_errore *errore, opencard_esito codice)
{
    if (errore != NULL) {
        errore->codice = codice;
        errore->posizione = 0;
        errore->dettaglio[0] = '\0';
        errore->schema_trovato = 0;
    }
    return codice;
}

static int spazio(char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

int opencard_csv_e_csv(const unsigned char *dati, size_t quanti)
{
    size_t testa, i = 0, j;

    if (dati == NULL) {
        return 0;
    }
    testa = quanti < 200 ? quanti : 200;
    while (i < testa && spazio((char)dati[i])) {
        i++;
    }
    if (i >= testa || dati[i] != VERSIONE[0]) {
        return 0;
    }
    for (j = 0; j + 3 <= testa; j++) {
        if (memcmp(dati + j, "_id", 3) == 0) {
            return 1;
        }
    }
    return 0;
}

/* ------------------------------------------------------------------ le date */

/* Giorni dal 1970-01-01 e ritorno, con il calendario gregoriano anche prima
 * del 1582, come fanno le due librerie di sistema in UTC. L'algoritmo è
 * quello di Howard Hinnant, «chrono-compatible low-level date algorithms». */
static long long giorni_da_data(long long a, int m, int g)
{
    long long era;
    long long anno_era, giorno_anno, giorno_era;

    a -= m <= 2;
    era = (a >= 0 ? a : a - 399) / 400;
    anno_era = a - era * 400;
    giorno_anno = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + g - 1;
    giorno_era = anno_era * 365 + anno_era / 4 - anno_era / 100 + giorno_anno;
    return era * 146097 + giorno_era - 719468;
}

static void data_da_giorni(long long z, long long *a, int *m, int *g)
{
    long long era, giorno_era, anno_era, giorno_anno, mp;

    z += 719468;
    era = (z >= 0 ? z : z - 146096) / 146097;
    giorno_era = z - era * 146097;
    anno_era = (giorno_era - giorno_era / 1460 + giorno_era / 36524
                - giorno_era / 146096) / 365;
    giorno_anno = giorno_era - (365 * anno_era + anno_era / 4 - anno_era / 100);
    mp = (5 * giorno_anno + 2) / 153;
    *g = (int)(giorno_anno - (153 * mp + 2) / 5 + 1);
    *m = (int)(mp < 10 ? mp + 3 : mp - 9);
    *a = anno_era + era * 400 + (*m <= 2);
}

static int cifre(const char *s, int n)
{
    int i;

    for (i = 0; i < n; i++) {
        if (s[i] < '0' || s[i] > '9') {
            return 0;
        }
    }
    return 1;
}

/* "AAAA-MM-GG" nei millisecondi che vuole Catima, mezzanotte UTC, o vuoto. */
static void millis_da_data(const char *data, char *out, size_t out_size)
{
    int m, g;

    out[0] = '\0';
    if (strlen(data) != 10 || data[4] != '-' || data[7] != '-'
        || !cifre(data, 4) || !cifre(data + 5, 2) || !cifre(data + 8, 2)) {
        return;
    }
    m = atoi(data + 5);
    g = atoi(data + 8);
    if (m < 1 || m > 12) {
        return;
    }
    snprintf(out, out_size, "%lld",
             giorni_da_data(atoll(data), m, g) * 86400000LL);
}

/* Il contrario: i millisecondi di Catima in "AAAA-MM-GG", o vuoto se il
 * campo è vuoto, è zero o non è un numero. */
static void data_da_millis(const char *testo, char *out, size_t out_size)
{
    char *fine;
    long long millis, giorni, a;
    int m, g;

    out[0] = '\0';
    if (testo[0] == '\0') {
        return;
    }
    errno = 0;
    millis = strtoll(testo, &fine, 10);
    if (errno != 0 || *fine != '\0' || millis == 0) {
        return;
    }
    giorni = millis / 86400000LL;
    if (millis % 86400000LL < 0) {
        giorni--;
    }
    data_da_giorni(giorni, &a, &m, &g);
    if (a < 0 || a > 9999) {
        return;
    }
    snprintf(out, out_size, "%04lld-%02d-%02d", a, m, g);
}

/* ----------------------------------------------------------------- i colori */

/* "#RRGGBB" nel numero intero con cui lo scrive Android, alfa piena davanti:
 * lo stesso numero da tutti e due i telefoni. */
static void colore_intero(const char *colore, char *out, size_t out_size)
{
    unsigned long valore;
    char *fine;

    out[0] = '\0';
    if (colore[0] != '#' || strlen(colore) != 7) {
        return;
    }
    valore = strtoul(colore + 1, &fine, 16);
    if (*fine != '\0') {
        return;
    }
    snprintf(out, out_size, "%d", (int)(unsigned int)(valore | 0xFF000000UL));
}

static void colore_da_intero(const char *testo, char *out, size_t out_size)
{
    char *fine;
    long long valore;

    out[0] = '\0';
    if (testo[0] == '\0') {
        return;
    }
    errno = 0;
    valore = strtoll(testo, &fine, 10);
    if (errno != 0 || *fine != '\0' || valore < -2147483648LL || valore > 2147483647LL) {
        return;
    }
    snprintf(out, out_size, "#%06X", (unsigned int)(valore & 0xFFFFFF));
}

/* ------------------------------------------------------------- in uscita */

typedef struct {
    char *p;
    size_t n;
    size_t cap;
} buffer;

static int aggiungi(buffer *b, const char *s, size_t n)
{
    if (b->n + n + 1 > b->cap) {
        size_t nuova = b->cap ? b->cap : 4096;
        char *altro;

        while (b->n + n + 1 > nuova) {
            nuova *= 2;
        }
        altro = realloc(b->p, nuova);
        if (altro == NULL) {
            return 0;
        }
        b->p = altro;
        b->cap = nuova;
    }
    memcpy(b->p + b->n, s, n);
    b->n += n;
    b->p[b->n] = '\0';
    return 1;
}

static int testo(buffer *b, const char *s)
{
    return aggiungi(b, s, strlen(s));
}

/* Un campo fra virgolette quando contiene virgole, virgolette o a capo. */
static int campo(buffer *b, const char *s, int primo)
{
    const char *c;

    if (!primo && !aggiungi(b, ",", 1)) {
        return 0;
    }
    if (strpbrk(s, ",\"\n\r") == NULL) {
        return testo(b, s);
    }
    if (!aggiungi(b, "\"", 1)) {
        return 0;
    }
    for (c = s; *c != '\0'; c++) {
        if (*c == '"' && !aggiungi(b, "\"", 1)) {
            return 0;
        }
        if (!aggiungi(b, c, 1)) {
            return 0;
        }
    }
    return aggiungi(b, "\"", 1);
}

opencard_esito opencard_csv_scrivi(const opencard_lista *lista, char **uscita,
                                   size_t *quanti, opencard_errore *errore)
{
    buffer b = {NULL, 0, 0};
    size_t i;
    int ok;

    if (lista == NULL || uscita == NULL || quanti == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    *uscita = NULL;
    *quanti = 0;

    ok = testo(&b, VERSIONE "\n\n") && testo(&b, "_id\n\n")   /* nessun gruppo */
         && testo(&b, COLONNE) && testo(&b, "\n");

    for (i = 0; ok && i < lista->n; i++) {
        const opencard_card *carta = &lista->carte[i];
        char id[16], millis[24], colore[OPENCARD_COLOR_MAX], intero[16];
        int s = (int)carta->simbologia;

        snprintf(id, sizeof(id), "%d", carta->id);
        millis_da_data(carta->scadenza, millis, sizeof(millis));
        /* Il colore che si vede, anche quando lo decide l'id: Catima non lo
         * saprebbe calcolare. */
        opencard_card_color(carta, colore, sizeof(colore));
        colore_intero(colore, intero, sizeof(intero));

        ok = campo(&b, id, 1)
             && campo(&b, carta->label, 0)
             && campo(&b, carta->note, 0)
             && campo(&b, "", 0)                        /* validfrom */
             && campo(&b, millis, 0)
             && campo(&b, carta->saldo, 0)
             && campo(&b, "", 0)                        /* balancetype */
             && campo(&b, carta->code, 0)
             && campo(&b, "", 0)                        /* barcodeid */
             && campo(&b, s >= 0 && s < N_NOMI ? NOMI_CATIMA[s] : "CODE_128", 0)
             && campo(&b, "UTF-8", 0)
             && campo(&b, intero, 0)
             && campo(&b, carta->favorite ? "1" : "0", 0)
             && campo(&b, "", 0)                        /* lastused */
             && campo(&b, "0", 0)                       /* archive */
             && testo(&b, "\n");
    }
    ok = ok && testo(&b, "\ncardId,groupId\n");

    if (!ok) {
        free(b.p);
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    *uscita = b.p;
    *quanti = b.n;
    return OPENCARD_OK;
}

/* ------------------------------------------------------------- in entrata */

/* Una riga del CSV: i campi uno dopo l'altro in `testo`, ognuno chiuso dal
 * suo NUL, e dove comincia ciascuno in `inizi`. */
typedef struct {
    buffer testo;
    size_t *inizi;
    size_t n;
    size_t cap;
} riga_csv;

static int chiudi_campo(riga_csv *r)
{
    if (r->n == r->cap) {
        size_t nuova = r->cap ? r->cap * 2 : 32;
        size_t *altro = realloc(r->inizi, nuova * sizeof(*altro));

        if (altro == NULL) {
            return 0;
        }
        r->inizi = altro;
        r->cap = nuova;
    }
    /* L'inizio del campo è dove finiva il NUL del precedente. */
    r->inizi[r->n] = r->n == 0 ? 0 : r->inizi[r->n - 1]
                     + strlen(r->testo.p + r->inizi[r->n - 1]) + 1;
    r->n++;
    return aggiungi(&r->testo, "", 1);
}

static const char *valore(const riga_csv *r, size_t i)
{
    return i < r->n ? r->testo.p + r->inizi[i] : "";
}

static int riga_vuota(const riga_csv *r)
{
    size_t i;

    for (i = 0; i < r->n; i++) {
        if (valore(r, i)[0] != '\0') {
            return 0;
        }
    }
    return 1;
}

/* La riga che comincia a `*pos`, tenendo conto delle virgolette: una nota può
 * contenere virgole e andare a capo, e spezzare senza guardarle spaccherebbe
 * proprio le carte con una nota lunga. Torna 0 a fine testo, -1 se manca la
 * memoria. L'ultima riga senza a capo conta solo se ha qualcosa dentro. */
static int prossima_riga(const char *t, size_t n, size_t *pos, riga_csv *r)
{
    size_t i = *pos;
    int fra_virgolette = 0;

    r->n = 0;
    r->testo.n = 0;
    if (r->testo.p == NULL && !aggiungi(&r->testo, "", 0)) {
        return -1;
    }
    r->testo.p[0] = '\0';
    if (i >= n) {
        return 0;
    }

    for (; i < n; i++) {
        char c = t[i];

        if (fra_virgolette && c == '"' && i + 1 < n && t[i + 1] == '"') {
            if (!aggiungi(&r->testo, "\"", 1)) {
                return -1;
            }
            i++;
        } else if (c == '"') {
            fra_virgolette = !fra_virgolette;
        } else if (!fra_virgolette && c == ',') {
            if (!chiudi_campo(r)) {
                return -1;
            }
        } else if (!fra_virgolette && (c == '\n' || c == '\r')) {
            if (c == '\r' && i + 1 < n && t[i + 1] == '\n') {
                i++;
            }
            if (!chiudi_campo(r)) {
                return -1;
            }
            *pos = i + 1;
            return 1;
        } else if (!aggiungi(&r->testo, &c, 1)) {
            return -1;
        }
    }
    if (!chiudi_campo(r)) {
        return -1;
    }
    *pos = n;
    return riga_vuota(r) ? 0 : 1;
}

static void libera_riga(riga_csv *r)
{
    free(r->testo.p);
    free(r->inizi);
}

static void metti(char *dest, size_t dest_size, const char *sorgente)
{
    snprintf(dest, dest_size, "%s", sorgente);
    /* Il taglio può cadere a metà di una lettera accentata. */
    opencard_utf8_ripara(dest);
}

static void togli_spazi(const char *s, char *out, size_t out_size)
{
    size_t inizio = 0, fine = strlen(s);

    while (inizio < fine && spazio(s[inizio])) {
        inizio++;
    }
    while (fine > inizio && spazio(s[fine - 1])) {
        fine--;
    }
    snprintf(out, out_size, "%.*s", (int)(fine - inizio), s + inizio);
}

/* Il saldo di Catima è un numero con accanto il tipo, il nostro è testo
 * libero: si uniscono. Zero vuol dire "non compilato", ed è il valore che
 * mettono a tutte le carte che non hanno un saldo. */
static void saldo_leggibile(const char *quanto, const char *tipo,
                            char *out, size_t out_size)
{
    char pulito[OPENCARD_SALDO_MAX * 2], unita[OPENCARD_SALDO_MAX * 2];
    size_t n;

    out[0] = '\0';
    togli_spazi(quanto, pulito, sizeof(pulito));
    n = strlen(pulito);
    while (n > 0 && pulito[n - 1] == '0') {
        n--;
    }
    if (n > 0 && (pulito[n - 1] == '.' || pulito[n - 1] == ',')) {
        n--;
    }
    if (n == 0 || (n == 1 && pulito[0] == '0')) {
        return;
    }
    togli_spazi(tipo, unita, sizeof(unita));
    if (unita[0] == '\0') {
        metti(out, out_size, pulito);
    } else {
        char unito[OPENCARD_SALDO_MAX * 4];

        snprintf(unito, sizeof(unito), "%s %s", pulito, unita);
        metti(out, out_size, unito);
    }
}

static opencard_simbologia simbologia_da_catima(const char *nome, const char *codice)
{
    char maiuscolo[32];
    size_t i;
    int s;

    for (i = 0; nome[i] != '\0' && i + 1 < sizeof(maiuscolo); i++) {
        maiuscolo[i] = (nome[i] >= 'a' && nome[i] <= 'z') ? (char)(nome[i] - 32) : nome[i];
    }
    maiuscolo[i] = '\0';
    for (s = 0; s < N_NOMI; s++) {
        if (strcmp(maiuscolo, NOMI_CATIMA[s]) == 0) {
            return (opencard_simbologia)s;
        }
    }
    /* Un tipo che non conosciamo, o assente, si indovina dal codice: meglio un
     * EAN riconosciuto che un Code 128 a caso. */
    return opencard_simbologia_indovinata(codice, 0);
}

/* Dove sta la colonna `nome` nell'intestazione, o (size_t)-1. */
static size_t colonna(const riga_csv *intestazione, const char *nome)
{
    size_t i;

    for (i = 0; i < intestazione->n; i++) {
        if (strcmp(valore(intestazione, i), nome) == 0) {
            return i;
        }
    }
    return (size_t)-1;
}

enum { C_STORE, C_NOTE, C_EXPIRY, C_BALANCE, C_BALANCETYPE, C_CARDID,
       C_BARCODETYPE, C_HEADERCOLOR, C_STARSTATUS, C_QUANTE };

static const char *const NOMI_COLONNE[C_QUANTE] = {
    "store", "note", "expiry", "balance", "balancetype", "cardid",
    "barcodetype", "headercolor", "starstatus"
};

static int metti_in_lista(opencard_lista *lista, const opencard_card *carta)
{
    if (lista->n == lista->capacita) {
        size_t nuova = lista->capacita ? lista->capacita * 2 : 16;
        opencard_card *altro = realloc(lista->carte, nuova * sizeof(*altro));

        if (altro == NULL) {
            return 0;
        }
        lista->carte = altro;
        lista->capacita = nuova;
    }
    lista->carte[lista->n++] = *carta;
    return 1;
}

opencard_esito opencard_csv_leggi(const unsigned char *dati, size_t quanti,
                                  opencard_lista *out, opencard_errore *errore)
{
    const char *t = (const char *)dati;
    riga_csv riga = {{NULL, 0, 0}, NULL, 0, 0};
    riga_csv testa = {{NULL, 0, 0}, NULL, 0, 0};
    size_t pos = 0, dove[C_QUANTE], colonne;
    int letta, k;

    if (dati == NULL || out == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    memset(out, 0, sizeof(*out));

    /* L'intestazione delle carte: la prima riga che comincia con "_id" e ha
     * più di cinque colonne. Quella dei gruppi ne ha una sola. */
    while ((letta = prossima_riga(t, quanti, &pos, &testa)) == 1) {
        if (testa.n > 5 && strcmp(valore(&testa, 0), "_id") == 0) {
            break;
        }
    }
    if (letta != 1) {
        libera_riga(&testa);
        return letta < 0 ? segnala(errore, OPENCARD_ERR_MEMORIA) : OPENCARD_OK;
    }
    colonne = testa.n;
    for (k = 0; k < C_QUANTE; k++) {
        dove[k] = colonna(&testa, NOMI_COLONNE[k]);
    }

    while ((letta = prossima_riga(t, quanti, &pos, &riga)) == 1) {
        opencard_card carta;
        char campo_saldo[OPENCARD_SALDO_MAX];

        /* La tabella finisce dove finiscono le colonne: dopo c'è la riga vuota
         * e poi i collegamenti ai gruppi. */
        if (riga.n < colonne || riga_vuota(&riga)) {
            break;
        }
        if (valore(&riga, dove[C_STORE])[0] == '\0'
            || valore(&riga, dove[C_CARDID])[0] == '\0') {
            continue;
        }

        memset(&carta, 0, sizeof(carta));
        metti(carta.label, sizeof(carta.label), valore(&riga, dove[C_STORE]));
        metti(carta.code, sizeof(carta.code), valore(&riga, dove[C_CARDID]));
        carta.simbologia = simbologia_da_catima(valore(&riga, dove[C_BARCODETYPE]),
                                                carta.code);
        carta.is_qrcode = carta.simbologia == OPENCARD_SIM_QR
                          || carta.simbologia == OPENCARD_SIM_MICROQR;
        colore_da_intero(valore(&riga, dove[C_HEADERCOLOR]), carta.color,
                         sizeof(carta.color));
        carta.favorite = strcmp(valore(&riga, dove[C_STARSTATUS]), "1") == 0;
        metti(carta.note, sizeof(carta.note), valore(&riga, dove[C_NOTE]));
        data_da_millis(valore(&riga, dove[C_EXPIRY]), carta.scadenza,
                       sizeof(carta.scadenza));
        saldo_leggibile(valore(&riga, dove[C_BALANCE]),
                        valore(&riga, dove[C_BALANCETYPE]),
                        campo_saldo, sizeof(campo_saldo));
        metti(carta.saldo, sizeof(carta.saldo), campo_saldo);

        if (!metti_in_lista(out, &carta)) {
            letta = -1;
            break;
        }
    }
    libera_riga(&riga);
    libera_riga(&testa);
    if (letta < 0) {
        opencard_lista_free(out);
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    return OPENCARD_OK;
}
