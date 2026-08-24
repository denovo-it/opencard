/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 *
 * Passaggio delle carte fra due telefoni con dei QR. Il perché delle scelte
 * sta in transfer.h.
 */

#include <stdlib.h>
#include <string.h>

#include <zlib.h>

#include "transfer.h"

/* Byte utili in una fetta, intestazione compresa. Con 950 byte il testo base44
 * viene di 1425 caratteri, e in un QR di versione 25 con correzione M ce ne
 * stanno 1451: il margine copre le versioni future dell'intestazione. */
#define FETTA_MAX 950

/* 'O','C', formato, indice, totale, crc32 (4 byte, little endian). Il CRC vale
 * anche da nome del trasferimento: due passaggi diversi non si mescolano. */
#define INTESTAZIONE 9

#define FLAG_QRCODE     0x01
#define FLAG_USA_GETTA  0x02
#define FLAG_COLORE     0x04
#define FLAG_CIFRE      0x08
#define FLAG_PREFERITA  0x10

static const char ALFABETO[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ$%*+-./:";
#define BASE 44

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

static void pulisci_errore(opencard_errore *errore)
{
    if (errore != NULL) {
        errore->codice = OPENCARD_OK;
        errore->posizione = 0;
        errore->dettaglio[0] = '\0';
        errore->schema_trovato = 0;
    }
}

/* -------------------------------------------------------------- base44 --- */

static int valore(char c)
{
    const char *p = strchr(ALFABETO, c);

    if (c == '\0' || p == NULL) {
        return -1;
    }
    return (int)(p - ALFABETO);
}

long opencard_base44_codifica(const unsigned char *dati, size_t n,
                              char *out, size_t out_size)
{
    size_t i, scritti = 0;

    if (dati == NULL || out == NULL) {
        return -1;
    }
    if (out_size < (n + 1) / 2 * 3 + 1) {
        return -1;
    }
    for (i = 0; i + 1 < n; i += 2) {
        unsigned int v = (unsigned int)dati[i] * 256u + dati[i + 1];

        out[scritti++] = ALFABETO[v % BASE];
        out[scritti++] = ALFABETO[(v / BASE) % BASE];
        out[scritti++] = ALFABETO[v / (BASE * BASE)];
    }
    if (i < n) {
        /* Byte spaiato in fondo: due caratteri bastano, 44*44 supera 255. */
        unsigned int v = dati[i];

        out[scritti++] = ALFABETO[v % BASE];
        out[scritti++] = ALFABETO[v / BASE];
    }
    out[scritti] = '\0';
    return (long)scritti;
}

long opencard_base44_decodifica(const char *testo, size_t n,
                                unsigned char *out, size_t out_size)
{
    size_t i, scritti = 0;

    if (testo == NULL || out == NULL) {
        return -1;
    }
    if (n == 0) {
        n = strlen(testo);
    }
    if (n % 3 == 1) {
        return -1;      /* nessuna codifica finisce con un carattere solo */
    }
    if (out_size < n / 3 * 2 + 2) {
        return -1;
    }
    for (i = 0; i + 2 < n; i += 3) {
        int a = valore(testo[i]), b = valore(testo[i + 1]), c = valore(testo[i + 2]);
        unsigned int v;

        if (a < 0 || b < 0 || c < 0) {
            return -1;
        }
        v = (unsigned int)a + (unsigned int)b * BASE + (unsigned int)c * BASE * BASE;
        if (v > 0xFFFFu) {
            return -1;
        }
        out[scritti++] = (unsigned char)(v / 256u);
        out[scritti++] = (unsigned char)(v % 256u);
    }
    if (i < n) {
        int a = valore(testo[i]), b = valore(testo[i + 1]);
        unsigned int v;

        if (a < 0 || b < 0) {
            return -1;
        }
        v = (unsigned int)a + (unsigned int)b * BASE;
        if (v > 0xFFu) {
            return -1;
        }
        out[scritti++] = (unsigned char)v;
    }
    return (long)scritti;
}

/* ------------------------------------------------- carte come byte -------- */

/* Una cifra esadecimale come numero. Fuori dall'alfabeto vale 0: il colore
 * arriva da opencard_card_color(), che lo scrive sempre bene, e uno zero
 * sbagliato darebbe una tinta storta, non una carta persa. */
static unsigned int mezzo_byte(char c)
{
    if (c >= '0' && c <= '9') {
        return (unsigned int)(c - '0');
    }
    if (c >= 'a' && c <= 'f') {
        return (unsigned int)(c - 'a' + 10);
    }
    if (c >= 'A' && c <= 'F') {
        return (unsigned int)(c - 'A' + 10);
    }
    return 0;
}

/* Quanto occupa una carta nel formato compatto, nel caso peggiore. */
static size_t misura_carta(const opencard_card *card)
{
    return 1 + 1 + strlen(card->label) + 1 + strlen(card->code) + 3;
}

static int solo_cifre(const char *s)
{
    size_t i;

    if (*s == '\0') {
        return 0;
    }
    for (i = 0; s[i] != '\0'; i++) {
        if (s[i] < '0' || s[i] > '9') {
            return 0;
        }
    }
    return 1;
}

/* Scrive le carte nel formato compatto. Ritorna i byte scritti, -1 se non ci
 * stanno. */
static long scrivi_carte(const opencard_lista *lista, unsigned char *out, size_t out_size)
{
    size_t scritti = 0, i;

    if (out_size < 4) {
        return -1;
    }
    out[scritti++] = 'O';
    out[scritti++] = 'C';
    out[scritti++] = OPENCARD_TRASF_FORMATO;
    out[scritti++] = (unsigned char)lista->n;

    for (i = 0; i < lista->n; i++) {
        const opencard_card *card = &lista->carte[i];
        char colore[OPENCARD_COLOR_MAX];
        size_t etichetta = strlen(card->label);
        size_t codice = strlen(card->code);
        int cifre = solo_cifre(card->code);
        unsigned char flag;
        size_t j;

        if (scritti + misura_carta(card) > out_size) {
            return -1;
        }
        if (etichetta > 255 || codice > 255) {
            return -1;
        }

        /* Il colore viaggia sempre, anche quando l'ha deciso l'id: chi riceve
         * assegna id nuovi, e senza il colore dentro il QR le carte
         * cambierebbero tinta arrivando. Si riconoscono a colpo d'occhio dal
         * colore, quindi vale i tre byte. */
        opencard_card_color(card, colore, sizeof(colore));

        flag = (unsigned char)((card->is_qrcode ? FLAG_QRCODE : 0)
                               | (card->disposable ? FLAG_USA_GETTA : 0)
                               | FLAG_COLORE
                               | (cifre ? FLAG_CIFRE : 0)
                               | (card->favorite ? FLAG_PREFERITA : 0));
        out[scritti++] = flag;

        out[scritti++] = (unsigned char)etichetta;
        memcpy(out + scritti, card->label, etichetta);
        scritti += etichetta;

        out[scritti++] = (unsigned char)codice;
        if (cifre) {
            /* Mezzo byte per cifra: un codice EAN-13 passa da 13 byte a 7. */
            for (j = 0; j < codice; j += 2) {
                unsigned char alto = (unsigned char)(card->code[j] - '0');
                unsigned char basso = (j + 1 < codice)
                                      ? (unsigned char)(card->code[j + 1] - '0') : 0;
                out[scritti++] = (unsigned char)((alto << 4) | basso);
            }
        } else {
            memcpy(out + scritti, card->code, codice);
            scritti += codice;
        }

        /* "#RRGGBB" senza il cancelletto, tre byte. */
        for (j = 0; j < 3; j++) {
            out[scritti++] = (unsigned char)((mezzo_byte(colore[1 + j * 2]) << 4)
                                             | mezzo_byte(colore[2 + j * 2]));
        }
    }
    return (long)scritti;
}

static int cifra_esadecimale(unsigned char b, char *out)
{
    static const char cifre[] = "0123456789ABCDEF";

    out[0] = cifre[(b >> 4) & 0x0F];
    out[1] = cifre[b & 0x0F];
    return 2;
}

static opencard_esito leggi_carte(const unsigned char *dati, size_t n,
                                  opencard_lista *out, opencard_errore *errore)
{
    size_t posizione = 0;
    unsigned int quante, i;

    memset(out, 0, sizeof(*out));

    if (n < 4 || dati[0] != 'O' || dati[1] != 'C') {
        return segnala(errore, OPENCARD_ERR_TRASF_ROTTO);
    }
    if (dati[2] > OPENCARD_TRASF_FORMATO) {
        segnala(errore, OPENCARD_ERR_TRASF_VERSIONE);
        if (errore != NULL) {
            errore->schema_trovato = dati[2];
        }
        return OPENCARD_ERR_TRASF_VERSIONE;
    }
    quante = dati[3];
    posizione = 4;

    out->carte = (opencard_card *)calloc(quante > 0 ? quante : 1,
                                         sizeof(opencard_card));
    if (out->carte == NULL) {
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    out->capacita = quante > 0 ? quante : 1;

    for (i = 0; i < quante; i++) {
        opencard_card *card = &out->carte[i];
        unsigned char flag;
        size_t etichetta, codice, byte_codice, j;

        if (posizione + 3 > n) {
            goto rotto;
        }
        flag = dati[posizione++];

        etichetta = dati[posizione++];
        if (posizione + etichetta + 1 > n || etichetta >= OPENCARD_LABEL_MAX) {
            goto rotto;
        }
        memcpy(card->label, dati + posizione, etichetta);
        card->label[etichetta] = '\0';
        /* I byte arrivano dall'altro telefono: quello che non è UTF-8 valido
         * si ripara subito, prima che tocchi i ponti verso Java e NSString. */
        opencard_utf8_ripara(card->label);
        posizione += etichetta;

        codice = dati[posizione++];
        byte_codice = (flag & FLAG_CIFRE) ? (codice + 1) / 2 : codice;
        if (posizione + byte_codice > n || codice >= OPENCARD_CODE_MAX) {
            goto rotto;
        }
        if (flag & FLAG_CIFRE) {
            for (j = 0; j < codice; j++) {
                unsigned char b = dati[posizione + j / 2];
                unsigned char mezzo = (j % 2 == 0) ? (unsigned char)(b >> 4)
                                                   : (unsigned char)(b & 0x0F);
                if (mezzo > 9) {
                    goto rotto;
                }
                card->code[j] = (char)('0' + mezzo);
            }
            card->code[codice] = '\0';
        } else {
            memcpy(card->code, dati + posizione, codice);
            card->code[codice] = '\0';
            opencard_utf8_ripara(card->code);
        }
        posizione += byte_codice;

        card->is_qrcode = (flag & FLAG_QRCODE) ? 1 : 0;
        card->disposable = (flag & FLAG_USA_GETTA) ? 1 : 0;
        /* Un bit che una versione precedente non conosce lo ignora e basta:
         * la carta arriva senza stella invece di non arrivare. Per questo il
         * numero di formato resta 1. */
        card->favorite = (flag & FLAG_PREFERITA) ? 1 : 0;
        card->id = 0;   /* lo assegna chi riceve */

        if (flag & FLAG_COLORE) {
            if (posizione + 3 > n) {
                goto rotto;
            }
            card->color[0] = '#';
            for (j = 0; j < 3; j++) {
                cifra_esadecimale(dati[posizione + j], card->color + 1 + j * 2);
            }
            card->color[7] = '\0';
            posizione += 3;
        } else {
            card->color[0] = '\0';
        }
        out->n++;
    }
    pulisci_errore(errore);
    return OPENCARD_OK;

rotto:
    opencard_lista_free(out);
    memset(out, 0, sizeof(*out));
    return segnala(errore, OPENCARD_ERR_TRASF_ROTTO);
}

/* --------------------------------------------------------- i pezzi -------- */

void opencard_trasf_pezzi_free(opencard_trasf_pezzi *pezzi)
{
    size_t i;

    if (pezzi == NULL || pezzi->pezzi == NULL) {
        return;
    }
    for (i = 0; i < pezzi->n; i++) {
        free(pezzi->pezzi[i]);
    }
    free(pezzi->pezzi);
    pezzi->pezzi = NULL;
    pezzi->n = 0;
}

opencard_esito opencard_trasf_prepara_lista(const opencard_lista *lista,
                                            opencard_trasf_pezzi *out,
                                            opencard_errore *errore)
{
    unsigned char *piano = NULL, *compresso = NULL, *blocco = NULL;
    uLongf compresso_max;
    size_t piano_max = 8, i, blocco_n, quanti, fetta_dati;
    long scritti;
    unsigned long crc;
    opencard_esito esito = OPENCARD_OK;

    if (lista == NULL || out == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    memset(out, 0, sizeof(*out));
    if (lista->n > OPENCARD_TRASF_CARTE_MAX) {
        return segnala(errore, OPENCARD_ERR_TRASF_TROPPE);
    }

    for (i = 0; i < lista->n; i++) {
        piano_max += misura_carta(&lista->carte[i]);
    }
    piano = (unsigned char *)malloc(piano_max);
    if (piano == NULL) {
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    scritti = scrivi_carte(lista, piano, piano_max);
    if (scritti < 0) {
        free(piano);
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }

    /* Quattro byte di lunghezza scompressa davanti al compresso: chi riceve
     * deve sapere quanto spazio serve prima di aprire il pacchetto. */
    compresso_max = compressBound((uLong)scritti);
    blocco = (unsigned char *)malloc(4 + compresso_max);
    if (blocco == NULL) {
        free(piano);
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    compresso = blocco + 4;
    if (compress2(compresso, &compresso_max, piano, (uLong)scritti, 9) != Z_OK) {
        free(piano);
        free(blocco);
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    free(piano);

    blocco[0] = (unsigned char)(scritti & 0xFF);
    blocco[1] = (unsigned char)((scritti >> 8) & 0xFF);
    blocco[2] = (unsigned char)((scritti >> 16) & 0xFF);
    blocco[3] = (unsigned char)((scritti >> 24) & 0xFF);
    blocco_n = 4 + (size_t)compresso_max;

    crc = crc32(0L, blocco, (uInt)blocco_n);

    fetta_dati = FETTA_MAX - INTESTAZIONE;
    quanti = (blocco_n + fetta_dati - 1) / fetta_dati;
    if (quanti == 0) {
        quanti = 1;
    }
    if (quanti > OPENCARD_TRASF_PEZZI_MAX) {
        free(blocco);
        return segnala(errore, OPENCARD_ERR_TRASF_TROPPE);
    }

    out->pezzi = (char **)calloc(quanti, sizeof(char *));
    if (out->pezzi == NULL) {
        free(blocco);
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }

    for (i = 0; i < quanti; i++) {
        unsigned char fetta[FETTA_MAX];
        size_t da = i * fetta_dati;
        size_t quanti_byte = blocco_n - da < fetta_dati ? blocco_n - da : fetta_dati;
        char *testo;

        fetta[0] = 'O';
        fetta[1] = 'C';
        fetta[2] = OPENCARD_TRASF_FORMATO;
        fetta[3] = (unsigned char)i;
        fetta[4] = (unsigned char)quanti;
        fetta[5] = (unsigned char)(crc & 0xFF);
        fetta[6] = (unsigned char)((crc >> 8) & 0xFF);
        fetta[7] = (unsigned char)((crc >> 16) & 0xFF);
        fetta[8] = (unsigned char)((crc >> 24) & 0xFF);
        memcpy(fetta + INTESTAZIONE, blocco + da, quanti_byte);

        testo = (char *)malloc((INTESTAZIONE + quanti_byte + 1) / 2 * 3 + 1);
        if (testo == NULL) {
            esito = segnala(errore, OPENCARD_ERR_MEMORIA);
            break;
        }
        if (opencard_base44_codifica(fetta, INTESTAZIONE + quanti_byte, testo,
                                     (INTESTAZIONE + quanti_byte + 1) / 2 * 3 + 1) < 0) {
            free(testo);
            esito = segnala(errore, OPENCARD_ERR_MEMORIA);
            break;
        }
        out->pezzi[i] = testo;
        out->n++;
    }
    free(blocco);

    if (esito != OPENCARD_OK) {
        opencard_trasf_pezzi_free(out);
        return esito;
    }
    pulisci_errore(errore);
    return OPENCARD_OK;
}

opencard_esito opencard_trasf_prepara(opencard_trasf_pezzi *out,
                                      opencard_errore *errore)
{
    opencard_lista tutte;
    opencard_esito esito;

    esito = opencard_get_all(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    esito = opencard_trasf_prepara_lista(&tutte, out, errore);
    opencard_lista_free(&tutte);
    return esito;
}

/* ------------------------------------------------------- la raccolta ------ */

/* I pezzi letti, rimessi in fila. `dati` è NULL finché non arriva il primo
 * pezzo buono, perché solo lui dice quanti sono. */
typedef struct {
    int totale;
    unsigned long crc;
    unsigned char *dati;
    size_t *lunghezze;
    unsigned char *presenti;
    int ricevuti;
} raccolta;

static void raccolta_free(raccolta *r)
{
    free(r->dati);
    free(r->lunghezze);
    free(r->presenti);
    memset(r, 0, sizeof(*r));
}

/* Mette insieme i pezzi letti. I testi che non sono di OpenCard si saltano in
 * silenzio: la fotocamera inquadra di tutto, e un codice a barre di un
 * pacchetto di biscotti non è un errore da mostrare. */
static opencard_esito raccogli(const char *const *letti, size_t n,
                               raccolta *r, opencard_errore *errore)
{
    size_t i;
    size_t fetta_dati = FETTA_MAX - INTESTAZIONE;

    memset(r, 0, sizeof(*r));

    for (i = 0; i < n; i++) {
        unsigned char fetta[FETTA_MAX + 8];
        long byte;
        int indice, totale;
        unsigned long crc;
        size_t utili;

        if (letti[i] == NULL) {
            continue;
        }
        byte = opencard_base44_decodifica(letti[i], 0, fetta, sizeof(fetta));
        if (byte < INTESTAZIONE || fetta[0] != 'O' || fetta[1] != 'C') {
            continue;
        }
        if (fetta[2] > OPENCARD_TRASF_FORMATO) {
            raccolta_free(r);
            segnala(errore, OPENCARD_ERR_TRASF_VERSIONE);
            if (errore != NULL) {
                errore->schema_trovato = fetta[2];
            }
            return OPENCARD_ERR_TRASF_VERSIONE;
        }
        indice = fetta[3];
        totale = fetta[4];
        crc = (unsigned long)fetta[5] | ((unsigned long)fetta[6] << 8)
              | ((unsigned long)fetta[7] << 16) | ((unsigned long)fetta[8] << 24);
        utili = (size_t)byte - INTESTAZIONE;

        if (totale <= 0 || indice >= totale || utili > fetta_dati) {
            continue;
        }

        if (r->dati == NULL) {
            r->totale = totale;
            r->crc = crc;
            r->dati = (unsigned char *)malloc((size_t)totale * fetta_dati);
            r->lunghezze = (size_t *)calloc((size_t)totale, sizeof(size_t));
            r->presenti = (unsigned char *)calloc((size_t)totale, 1);
            if (r->dati == NULL || r->lunghezze == NULL || r->presenti == NULL) {
                raccolta_free(r);
                return segnala(errore, OPENCARD_ERR_MEMORIA);
            }
        } else if (r->crc != crc || r->totale != totale) {
            /* Pezzo di un altro passaggio: dirlo, altrimenti chi riceve
             * aspetta all'infinito un codice che non arriverà mai. */
            raccolta_free(r);
            return segnala(errore, OPENCARD_ERR_ALTRO_TRASF);
        }

        if (!r->presenti[indice]) {
            r->presenti[indice] = 1;
            r->ricevuti++;
        }
        memcpy(r->dati + (size_t)indice * fetta_dati, fetta + INTESTAZIONE, utili);
        r->lunghezze[indice] = utili;
    }
    pulisci_errore(errore);
    return OPENCARD_OK;
}

/* Rimette in fila i pezzi e apre il pacchetto. */
static opencard_esito componi_blocco(const raccolta *r, unsigned char **out,
                                     size_t *out_n, opencard_errore *errore)
{
    size_t fetta_dati = FETTA_MAX - INTESTAZIONE;
    unsigned char *blocco;
    size_t totale_byte = 0, posizione = 0;
    unsigned long lunghezza_piana;
    unsigned char *piano;
    uLongf piano_n;
    int i;

    for (i = 0; i < r->totale; i++) {
        totale_byte += r->lunghezze[i];
    }
    blocco = (unsigned char *)malloc(totale_byte > 0 ? totale_byte : 1);
    if (blocco == NULL) {
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    for (i = 0; i < r->totale; i++) {
        memcpy(blocco + posizione, r->dati + (size_t)i * fetta_dati, r->lunghezze[i]);
        posizione += r->lunghezze[i];
    }

    if (crc32(0L, blocco, (uInt)totale_byte) != r->crc || totale_byte < 5) {
        free(blocco);
        return segnala(errore, OPENCARD_ERR_TRASF_ROTTO);
    }

    lunghezza_piana = (unsigned long)blocco[0] | ((unsigned long)blocco[1] << 8)
                      | ((unsigned long)blocco[2] << 16)
                      | ((unsigned long)blocco[3] << 24);
    if (lunghezza_piana == 0 || lunghezza_piana > 1024u * 1024u) {
        free(blocco);
        return segnala(errore, OPENCARD_ERR_TRASF_ROTTO);
    }
    piano = (unsigned char *)malloc(lunghezza_piana);
    if (piano == NULL) {
        free(blocco);
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    piano_n = (uLongf)lunghezza_piana;
    if (uncompress(piano, &piano_n, blocco + 4, (uLong)(totale_byte - 4)) != Z_OK) {
        free(blocco);
        free(piano);
        return segnala(errore, OPENCARD_ERR_TRASF_ROTTO);
    }
    free(blocco);

    *out = piano;
    *out_n = (size_t)piano_n;
    return OPENCARD_OK;
}

opencard_esito opencard_trasf_stato(const char *const *letti, size_t n,
                                    int *ricevuti, int *totale,
                                    opencard_errore *errore)
{
    raccolta r;
    opencard_esito esito;

    if (ricevuti != NULL) {
        *ricevuti = 0;
    }
    if (totale != NULL) {
        *totale = 0;
    }
    if (letti == NULL && n > 0) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    esito = raccogli(letti, n, &r, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    if (ricevuti != NULL) {
        *ricevuti = r.ricevuti;
    }
    if (totale != NULL) {
        *totale = r.totale;
    }
    raccolta_free(&r);
    return OPENCARD_OK;
}

opencard_esito opencard_trasf_leggi(const char *const *letti, size_t n,
                                    opencard_lista *out, opencard_errore *errore)
{
    raccolta r;
    unsigned char *piano = NULL;
    size_t piano_n = 0;
    opencard_esito esito;

    if (out == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    memset(out, 0, sizeof(*out));

    esito = raccogli(letti, n, &r, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    if (r.dati == NULL || r.ricevuti < r.totale) {
        raccolta_free(&r);
        return segnala(errore, OPENCARD_ERR_TRASF_INCOMPLETO);
    }
    esito = componi_blocco(&r, &piano, &piano_n, errore);
    raccolta_free(&r);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    esito = leggi_carte(piano, piano_n, out, errore);
    free(piano);
    return esito;
}

opencard_esito opencard_trasf_applica(const char *const *letti, size_t n,
                                      int azzera, int *quante,
                                      opencard_errore *errore)
{
    opencard_lista arrivate;
    opencard_esito esito;
    size_t i;

    if (quante != NULL) {
        *quante = 0;
    }
    esito = opencard_trasf_leggi(letti, n, &arrivate, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    if (azzera) {
        /* Le carte arrivano con id 0: sulla strada dell'aggiunta glielo assegna
         * opencard_append_all, qui non lo assegnava nessuno e finivano tutte
         * sullo stesso id. Aprirne una ne mostrava un'altra, codice e colore
         * della prima. Si rinumera come fa il ripristino da backup. */
        for (i = 0; i < arrivate.n; i++) {
            arrivate.carte[i].id = (int)i + 1;
        }
        esito = opencard_replace_all(&arrivate, errore);
    } else {
        esito = opencard_append_all(&arrivate, errore);
    }
    if (esito == OPENCARD_OK && quante != NULL) {
        *quante = (int)arrivate.n;
    }
    opencard_lista_free(&arrivate);
    return esito;
}
