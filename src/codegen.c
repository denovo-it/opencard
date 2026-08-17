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
        /* Da destra: il primo blocco e' il resto della divisione per tre. */
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

int opencard_render_bitmap(const char *code, opencard_tipo tipo,
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
    simbolo->symbology = opencard_symbology(code, tipo);
    simbolo->show_hrt = 0;      /* il testo lo disegna la UI, raggruppato a tre */
    simbolo->scale = 4.0f;

    esito = ZBarcode_Encode_and_Buffer(simbolo, (const unsigned char *)s, (int)n, 0);

    if (esito >= ZINT_ERROR || simbolo->bitmap == NULL) {
        if (errore != NULL && errore_len > 0) {
            strncpy(errore, simbolo->errtxt, errore_len - 1);
            errore[errore_len - 1] = '\0';
        }
        ZBarcode_Delete(simbolo);
        return esito >= ZINT_ERROR ? esito : ZINT_ERROR_ENCODING_PROBLEM;
    }

    /* Il bitmap di zint vive dentro il simbolo e muore con lui: se ne fa una
     * copia, cosi' chi chiama non deve tenersi il simbolo. */
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
    simbolo->symbology = opencard_symbology(code, tipo);
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
