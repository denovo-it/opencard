#include "codegen.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <zint.h>

static int tutto_cifre(const char *s, size_t n)
{
    size_t i;
    if (n == 0) {
        return 0;
    }
    for (i = 0; i < n; i++) {
        if (!isdigit((unsigned char)s[i])) {
            return 0;
        }
    }
    return 1;
}

static int tutto_alfanumerico(const char *s, size_t n)
{
    size_t i;
    if (n == 0) {
        return 0;
    }
    for (i = 0; i < n; i++) {
        if (!isalnum((unsigned char)s[i])) {
            return 0;
        }
    }
    return 1;
}

/* Taglia gli spazi ai due capi. */
static void estremi(const char *code, const char **inizio, size_t *lunghezza)
{
    const char *p = code;
    const char *fine;

    while (*p != '\0' && isspace((unsigned char)*p)) {
        p++;
    }
    fine = p + strlen(p);
    while (fine > p && isspace((unsigned char)fine[-1])) {
        fine--;
    }
    *inizio = p;
    *lunghezza = (size_t)(fine - p);
}

int opencard_grouped_code(const char *code, char *out, size_t out_size)
{
    const char *s;
    size_t n, scritti = 0, i;

    if (code == NULL || out == NULL || out_size == 0) {
        return -1;
    }

    estremi(code, &s, &n);

    /* Codici corti o con punteggiatura propria: si lasciano stare, spezzarli
     * darebbe solo fastidio. Si copia l'originale, spazi ai capi compresi. */
    if (n <= 4 || !tutto_alfanumerico(s, n)) {
        size_t l = strlen(code);
        if (l + 1 > out_size) {
            return -1;
        }
        memcpy(out, code, l + 1);
        return (int)l;
    }

    if (tutto_cifre(s, n)) {
        /* Da destra: il primo blocco è il resto della divisione per tre. */
        size_t testa = n % 3;
        if (testa == 0) {
            testa = 3;
        }
        for (i = 0; i < n; i++) {
            if (i == testa || (i > testa && (i - testa) % 3 == 0)) {
                if (scritti + 1 >= out_size) {
                    return -1;
                }
                out[scritti++] = ' ';
            }
            if (scritti + 1 >= out_size) {
                return -1;
            }
            out[scritti++] = s[i];
        }
    } else {
        /* Da sinistra. */
        for (i = 0; i < n; i++) {
            if (i > 0 && i % 3 == 0) {
                if (scritti + 1 >= out_size) {
                    return -1;
                }
                out[scritti++] = ' ';
            }
            if (scritti + 1 >= out_size) {
                return -1;
            }
            out[scritti++] = s[i];
        }
    }

    out[scritti] = '\0';
    return (int)scritti;
}

/* Le simbologie di OpenCard e la costante zint che le disegna. L'ordine segue
 * l'enum di store.h: una riga per valore, nessun buco.
 *
 * EAN-8 ed EAN-13 hanno la stessa costante perché zint sceglie in base a
 * quante cifre gli arrivano; tenerle separate da noi serve a far vedere in
 * elenco quello che la gente si aspetta di trovare. */
static const int ZINT_DI_SIMBOLOGIA[OPENCARD_SIM_QUANTE] = {
    BARCODE_CODE128,        /* CODE128 */
    BARCODE_QRCODE,         /* QR */
    BARCODE_AZTEC,          /* AZTEC */
    BARCODE_CODABAR,        /* CODABAR */
    BARCODE_CODE39,         /* CODE39 */
    BARCODE_CODE93,         /* CODE93 */
    BARCODE_DATAMATRIX,     /* DATAMATRIX */
    BARCODE_EANX,           /* EAN8 */
    BARCODE_EANX,           /* EAN13 */
    BARCODE_C25INTER,       /* ITF */
    BARCODE_PDF417,         /* PDF417 */
    BARCODE_UPCA,           /* UPCA */
    BARCODE_UPCE,           /* UPCE */
    BARCODE_MICROQR,        /* MICROQR */
    BARCODE_GS1_128,        /* GS1_128 */
    BARCODE_DBAR_OMN,       /* DATABAR */
    BARCODE_DBAR_EXP,       /* DATABAR_ESPANSO */
    BARCODE_MSI_PLESSEY     /* MSI */
};

int opencard_zint_da_simbologia(opencard_simbologia simbologia)
{
    if (simbologia < 0 || simbologia >= OPENCARD_SIM_QUANTE) {
        return -1;
    }
    return ZINT_DI_SIMBOLOGIA[simbologia];
}

int opencard_symbology(const char *code, opencard_tipo tipo)
{
    const char *s;
    size_t n;

    if (tipo == OPENCARD_QRCODE) {
        return BARCODE_QRCODE;
    }
    if (code == NULL) {
        return BARCODE_CODE128;
    }

    estremi(code, &s, &n);
    if (tutto_cifre(s, n)) {
        if (n == 13) {
            return BARCODE_EANX;   /* EAN-13: zint sceglie in base alle cifre */
        }
        if (n == 8) {
            return BARCODE_EANX;   /* EAN-8 */
        }
        if (n == 12) {
            return BARCODE_UPCA;
        }
    }
    return BARCODE_CODE128;
}

