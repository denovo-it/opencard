/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

#include "archivio.h"

#include <stdlib.h>
#include <string.h>

#include <zlib.h>

/* Le firme dei tre pezzi di uno ZIP. */
#define FIRMA_LOCALE  0x04034b50u
#define FIRMA_INDICE  0x02014b50u
#define FIRMA_FINE    0x06054b50u

#define TESTA_LOCALE  30
#define TESTA_INDICE  46
#define TESTA_FINE    22

/* Un archivio di tessere sta in pochi MB. Il tetto serve a non farsi allocare
 * gigabyte da un file scritto apposta. */
#define ARCHIVIO_MAX (64u * 1024u * 1024u)

/* ---------------------------------------------------------------- buffer */

typedef struct {
    unsigned char *dati;
    size_t n;
    size_t capacita;
} buffer;

static int buffer_spazio(buffer *b, size_t serve)
{
    size_t nuova;
    unsigned char *piu_grande;

    if (b->n + serve <= b->capacita) {
        return 1;
    }
    nuova = b->capacita > 0 ? b->capacita : 4096;
    while (nuova < b->n + serve) {
        if (nuova > ARCHIVIO_MAX) {
            return 0;
        }
        nuova *= 2;
    }
    piu_grande = realloc(b->dati, nuova);
    if (piu_grande == NULL) {
        return 0;
    }
    b->dati = piu_grande;
    b->capacita = nuova;
    return 1;
}

static int scrivi_byte(buffer *b, const void *dati, size_t quanti)
{
    if (!buffer_spazio(b, quanti)) {
        return 0;
    }
    memcpy(b->dati + b->n, dati, quanti);
    b->n += quanti;
    return 1;
}

/* Nello ZIP i numeri stanno in little endian, sempre, su qualunque macchina. */
static int scrivi16(buffer *b, unsigned valore)
{
    unsigned char pezzo[2];

    pezzo[0] = (unsigned char)(valore & 0xff);
    pezzo[1] = (unsigned char)((valore >> 8) & 0xff);
    return scrivi_byte(b, pezzo, 2);
}

static int scrivi32(buffer *b, unsigned long valore)
{
    unsigned char pezzo[4];

    pezzo[0] = (unsigned char)(valore & 0xff);
    pezzo[1] = (unsigned char)((valore >> 8) & 0xff);
    pezzo[2] = (unsigned char)((valore >> 16) & 0xff);
    pezzo[3] = (unsigned char)((valore >> 24) & 0xff);
    return scrivi_byte(b, pezzo, 4);
}

static unsigned leggi16(const unsigned char *p)
{
    return (unsigned)p[0] | ((unsigned)p[1] << 8);
}

static unsigned long leggi32(const unsigned char *p)
{
    return (unsigned long)p[0] | ((unsigned long)p[1] << 8)
         | ((unsigned long)p[2] << 16) | ((unsigned long)p[3] << 24);
}

/* ------------------------------------------------------------- compressione */

/* Deflate grezzo, quello che lo ZIP chiama metodo 8: `windowBits` negativo
 * toglie l'intestazione zlib, che dentro un archivio non ci va.
 *
 * Torna 0 se non conviene comprimere: le foto sono JPEG, già compressi, e su
 * quelli il deflate cresce invece di ridurre. In quel caso si scrive il file
 * com'è, metodo 0, che ogni lettore capisce. */
static int comprimi(const unsigned char *dentro, size_t quanti,
                    unsigned char **fuori, size_t *fuori_n)
{
    z_stream flusso;
    unsigned char *spazio;
    size_t massimo;

    *fuori = NULL;
    *fuori_n = 0;
    if (quanti == 0) {
        return 0;
    }

    memset(&flusso, 0, sizeof(flusso));
    if (deflateInit2(&flusso, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8,
                     Z_DEFAULT_STRATEGY) != Z_OK) {
        return 0;
    }

    massimo = deflateBound(&flusso, (uLong)quanti);
    spazio = malloc(massimo > 0 ? massimo : 1);
    if (spazio == NULL) {
        deflateEnd(&flusso);
        return 0;
    }

    flusso.next_in = (Bytef *)dentro;
    flusso.avail_in = (uInt)quanti;
    flusso.next_out = spazio;
    flusso.avail_out = (uInt)massimo;

    if (deflate(&flusso, Z_FINISH) != Z_STREAM_END) {
        deflateEnd(&flusso);
        free(spazio);
        return 0;
    }
    *fuori_n = (size_t)flusso.total_out;
    deflateEnd(&flusso);

    if (*fuori_n >= quanti) {
        free(spazio);
        *fuori_n = 0;
        return 0;
    }
    *fuori = spazio;
    return 1;
}