/* EANX conta le cifre come se mancasse sempre quella di controllo: otto cifre
 * per lui sono un EAN-13 da completare con gli zeri davanti. Ma un EAN-8 lo
 * si scrive con tutte e otto, ed è così che lo leggono i lettori dalla
 * tessera: 96385074 usciva disegnato come 0000963850742, e alla cassa era un
 * altro numero. EANX_CHK prende le otto cifre per un EAN-8 e ne verifica il
 * controllo, come EANX fa già con le tredici di un EAN-13. Con sette cifre
 * resta EANX, che il controllo lo calcola da sé. */
static int zint_per_la_lunghezza(int zint_simbologia, size_t n)
{
    if (zint_simbologia == BARCODE_EANX && n == 8) {
        return BARCODE_EANX_CHK;
    }
    return zint_simbologia;
}

/* Oltre questa larghezza l'immagine non arriva sullo schermo.
 *
 * Un codice lungo disegnato a scala 4 diventa larghissimo: cinquanta caratteri
 * in Code 128 passano i 4.600 px. Su parecchi telefoni Android il massimo di
 * una texture è 4.096 px, e sopra quel limite il sistema non disegna niente:
 * niente errore, niente immagine, solo una riga nel log. Nella schermata della
 * carta resta il vuoto, e il numero scritto sotto sale al posto del codice.
 *
 * Larghi così non servono comunque: l'immagine viene comunque ridotta alla
 * larghezza dello schermo. Quindi si abbassa la scala finché ci sta.
 *
 * 3.072 e non meno: sotto, un Code 128 vicino al suo massimo uscirebbe più
 * stretto dello schermo di un telefono grande e verrebbe ingrandito, e le
 * barre ingrandite si sfocano. Così resta sempre da rimpicciolire.
 */
#define OPENCARD_LARGHEZZA_MASSIMA 3072

/* Sotto questa scala un modulo diventa meno di un pixel e le barre si
 * impastano. La scala si abbassa a passi di mezzo perché zint disegna due
 * pixel per modulo per ogni punto di scala: così un modulo resta un numero
 * intero di pixel e le barre non si sfrangiano. */
#define OPENCARD_SCALA_MINIMA 0.5f

/* Il motore vero: la simbologia arriva già decisa, in costanti di zint. */
static int disegna(const char *code, int zint_simbologia,
                   unsigned char **pixel, int *larghezza, int *altezza,
                   char *errore, size_t errore_len)
{
    struct zint_symbol *simbolo;
    const char *s;
    size_t n, byte;
    int esito;

    if (errore != NULL && errore_len > 0) {
        errore[0] = '\0';
    }
    if (code == NULL || pixel == NULL || larghezza == NULL || altezza == NULL) {
        return ZINT_ERROR_INVALID_DATA;
    }
    *pixel = NULL;
    *larghezza = 0;
    *altezza = 0;

    simbolo = ZBarcode_Create();
    if (simbolo == NULL) {
        return ZINT_ERROR_MEMORY;
    }

    estremi(code, &s, &n);
    simbolo->symbology = zint_per_la_lunghezza(zint_simbologia, n);
    simbolo->show_hrt = 0;      /* il testo lo disegna la UI, raggruppato a tre */
    simbolo->scale = 4.0f;

    /* Codifica e disegno sono due passi apposta: fra i due `simbolo->width` dice
     * quanti moduli sono venuti fuori, che è l'unico modo di sapere quanto
     * verrebbe larga l'immagine prima di allocarla. */
    esito = ZBarcode_Encode(simbolo, (const unsigned char *)s, (int)n);
    if (esito < ZINT_ERROR) {
        while (simbolo->scale > OPENCARD_SCALA_MINIMA &&
               (float)simbolo->width * 2.0f * simbolo->scale > OPENCARD_LARGHEZZA_MASSIMA) {
            simbolo->scale -= 0.5f;
        }
        esito = ZBarcode_Buffer(simbolo, 0);
    }

    if (esito >= ZINT_ERROR || simbolo->bitmap == NULL) {
        if (errore != NULL && errore_len > 0) {
            strncpy(errore, simbolo->errtxt, errore_len - 1);
            errore[errore_len - 1] = '\0';
        }
        ZBarcode_Delete(simbolo);
        return esito >= ZINT_ERROR ? esito : ZINT_ERROR_ENCODING_PROBLEM;
    }

    /* Il bitmap di zint vive dentro il simbolo e muore con lui: se ne fa una
     * copia, così chi chiama non deve tenersi il simbolo. */
    byte = (size_t)simbolo->bitmap_width * (size_t)simbolo->bitmap_height * 3;
    *pixel = (unsigned char *)malloc(byte);
    if (*pixel == NULL) {
        ZBarcode_Delete(simbolo);
        return ZINT_ERROR_MEMORY;
    }
    memcpy(*pixel, simbolo->bitmap, byte);
    *larghezza = simbolo->bitmap_width;
    *altezza = simbolo->bitmap_height;

    ZBarcode_Delete(simbolo);
    return 0;
}