static int decomprimi(const unsigned char *dentro, size_t quanti,
                      size_t attesi, unsigned char **fuori)
{
    z_stream flusso;
    unsigned char *spazio;

    *fuori = NULL;
    spazio = malloc(attesi + 1);
    if (spazio == NULL) {
        return 0;
    }

    memset(&flusso, 0, sizeof(flusso));
    if (inflateInit2(&flusso, -15) != Z_OK) {
        free(spazio);
        return 0;
    }
    flusso.next_in = (Bytef *)dentro;
    flusso.avail_in = (uInt)quanti;
    flusso.next_out = spazio;
    flusso.avail_out = (uInt)attesi;

    if (inflate(&flusso, Z_FINISH) != Z_STREAM_END || flusso.total_out != attesi) {
        inflateEnd(&flusso);
        free(spazio);
        return 0;
    }
    inflateEnd(&flusso);
    spazio[attesi] = '\0';
    *fuori = spazio;
    return 1;
}

/* ---------------------------------------------------------------- scrittura */

int opencard_zip_e_archivio(const unsigned char *dati, size_t quanti)
{
    return dati != NULL && quanti > 4 && dati[0] == 'P' && dati[1] == 'K'
        && dati[2] == 0x03 && dati[3] == 0x04;
}

static opencard_esito fallisci(opencard_errore *errore, opencard_esito codice)
{
    if (errore != NULL) {
        errore->codice = codice;
        errore->posizione = 0;
        errore->dettaglio[0] = '\0';
        errore->schema_trovato = 0;
    }
    return codice;
}