int opencard_render_bitmap(const char *code, opencard_tipo tipo,
                           unsigned char **pixel, int *larghezza, int *altezza,
                           char *errore, size_t errore_len)
{
    return disegna(code, opencard_symbology(code, tipo), pixel, larghezza, altezza,
                   errore, errore_len);
}

/* EAN e UPC vogliono un numero di cifre preciso, con o senza quella di
 * controllo, che zint calcola da sé. Il controllo sta qui e non in zint
 * perché EAN-8 ed EAN-13 per lui sono la stessa simbologia: senza, uno che
 * sceglie EAN-13 e scrive undici cifre si ritrova un codice disegnato che
 * alla cassa non è la sua tessera. */
static int lunghezza_adatta(opencard_simbologia simbologia, const char *code)
{
    const char *s;
    size_t n;

    if (simbologia != OPENCARD_SIM_EAN13 && simbologia != OPENCARD_SIM_EAN8
        && simbologia != OPENCARD_SIM_UPCA && simbologia != OPENCARD_SIM_UPCE) {
        return 1;
    }
    if (code == NULL) {
        return 0;
    }
    estremi(code, &s, &n);
    if (!tutto_cifre(s, n)) {
        return 0;
    }
    switch (simbologia) {
    case OPENCARD_SIM_EAN13:
        return n == 12 || n == 13;
    case OPENCARD_SIM_EAN8:
        return n == 7 || n == 8;
    case OPENCARD_SIM_UPCA:
        return n == 11 || n == 12;
    case OPENCARD_SIM_UPCE:
        return n >= 6 && n <= 8;
    default:
        return 1;
    }
}

int opencard_codice_sta(const char *code, opencard_simbologia simbologia)
{
    struct zint_symbol *simbolo;
    const char *s;
    size_t n;
    int zint_simbologia = opencard_zint_da_simbologia(simbologia);
    int esito;

    if (zint_simbologia < 0 || code == NULL) {
        return 0;
    }
    if (!lunghezza_adatta(simbologia, code)) {
        return 0;
    }
    estremi(code, &s, &n);
    if (n == 0) {
        return 0;
    }
    simbolo = ZBarcode_Create();
    if (simbolo == NULL) {
        return 0;
    }
    simbolo->symbology = zint_per_la_lunghezza(zint_simbologia, n);
    /* Solo la codifica, niente disegno: qui interessa la risposta sì o no, e
     * l'immagine costa memoria che poi si butterebbe. */
    esito = ZBarcode_Encode(simbolo, (const unsigned char *)s, (int)n);
    ZBarcode_Delete(simbolo);
    return esito < ZINT_ERROR;
}

int opencard_render_bitmap_simbologia(const char *code, opencard_simbologia simbologia,
                                      unsigned char **pixel, int *larghezza,
                                      int *altezza, char *errore, size_t errore_len)
{
    int zint_simbologia = opencard_zint_da_simbologia(simbologia);

    if (zint_simbologia >= 0 && !lunghezza_adatta(simbologia, code)) {
        if (errore != NULL && errore_len > 0) {
            strncpy(errore, "il numero di cifre non va bene per questa simbologia",
                    errore_len - 1);
            errore[errore_len - 1] = '\0';
        }
        return ZINT_ERROR_INVALID_DATA;
    }
    if (zint_simbologia < 0) {
        if (errore != NULL && errore_len > 0) {
            errore[0] = '\0';
        }
        return ZINT_ERROR_INVALID_OPTION;
    }
    return disegna(code, zint_simbologia, pixel, larghezza, altezza, errore, errore_len);
}

void opencard_free_bitmap(unsigned char *pixel)
{
    free(pixel);
}

int opencard_write_png(const char *code, opencard_tipo tipo, const char *percorso,
                       char *errore, size_t errore_len)
{
    struct zint_symbol *simbolo;
    const char *s;
    size_t n;
    int esito;

    if (errore != NULL && errore_len > 0) {
        errore[0] = '\0';
    }
    if (code == NULL || percorso == NULL) {
        return ZINT_ERROR_INVALID_DATA;
    }

    simbolo = ZBarcode_Create();
    if (simbolo == NULL) {
        return ZINT_ERROR_MEMORY;
    }

    estremi(code, &s, &n);
    simbolo->symbology = zint_per_la_lunghezza(opencard_symbology(code, tipo), n);
    simbolo->show_hrt = 0;      /* il testo lo disegna la UI, raggruppato a tre */
    simbolo->scale = 4.0f;
    strncpy(simbolo->outfile, percorso, sizeof(simbolo->outfile) - 1);
    simbolo->outfile[sizeof(simbolo->outfile) - 1] = '\0';

    esito = ZBarcode_Encode_and_Print(simbolo, (const unsigned char *)s, (int)n, 0);

    if (esito >= ZINT_ERROR && errore != NULL && errore_len > 0) {
        strncpy(errore, simbolo->errtxt, errore_len - 1);
        errore[errore_len - 1] = '\0';
    }

    ZBarcode_Delete(simbolo);
    return esito >= ZINT_ERROR ? esito : 0;
}