opencard_esito opencard_zip_scrivi(const opencard_zip_voce *voci, size_t n,
                                   unsigned char **fuori, size_t *fuori_n,
                                   opencard_errore *errore)
{
    buffer archivio = {NULL, 0, 0};
    size_t *inizi = NULL;
    unsigned *metodi = NULL;
    size_t *compressi = NULL;
    unsigned long *somme = NULL;
    size_t i, inizio_indice, fine_indice;

    if (voci == NULL || fuori == NULL || fuori_n == NULL || n == 0) {
        return fallisci(errore, OPENCARD_ERR_ARGOMENTI);
    }
    *fuori = NULL;
    *fuori_n = 0;

    inizi = calloc(n, sizeof(size_t));
    metodi = calloc(n, sizeof(unsigned));
    compressi = calloc(n, sizeof(size_t));
    somme = calloc(n, sizeof(unsigned long));
    if (inizi == NULL || metodi == NULL || compressi == NULL || somme == NULL) {
        free(inizi); free(metodi); free(compressi); free(somme);
        return fallisci(errore, OPENCARD_ERR_MEMORIA);
    }

    /* Prima i file, uno dietro l'altro, ognuno con la sua intestazione. */
    for (i = 0; i < n; i++) {
        size_t lunghezza_nome = strlen(voci[i].nome);
        unsigned char *pacchetto = NULL;
        size_t pacchetto_n = 0;
        const unsigned char *da_scrivere = voci[i].dati;
        size_t da_scrivere_n = voci[i].quanti;

        if (lunghezza_nome == 0 || lunghezza_nome > 200) {
            free(inizi); free(metodi); free(compressi); free(somme);
            free(archivio.dati);
            return fallisci(errore, OPENCARD_ERR_ARGOMENTI);
        }

        somme[i] = crc32(0L, voci[i].dati, (uInt)voci[i].quanti);

        if (comprimi(voci[i].dati, voci[i].quanti, &pacchetto, &pacchetto_n)) {
            metodi[i] = 8;
            da_scrivere = pacchetto;
            da_scrivere_n = pacchetto_n;
        } else {
            metodi[i] = 0;
        }
        compressi[i] = da_scrivere_n;
        inizi[i] = archivio.n;

        if (!scrivi32(&archivio, FIRMA_LOCALE) || !scrivi16(&archivio, 20)
            || !scrivi16(&archivio, 0) || !scrivi16(&archivio, metodi[i])
            /* Ora e data a zero: la data di un file dentro l'archivio non
             * dice niente a nessuno, e a zero l'archivio è riproducibile. */
            || !scrivi16(&archivio, 0) || !scrivi16(&archivio, 0)
            || !scrivi32(&archivio, somme[i])
            || !scrivi32(&archivio, (unsigned long)da_scrivere_n)
            || !scrivi32(&archivio, (unsigned long)voci[i].quanti)
            || !scrivi16(&archivio, (unsigned)lunghezza_nome)
            || !scrivi16(&archivio, 0)
            || !scrivi_byte(&archivio, voci[i].nome, lunghezza_nome)
            || !scrivi_byte(&archivio, da_scrivere, da_scrivere_n)) {
            free(pacchetto);
            free(inizi); free(metodi); free(compressi); free(somme);
            free(archivio.dati);
            return fallisci(errore, OPENCARD_ERR_MEMORIA);
        }
        free(pacchetto);
    }

    /* Poi l'indice, che ripete le stesse cose più la posizione di ognuno. */
    inizio_indice = archivio.n;
    for (i = 0; i < n; i++) {
        size_t lunghezza_nome = strlen(voci[i].nome);

        if (!scrivi32(&archivio, FIRMA_INDICE) || !scrivi16(&archivio, 20)
            || !scrivi16(&archivio, 20) || !scrivi16(&archivio, 0)
            || !scrivi16(&archivio, metodi[i])
            || !scrivi16(&archivio, 0) || !scrivi16(&archivio, 0)
            || !scrivi32(&archivio, somme[i])
            || !scrivi32(&archivio, (unsigned long)compressi[i])
            || !scrivi32(&archivio, (unsigned long)voci[i].quanti)
            || !scrivi16(&archivio, (unsigned)lunghezza_nome)
            || !scrivi16(&archivio, 0) || !scrivi16(&archivio, 0)
            || !scrivi16(&archivio, 0) || !scrivi16(&archivio, 0)
            || !scrivi32(&archivio, 0)
            || !scrivi32(&archivio, (unsigned long)inizi[i])
            || !scrivi_byte(&archivio, voci[i].nome, lunghezza_nome)) {
            free(inizi); free(metodi); free(compressi); free(somme);
            free(archivio.dati);
            return fallisci(errore, OPENCARD_ERR_MEMORIA);
        }
    }
    fine_indice = archivio.n;

    /* In fondo la chiusura, che dice dov'è l'indice: un lettore parte da qui. */
    if (!scrivi32(&archivio, FIRMA_FINE) || !scrivi16(&archivio, 0)
        || !scrivi16(&archivio, 0) || !scrivi16(&archivio, (unsigned)n)
        || !scrivi16(&archivio, (unsigned)n)
        || !scrivi32(&archivio, (unsigned long)(fine_indice - inizio_indice))
        || !scrivi32(&archivio, (unsigned long)inizio_indice)
        || !scrivi16(&archivio, 0)) {
        free(inizi); free(metodi); free(compressi); free(somme);
        free(archivio.dati);
        return fallisci(errore, OPENCARD_ERR_MEMORIA);
    }

    free(inizi); free(metodi); free(compressi); free(somme);
    *fuori = archivio.dati;
    *fuori_n = archivio.n;
    return OPENCARD_OK;
}

/* ----------------------------------------------------------------- lettura */

/* La chiusura sta in fondo, ma dopo può esserci un commento: si cerca
 * all'indietro, e un commento più lungo di 64 kB non esiste. */
static const unsigned char *trova_fine(const unsigned char *dati, size_t quanti)
{
    size_t i, limite;

    if (quanti < TESTA_FINE) {
        return NULL;
    }
    limite = quanti > 65535 + TESTA_FINE ? 65535 + TESTA_FINE : quanti;

    for (i = TESTA_FINE; i <= limite; i++) {
        const unsigned char *p = dati + quanti - i;
        if (leggi32(p) == FIRMA_FINE) {
            return p;
        }
    }
    return NULL;
}

opencard_esito opencard_zip_leggi(const unsigned char *dati, size_t quanti,
                                  opencard_zip_lettura *out,
                                  opencard_errore *errore)
{
    const unsigned char *fine;
    size_t inizio_indice, i, quante;
    const unsigned char *voce;

    if (dati == NULL || out == NULL || quanti == 0) {
        return fallisci(errore, OPENCARD_ERR_ARGOMENTI);
    }
    out->voci = NULL;
    out->n = 0;

    fine = trova_fine(dati, quanti);
    if (fine == NULL) {
        return fallisci(errore, OPENCARD_ERR_JSON);
    }
    quante = leggi16(fine + 10);
    inizio_indice = (size_t)leggi32(fine + 16);

    if (quante == 0 || quante > 4096 || inizio_indice >= quanti) {
        return fallisci(errore, OPENCARD_ERR_JSON);
    }

    out->voci = calloc(quante, sizeof(opencard_zip_voce));
    if (out->voci == NULL) {
        return fallisci(errore, OPENCARD_ERR_MEMORIA);
    }

    voce = dati + inizio_indice;
    for (i = 0; i < quante; i++) {
        unsigned metodo, lunghezza_nome, extra, commento;
        size_t compressa, distesa, dove, testa;
        const unsigned char *locale;
        unsigned char *contenuto = NULL;

        if ((size_t)(voce - dati) + TESTA_INDICE > quanti
            || leggi32(voce) != FIRMA_INDICE) {
            opencard_zip_libera(out);
            return fallisci(errore, OPENCARD_ERR_JSON);
        }
        metodo = leggi16(voce + 10);
        compressa = (size_t)leggi32(voce + 20);
        distesa = (size_t)leggi32(voce + 24);
        lunghezza_nome = leggi16(voce + 28);
        extra = leggi16(voce + 30);
        commento = leggi16(voce + 32);
        dove = (size_t)leggi32(voce + 42);

        if (lunghezza_nome == 0 || lunghezza_nome >= sizeof(out->voci[i].nome)
            || distesa > ARCHIVIO_MAX || dove + TESTA_LOCALE > quanti) {
            opencard_zip_libera(out);
            return fallisci(errore, OPENCARD_ERR_JSON);
        }
        memcpy(out->voci[i].nome, voce + TESTA_INDICE, lunghezza_nome);
        out->voci[i].nome[lunghezza_nome] = '\0';

        /* Il nome e gli extra dell'intestazione locale possono essere diversi
         * da quelli dell'indice: i byte del file cominciano dopo i suoi. */
        locale = dati + dove;
        if (leggi32(locale) != FIRMA_LOCALE) {
            opencard_zip_libera(out);
            return fallisci(errore, OPENCARD_ERR_JSON);
        }
        testa = TESTA_LOCALE + leggi16(locale + 26) + leggi16(locale + 28);
        if (dove + testa + compressa > quanti) {
            opencard_zip_libera(out);
            return fallisci(errore, OPENCARD_ERR_JSON);
        }

        if (metodo == 0) {
            contenuto = malloc(distesa + 1);
            if (contenuto == NULL) {
                opencard_zip_libera(out);
                return fallisci(errore, OPENCARD_ERR_MEMORIA);
            }
            memcpy(contenuto, locale + testa, distesa);
            contenuto[distesa] = '\0';
        } else if (metodo == 8) {
            if (!decomprimi(locale + testa, compressa, distesa, &contenuto)) {
                opencard_zip_libera(out);
                return fallisci(errore, OPENCARD_ERR_JSON);
            }
        } else {
            opencard_zip_libera(out);
            return fallisci(errore, OPENCARD_ERR_JSON);
        }

        out->voci[i].dati = contenuto;
        out->voci[i].quanti = distesa;
        out->n = i + 1;

        voce += TESTA_INDICE + lunghezza_nome + extra + commento;
    }
    return OPENCARD_OK;
}

void opencard_zip_libera(opencard_zip_lettura *lettura)
{
    size_t i;

    if (lettura == NULL || lettura->voci == NULL) {
        return;
    }
    for (i = 0; i < lettura->n; i++) {
        free(lettura->voci[i].dati);
    }
    free(lettura->voci);
    lettura->voci = NULL;
    lettura->n = 0;
}

void opencard_zip_free(unsigned char *dati)
{
    free(dati);
}
