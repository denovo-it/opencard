/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

#include "store.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "third-party/cJSON.h"

/* Colori vivaci ma non troppo saturi, adatti a testo bianco sopra. */
static const char *const COLORI[] = {
    "#E53935",  /* rosso */
    "#8E24AA",  /* viola */
    "#1E88E5",  /* blu */
    "#00897B",  /* teal */
    "#43A047",  /* verde */
    "#FB8C00",  /* arancione */
    "#6D4C41",  /* marrone */
    "#039BE5",  /* celeste */
    "#D81B60",  /* rosa scuro */
    "#3949AB",  /* indaco */
    "#00ACC1",  /* ciano */
    "#7CB342"   /* verde chiaro */
};
#define N_COLORI ((int)(sizeof(COLORI) / sizeof(COLORI[0])))

static char percorso_dati[1024];
static char percorso_flag[1024];

static void azzera_errore(opencard_errore *errore)
{
    if (errore != NULL) {
        errore->codice = OPENCARD_OK;
        errore->posizione = 0;
        errore->dettaglio[0] = '\0';
        errore->schema_trovato = 0;
    }
}

static opencard_esito segnala(opencard_errore *errore, opencard_esito codice)
{
    if (errore != NULL) {
        errore->codice = codice;
    }
    return codice;
}

static void copia(char *dest, size_t dest_size, const char *sorgente)
{
    size_t n;

    if (sorgente == NULL) {
        dest[0] = '\0';
        return;
    }
    n = strlen(sorgente);
    if (n >= dest_size) {
        /* Non si taglia a metà un carattere multibyte: si torna indietro fino
         * al suo primo byte e si taglia lì. Un pezzo di carattere non è UTF-8
         * valido e i ponti verso Java e NSString non lo digeriscono. */
        n = dest_size - 1;
        /* Il byte in posizione n è il primo che non entra. Se è un byte di
         * coda, il carattere a cui appartiene resta spezzato: si arretra fino
         * al suo byte di testa e si taglia lì, testa compresa. */
        while (n > 0 && ((unsigned char)sorgente[n] & 0xC0) == 0x80) {
            n--;
        }
    }
    memcpy(dest, sorgente, n);
    dest[n] = '\0';
}

/* Un double dal JSON come int, senza comportamento indefinito: fuori dai
 * limiti (o NaN) vale 0, che per gli id significa "da rinumerare". */
static int intero_da(double v)
{
    if (!(v >= -2147483647.0 && v <= 2147483647.0)) {
        return 0;
    }
    return (int)v;
}

void opencard_utf8_ripara(char *s)
{
    unsigned char *src = (unsigned char *)s;
    unsigned char *dst = (unsigned char *)s;

    while (*src != '\0') {
        unsigned char testa = src[0];
        unsigned int cp = 0;
        int lunghezza, i, buono = 1;

        if (testa < 0x80) {
            *dst++ = *src++;
            continue;
        }
        if ((testa & 0xE0) == 0xC0) {
            lunghezza = 2;
            cp = testa & 0x1Fu;
        } else if ((testa & 0xF0) == 0xE0) {
            lunghezza = 3;
            cp = testa & 0x0Fu;
        } else if ((testa & 0xF8) == 0xF0) {
            lunghezza = 4;
            cp = testa & 0x07u;
        } else {
            *dst++ = '?';
            src++;
            continue;
        }
        for (i = 1; i < lunghezza; i++) {
            if ((src[i] & 0xC0) != 0x80) {
                buono = 0;
                break;
            }
            cp = (cp << 6) | (src[i] & 0x3Fu);
        }
        if (!buono) {
            if (src[i] == '\0') {
                break;      /* sequenza tagliata in fondo: si toglie */
            }
            *dst++ = '?';
            src++;
            continue;
        }
        /* Sequenze più lunghe del necessario e fuori dal piano Unicode. */
        if ((lunghezza == 2 && cp < 0x80) || (lunghezza == 3 && cp < 0x800) ||
            (lunghezza == 4 && (cp < 0x10000 || cp > 0x10FFFF))) {
            *dst++ = '?';
            src++;
            continue;
        }
        if (cp >= 0xD800 && cp <= 0xDFFF) {
            /* Un surrogato da solo non è un carattere. In coppia è il
             * modified UTF-8 di Java, sei byte per un'emoji: si ricodifica in
             * UTF-8 vero da quattro, che è quello che leggono tutti. */
            unsigned int basso = 0;
            if (cp <= 0xDBFF && (src[3] & 0xF0) == 0xE0 &&
                (src[4] & 0xC0) == 0x80 && (src[5] & 0xC0) == 0x80) {
                basso = ((src[3] & 0x0Fu) << 12) | ((src[4] & 0x3Fu) << 6)
                        | (src[5] & 0x3Fu);
            }
            if (basso >= 0xDC00 && basso <= 0xDFFF) {
                unsigned int intero = 0x10000u + ((cp - 0xD800u) << 10)
                                      + (basso - 0xDC00u);
                *dst++ = (unsigned char)(0xF0 | (intero >> 18));
                *dst++ = (unsigned char)(0x80 | ((intero >> 12) & 0x3F));
                *dst++ = (unsigned char)(0x80 | ((intero >> 6) & 0x3F));
                *dst++ = (unsigned char)(0x80 | (intero & 0x3F));
                src += 6;
                continue;
            }
            *dst++ = '?';
            src++;
            continue;
        }
        for (i = 0; i < lunghezza; i++) {
            *dst++ = *src++;
        }
    }
    *dst = '\0';
}

void opencard_color_for_id(int id, char *out, size_t out_size)
{
    int indice;

    if (out == NULL || out_size == 0) {
        return;
    }
    /* Il modulo in C tiene il segno del dividendo: un id negativo darebbe un
     * indice negativo e leggeremmo fuori dall'array. */
    indice = id % N_COLORI;
    if (indice < 0) {
        indice += N_COLORI;
    }
    copia(out, out_size, COLORI[indice]);
}

void opencard_card_color(const opencard_card *card, char *out, size_t out_size)
{
    if (card == NULL || out == NULL || out_size == 0) {
        return;
    }
    if (card->color[0] != '\0') {
        copia(out, out_size, card->color);
        return;
    }
    opencard_color_for_id(card->id, out, out_size);
}

opencard_esito opencard_store_init(const char *directory_dati)
{
    if (directory_dati == NULL || directory_dati[0] == '\0') {
        return OPENCARD_ERR_ARGOMENTI;
    }
    if (snprintf(percorso_dati, sizeof(percorso_dati), "%s/opencard.json",
                 directory_dati) >= (int)sizeof(percorso_dati)) {
        return OPENCARD_ERR_ARGOMENTI;
    }
    if (snprintf(percorso_flag, sizeof(percorso_flag), "%s/.splash_shown",
                 directory_dati) >= (int)sizeof(percorso_flag)) {
        return OPENCARD_ERR_ARGOMENTI;
    }
    return OPENCARD_OK;
}

const char *opencard_store_percorso(void)
{
    return percorso_dati;
}

int opencard_is_first_run(void)
{
    return access(percorso_flag, F_OK) != 0;
}

void opencard_mark_first_run_done(void)
{
    FILE *f = fopen(percorso_flag, "w");
    if (f != NULL) {
        fputc('1', f);
        fclose(f);
    }
    /* Se non si scrive pazienza: si rivede lo splash, non si perde niente. */
}

void opencard_lista_free(opencard_lista *lista)
{
    if (lista == NULL) {
        return;
    }
    free(lista->carte);
    lista->carte = NULL;
    lista->n = 0;
    lista->capacita = 0;
}

static int lista_spazio(opencard_lista *lista, size_t servono)
{
    opencard_card *nuovo;
    size_t capacita = lista->capacita;

    if (capacita >= servono) {
        return 1;
    }
    capacita = capacita == 0 ? 8 : capacita;
    while (capacita < servono) {
        capacita *= 2;
    }
    nuovo = (opencard_card *)realloc(lista->carte, capacita * sizeof(opencard_card));
    if (nuovo == NULL) {
        return 0;
    }
    lista->carte = nuovo;
    lista->capacita = capacita;
    return 1;
}

static int lista_aggiungi(opencard_lista *lista, const opencard_card *card)
{
    if (!lista_spazio(lista, lista->n + 1)) {
        return 0;
    }
    lista->carte[lista->n++] = *card;
    return 1;
}

/* Legge il file e ne restituisce il JSON. NULL con errore valorizzato se il
 * file c'è ma non si legge: non si parte da vuoto, altrimenti la scrittura
 * successiva sovrascriverebbe le carte dell'utente. */
static cJSON *leggi_file(int *mancante, opencard_errore *errore)
{
    FILE *f;
    long dimensione;
    char *testo;
    cJSON *radice;
    size_t letti;

    *mancante = 0;

    f = fopen(percorso_dati, "rb");
    if (f == NULL) {
        *mancante = 1;
        return NULL;
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        segnala(errore, OPENCARD_ERR_IO);
        return NULL;
    }
    dimensione = ftell(f);
    if (dimensione < 0) {
        fclose(f);
        segnala(errore, OPENCARD_ERR_IO);
        return NULL;
    }
    rewind(f);

    testo = (char *)malloc((size_t)dimensione + 1);
    if (testo == NULL) {
        fclose(f);
        segnala(errore, OPENCARD_ERR_MEMORIA);
        return NULL;
    }
    letti = fread(testo, 1, (size_t)dimensione, f);
    fclose(f);
    testo[letti] = '\0';

    radice = cJSON_Parse(testo);
    free(testo);
    if (radice == NULL) {
        segnala(errore, OPENCARD_ERR_JSON);
        return NULL;
    }
    return radice;
}

/* Una carta dal suo oggetto JSON. `posizione` serve solo ai messaggi. */
static opencard_esito carta_da_json(const cJSON *nodo, int posizione,
                                    opencard_card *out, opencard_errore *errore)
{
    const cJSON *label = cJSON_GetObjectItemCaseSensitive(nodo, "label");
    const cJSON *code = cJSON_GetObjectItemCaseSensitive(nodo, "code");
    const cJSON *tipo = cJSON_GetObjectItemCaseSensitive(nodo, "type");
    const cJSON *id = cJSON_GetObjectItemCaseSensitive(nodo, "id");
    const cJSON *color = cJSON_GetObjectItemCaseSensitive(nodo, "color");
    const cJSON *disposable = cJSON_GetObjectItemCaseSensitive(nodo, "disposable");
    const cJSON *favorite = cJSON_GetObjectItemCaseSensitive(nodo, "favorite");

    memset(out, 0, sizeof(*out));

    if (errore != NULL) {
        errore->posizione = posizione;
        errore->dettaglio[0] = '\0';
    }

    if (!cJSON_IsObject(nodo)) {
        return segnala(errore, OPENCARD_ERR_CARTA);
    }
    if (!cJSON_IsString(label) || label->valuestring == NULL ||
        label->valuestring[0] == '\0') {
        return segnala(errore, OPENCARD_ERR_CARTA);
    }
    /* Da qui in poi il nome c'è: finisce nei messaggi per far capire di quale
     * carta si parla. */
    if (errore != NULL) {
        copia(errore->dettaglio, sizeof(errore->dettaglio), label->valuestring);
        opencard_utf8_ripara(errore->dettaglio);
    }
    if (!cJSON_IsString(code) || code->valuestring == NULL ||
        code->valuestring[0] == '\0') {
        return segnala(errore, OPENCARD_ERR_CARTA);
    }
    if (!cJSON_IsString(tipo) || tipo->valuestring == NULL) {
        return segnala(errore, OPENCARD_ERR_CARTA);
    }
    if (strcmp(tipo->valuestring, "qrcode") == 0) {
        out->is_qrcode = 1;
    } else if (strcmp(tipo->valuestring, "barcode") == 0) {
        out->is_qrcode = 0;
    } else {
        return segnala(errore, OPENCARD_ERR_CARTA);
    }
    if (color != NULL && !cJSON_IsNull(color) && !cJSON_IsString(color)) {
        return segnala(errore, OPENCARD_ERR_CARTA);
    }

    out->id = cJSON_IsNumber(id) ? intero_da(id->valuedouble) : 0;
    copia(out->label, sizeof(out->label), label->valuestring);
    copia(out->code, sizeof(out->code), code->valuestring);
    if (cJSON_IsString(color) && color->valuestring != NULL) {
        copia(out->color, sizeof(out->color), color->valuestring);
    }
    /* Il file arriva anche da fuori (backup, vecchie versioni Android che
     * scrivevano il modified UTF-8 di Java): quello che non è UTF-8 valido
     * si ripara qui, prima che arrivi ai ponti verso Java e NSString. */
    opencard_utf8_ripara(out->label);
    opencard_utf8_ripara(out->code);
    opencard_utf8_ripara(out->color);
    out->disposable = cJSON_IsTrue(disposable) ? 1 : 0;
    /* Campo assente vuol dire "non preferita": è così che i file scritti
     * dalle versioni precedenti restano validi senza convertire niente. */
    out->favorite = cJSON_IsTrue(favorite) ? 1 : 0;

    if (errore != NULL) {
        errore->posizione = 0;
        errore->dettaglio[0] = '\0';
    }
    return OPENCARD_OK;
}

/* Le carte dentro un oggetto JSON che ha il campo "cards". Usata sia dal file
 * dei dati sia dai backup, che hanno lo stesso formato. */
opencard_esito opencard_carte_da_json(const void *radice_json, int controlla_schema,
                                      opencard_lista *out, opencard_errore *errore)
{
    const cJSON *radice = (const cJSON *)radice_json;
    const cJSON *cards, *nodo;
    const cJSON *schema;
    int posizione = 0;

    if (out == NULL || radice == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    out->carte = NULL;
    out->n = 0;
    out->capacita = 0;

    if (!cJSON_IsObject(radice)) {
        return segnala(errore, OPENCARD_ERR_FORMATO);
    }
    cards = cJSON_GetObjectItemCaseSensitive(radice, "cards");
    if (!cJSON_IsArray(cards)) {
        return segnala(errore, OPENCARD_ERR_FORMATO);
    }
    if (controlla_schema) {
        schema = cJSON_GetObjectItemCaseSensitive(radice, "schema");
        if (!cJSON_IsNumber(schema) || intero_da(schema->valuedouble) != OPENCARD_SCHEMA_VERSION) {
            if (errore != NULL) {
                errore->schema_trovato = cJSON_IsNumber(schema) ? intero_da(schema->valuedouble) : 0;
            }
            return segnala(errore, OPENCARD_ERR_SCHEMA);
        }
    }

    cJSON_ArrayForEach(nodo, cards) {
        opencard_card card;
        opencard_esito esito;

        posizione++;
        esito = carta_da_json(nodo, posizione, &card, errore);
        if (esito != OPENCARD_OK) {
            opencard_lista_free(out);
            return esito;
        }
        if (!lista_aggiungi(out, &card)) {
            opencard_lista_free(out);
            return segnala(errore, OPENCARD_ERR_MEMORIA);
        }
    }
    return OPENCARD_OK;
}

/* Il JSON di una lista di carte. `intestazione_backup` aggiunge i campi che
 * fanno riconoscere un backup a colpo d'occhio quando lo si apre. */
void *opencard_carte_a_json(const opencard_lista *lista, const char *esportato_il)
{
    cJSON *radice = cJSON_CreateObject();
    cJSON *cards;
    size_t i;

    if (radice == NULL) {
        return NULL;
    }
    /* Ogni aggiunta si controlla: una che fallisce a memoria esaurita
     * lascerebbe un file senza un campo, che al giro dopo non si legge più.
     * Meglio non scrivere niente che scrivere un file monco. */
    if (esportato_il != NULL &&
        cJSON_AddStringToObject(radice, "app", "OpenCard") == NULL) {
        goto fallito;
    }
    if (cJSON_AddNumberToObject(radice, "schema", OPENCARD_SCHEMA_VERSION) == NULL) {
        goto fallito;
    }
    if (esportato_il != NULL &&
        cJSON_AddStringToObject(radice, "exported_at", esportato_il) == NULL) {
        goto fallito;
    }
    cards = cJSON_AddArrayToObject(radice, "cards");
    if (cards == NULL) {
        goto fallito;
    }

    for (i = 0; lista != NULL && i < lista->n; i++) {
        const opencard_card *card = &lista->carte[i];
        char colore_id[OPENCARD_COLOR_MAX];
        cJSON *nodo = cJSON_CreateObject();

        if (nodo == NULL) {
            goto fallito;
        }
        if (!cJSON_AddItemToArray(cards, nodo)) {
            cJSON_Delete(nodo);
            goto fallito;
        }
        if (cJSON_AddNumberToObject(nodo, "id", card->id) == NULL ||
            cJSON_AddStringToObject(nodo, "label", card->label) == NULL ||
            cJSON_AddStringToObject(nodo, "code", card->code) == NULL ||
            cJSON_AddStringToObject(nodo, "type",
                                    card->is_qrcode ? "qrcode" : "barcode") == NULL) {
            goto fallito;
        }

        /* I campi facoltativi si scrivono solo quando dicono qualcosa: il
         * colore se è diverso da quello che l'id assegna da sé, l'usa e getta
         * solo se è acceso. Cosi' una carta normale ha esattamente i campi che
         * le servono e il file resta leggibile. */
        opencard_color_for_id(card->id, colore_id, sizeof(colore_id));
        if (card->color[0] != '\0' && strcmp(card->color, colore_id) != 0 &&
            cJSON_AddStringToObject(nodo, "color", card->color) == NULL) {
            goto fallito;
        }
        if (card->disposable && cJSON_AddBoolToObject(nodo, "disposable", 1) == NULL) {
            goto fallito;
        }
        if (card->favorite && cJSON_AddBoolToObject(nodo, "favorite", 1) == NULL) {
            goto fallito;
        }
    }
    return radice;

fallito:
    cJSON_Delete(radice);
    return NULL;
}

/* Id assenti o ripetuti: si rinumera tutto. Due carte sullo stesso id si
 * perdono a vicenda, perché aprire, modificare o cancellare passa da lì.
 * Serve ai file già scritti dalla 1.0.2, che dopo un "azzera e sostituisci"
 * dai QR aveva lasciato tutte le carte con l'id a zero. */
static void rinumera_se_serve(opencard_lista *lista)
{
    size_t i, j;

    for (i = 0; i < lista->n; i++) {
        if (lista->carte[i].id < 1) {
            break;
        }
        for (j = 0; j < i; j++) {
            if (lista->carte[j].id == lista->carte[i].id) {
                break;
            }
        }
        if (j < i) {
            break;
        }
    }
    if (i == lista->n) {
        return;
    }
    for (i = 0; i < lista->n; i++) {
        lista->carte[i].id = (int)i + 1;
    }
}

static opencard_esito carica(opencard_lista *out, opencard_errore *errore)
{
    cJSON *radice;
    int mancante = 0;
    opencard_esito esito;

    azzera_errore(errore);
    out->carte = NULL;
    out->n = 0;
    out->capacita = 0;

    radice = leggi_file(&mancante, errore);
    if (radice == NULL) {
        /* File assente: si parte da vuoto, è il primo avvio. */
        return mancante ? OPENCARD_OK : (errore != NULL ? errore->codice : OPENCARD_ERR_IO);
    }
    esito = opencard_carte_da_json(radice, 0, out, errore);
    cJSON_Delete(radice);
    if (esito == OPENCARD_OK) {
        rinumera_se_serve(out);
    }
    return esito;
}

/* Scrittura atomica: file temporaneo, fsync, rename. Se il sistema uccide
 * l'app a metà, il file vecchio resta intatto. */
static opencard_esito salva(const opencard_lista *lista, opencard_errore *errore)
{
    char temporaneo[1100];
    cJSON *radice;
    char *testo;
    FILE *f;
    size_t lunghezza;

    if (percorso_dati[0] == '\0') {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    if (snprintf(temporaneo, sizeof(temporaneo), "%s.tmp", percorso_dati)
        >= (int)sizeof(temporaneo)) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }

    radice = (cJSON *)opencard_carte_a_json(lista, NULL);
    if (radice == NULL) {
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    testo = cJSON_Print(radice);
    cJSON_Delete(radice);
    if (testo == NULL) {
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    lunghezza = strlen(testo);

    f = fopen(temporaneo, "wb");
    if (f == NULL) {
        free(testo);
        return segnala(errore, OPENCARD_ERR_IO);
    }
    if (fwrite(testo, 1, lunghezza, f) != lunghezza || fflush(f) != 0) {
        fclose(f);
        remove(temporaneo);
        free(testo);
        return segnala(errore, OPENCARD_ERR_IO);
    }
    if (fsync(fileno(f)) != 0) {
        fclose(f);
        remove(temporaneo);
        free(testo);
        return segnala(errore, OPENCARD_ERR_IO);
    }
    fclose(f);
    free(testo);

    if (rename(temporaneo, percorso_dati) != 0) {
        remove(temporaneo);
        return segnala(errore, OPENCARD_ERR_IO);
    }
    return OPENCARD_OK;
}

opencard_esito opencard_init_db(void)
{
    opencard_lista vuota = {NULL, 0, 0};

    if (access(percorso_dati, F_OK) == 0) {
        return OPENCARD_OK;
    }
    return salva(&vuota, NULL);
}

opencard_esito opencard_get_all(opencard_lista *out, opencard_errore *errore)
{
    if (out == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    return carica(out, errore);
}

/* Le carte preferite, dei due gruppi insieme e nell'ordine in cui stanno.
 * La scheda con la stella non ha un ordine suo: mescolare due gruppi con due
 * ordini diversi vorrebbe dire inventarne un terzo. */
opencard_esito opencard_get_preferite(opencard_lista *out, opencard_errore *errore)
{
    opencard_lista tutte;
    opencard_esito esito;
    size_t i;

    if (out == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    out->carte = NULL;
    out->n = 0;
    out->capacita = 0;

    esito = carica(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    for (i = 0; i < tutte.n; i++) {
        if (tutte.carte[i].favorite) {
            if (!lista_aggiungi(out, &tutte.carte[i])) {
                opencard_lista_free(&tutte);
                opencard_lista_free(out);
                return segnala(errore, OPENCARD_ERR_MEMORIA);
            }
        }
    }
    opencard_lista_free(&tutte);
    return OPENCARD_OK;
}

opencard_esito opencard_set_favorite(int id, int preferita, opencard_errore *errore)
{
    opencard_lista tutte;
    opencard_esito esito;
    size_t i;
    int trovata = 0;

    azzera_errore(errore);
    esito = carica(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    for (i = 0; i < tutte.n; i++) {
        if (tutte.carte[i].id == id) {
            /* Gia' come la si vuole: si evita di riscrivere il file. */
            if (tutte.carte[i].favorite == (preferita ? 1 : 0)) {
                opencard_lista_free(&tutte);
                return OPENCARD_OK;
            }
            tutte.carte[i].favorite = preferita ? 1 : 0;
            trovata = 1;
            break;
        }
    }
    if (!trovata) {
        opencard_lista_free(&tutte);
        return segnala(errore, OPENCARD_ERR_NON_TROVATA);
    }
    esito = salva(&tutte, errore);
    opencard_lista_free(&tutte);
    return esito;
}

opencard_esito opencard_get_gruppo(int disposable, opencard_lista *out,
                                   opencard_errore *errore)
{
    opencard_lista tutte;
    opencard_esito esito;
    size_t i;

    if (out == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    out->carte = NULL;
    out->n = 0;
    out->capacita = 0;

    esito = carica(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    for (i = 0; i < tutte.n; i++) {
        if (tutte.carte[i].disposable == (disposable ? 1 : 0)) {
            if (!lista_aggiungi(out, &tutte.carte[i])) {
                opencard_lista_free(&tutte);
                opencard_lista_free(out);
                return segnala(errore, OPENCARD_ERR_MEMORIA);
            }
        }
    }
    opencard_lista_free(&tutte);
    return OPENCARD_OK;
}

opencard_esito opencard_get(int id, opencard_card *out, opencard_errore *errore)
{
    opencard_lista tutte;
    opencard_esito esito;
    size_t i;

    if (out == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    esito = carica(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    for (i = 0; i < tutte.n; i++) {
        if (tutte.carte[i].id == id) {
            *out = tutte.carte[i];
            opencard_lista_free(&tutte);
            return OPENCARD_OK;
        }
    }
    opencard_lista_free(&tutte);
    return segnala(errore, OPENCARD_ERR_NON_TROVATA);
}

int opencard_next_id(void)
{
    opencard_lista tutte;
    int massimo = 0;
    size_t i;

    if (carica(&tutte, NULL) != OPENCARD_OK) {
        return 1;
    }
    for (i = 0; i < tutte.n; i++) {
        if (tutte.carte[i].id > massimo) {
            massimo = tutte.carte[i].id;
        }
    }
    opencard_lista_free(&tutte);
    return massimo + 1;
}

/* Riempie una carta dai valori del form. Il colore si tiene solo se dice
 * qualcosa, cioè se è diverso da quello che l'id assegna da sé. */
static void componi(opencard_card *card, int id, const char *label, const char *code,
                    int is_qrcode, const char *color, int disposable, int favorite)
{
    char colore_id[OPENCARD_COLOR_MAX];

    card->id = id;
    card->favorite = favorite ? 1 : 0;
    copia(card->label, sizeof(card->label), label);
    copia(card->code, sizeof(card->code), code);
    card->is_qrcode = is_qrcode ? 1 : 0;
    card->disposable = disposable ? 1 : 0;
    card->color[0] = '\0';

    if (color != NULL && color[0] != '\0') {
        opencard_color_for_id(id, colore_id, sizeof(colore_id));
        if (strcmp(color, colore_id) != 0) {
            copia(card->color, sizeof(card->color), color);
        }
    }
}

opencard_esito opencard_insert(const char *label, const char *code, int is_qrcode,
                               const char *color, int disposable,
                               int *nuovo_id, opencard_errore *errore)
{
    opencard_lista tutte;
    opencard_card card;
    opencard_esito esito;
    int massimo = 0;
    size_t i;

    if (label == NULL || code == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    esito = carica(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    for (i = 0; i < tutte.n; i++) {
        if (tutte.carte[i].id > massimo) {
            massimo = tutte.carte[i].id;
        }
    }
    componi(&card, massimo + 1, label, code, is_qrcode, color, disposable, 0);

    if (!lista_aggiungi(&tutte, &card)) {
        opencard_lista_free(&tutte);
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    esito = salva(&tutte, errore);
    opencard_lista_free(&tutte);
    if (esito == OPENCARD_OK && nuovo_id != NULL) {
        *nuovo_id = card.id;
    }
    return esito;
}

opencard_esito opencard_update(int id, const char *label, const char *code,
                               int is_qrcode, const char *color, int disposable,
                               opencard_errore *errore)
{
    opencard_lista tutte;
    opencard_esito esito;
    size_t i;
    int trovata = 0;

    if (label == NULL || code == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    esito = carica(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    for (i = 0; i < tutte.n; i++) {
        if (tutte.carte[i].id == id) {
            /* La stella resta com'era: si accende e si spegne da sola, e una
             * modifica al nome non deve toglierla. */
            componi(&tutte.carte[i], id, label, code, is_qrcode, color, disposable,
                    tutte.carte[i].favorite);
            trovata = 1;
            break;
        }
    }
    if (!trovata) {
        opencard_lista_free(&tutte);
        return segnala(errore, OPENCARD_ERR_NON_TROVATA);
    }
    esito = salva(&tutte, errore);
    opencard_lista_free(&tutte);
    return esito;
}

opencard_esito opencard_delete(int id, opencard_errore *errore)
{
    opencard_lista tutte;
    opencard_esito esito;
    size_t i, scritte = 0;

    esito = carica(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    for (i = 0; i < tutte.n; i++) {
        if (tutte.carte[i].id != id) {
            tutte.carte[scritte++] = tutte.carte[i];
        }
    }
    tutte.n = scritte;
    esito = salva(&tutte, errore);
    opencard_lista_free(&tutte);
    return esito;
}

opencard_esito opencard_reorder(int disposable, const int *ids, size_t n,
                                opencard_errore *errore)
{
    opencard_lista tutte;
    opencard_esito esito;
    size_t i, j, quante = 0, presi = 0;
    int gruppo = disposable ? 1 : 0;

    if (ids == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    esito = carica(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }

    for (i = 0; i < tutte.n; i++) {
        if (tutte.carte[i].disposable == gruppo) {
            quante++;
        }
    }
    /* Gli id ricevuti devono essere esattamente quelli del gruppo, ognuno una
     * volta sola. Se non tornano non si tocca niente: meglio un riordino perso
     * che una carta persa. */
    if (quante != n) {
        opencard_lista_free(&tutte);
        return OPENCARD_OK;
    }
    for (i = 0; i < n; i++) {
        int trovato = 0;
        for (j = 0; j < i; j++) {
            if (ids[j] == ids[i]) {
                opencard_lista_free(&tutte);
                return OPENCARD_OK;   /* ripetuto */
            }
        }
        for (j = 0; j < tutte.n; j++) {
            if (tutte.carte[j].id == ids[i] && tutte.carte[j].disposable == gruppo) {
                trovato = 1;
                break;
            }
        }
        if (!trovato) {
            opencard_lista_free(&tutte);
            return OPENCARD_OK;
        }
    }

    /* Le carte dei due gruppi stanno mescolate in una lista sola: le nuove
     * prendono, nell'ordine, le posizioni che il gruppo occupava già, così
     * spostare una carta fedeltà non muove le usa e getta. */
    for (i = 0; i < tutte.n; i++) {
        if (tutte.carte[i].disposable != gruppo) {
            continue;
        }
        for (j = 0; j < tutte.n; j++) {
            if (tutte.carte[j].id == ids[presi] && tutte.carte[j].disposable == gruppo) {
                opencard_card temporanea = tutte.carte[i];
                tutte.carte[i] = tutte.carte[j];
                tutte.carte[j] = temporanea;
                break;
            }
        }
        presi++;
    }

    esito = salva(&tutte, errore);
    opencard_lista_free(&tutte);
    return esito;
}

opencard_esito opencard_replace_all(const opencard_lista *lista,
                                    opencard_errore *errore)
{
    if (lista == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    azzera_errore(errore);
    return salva(lista, errore);
}

opencard_esito opencard_append_all(const opencard_lista *lista,
                                   opencard_errore *errore)
{
    opencard_lista tutte;
    opencard_esito esito;
    int massimo = 0;
    size_t i;

    if (lista == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    azzera_errore(errore);
    if (lista->n == 0) {
        return OPENCARD_OK;
    }
    esito = carica(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    for (i = 0; i < tutte.n; i++) {
        if (tutte.carte[i].id > massimo) {
            massimo = tutte.carte[i].id;
        }
    }
    for (i = 0; i < lista->n; i++) {
        opencard_card card;

        /* Id nuovo: quello di chi cede non vuol dire niente qui, e due carte
         * con lo stesso id si perderebbero a vicenda. */
        componi(&card, ++massimo,
                lista->carte[i].label, lista->carte[i].code,
                lista->carte[i].is_qrcode, lista->carte[i].color,
                lista->carte[i].disposable, lista->carte[i].favorite);
        if (!lista_aggiungi(&tutte, &card)) {
            opencard_lista_free(&tutte);
            return segnala(errore, OPENCARD_ERR_MEMORIA);
        }
    }
    esito = salva(&tutte, errore);
    opencard_lista_free(&tutte);
    return esito;
}

void opencard_errore_testo(const opencard_errore *errore, char *out, size_t out_size)
{
    if (out == NULL || out_size == 0) {
        return;
    }
    if (errore == NULL || errore->codice == OPENCARD_OK) {
        copia(out, out_size, "");
        return;
    }

    switch (errore->codice) {
    case OPENCARD_ERR_IO:
        copia(out, out_size, "Il file non si legge o non si scrive.");
        break;
    case OPENCARD_ERR_JSON:
        copia(out, out_size,
              "Il file non è leggibile: non contiene un backup di OpenCard.");
        break;
    case OPENCARD_ERR_FORMATO:
        copia(out, out_size, "Il file non è un backup di OpenCard.");
        break;
    case OPENCARD_ERR_SCHEMA:
        snprintf(out, out_size,
                 "Backup creato da un'altra versione di OpenCard (formato %d). "
                 "Questa versione legge il formato %d.",
                 errore->schema_trovato, OPENCARD_SCHEMA_VERSION);
        break;
    case OPENCARD_ERR_CARTA:
        if (errore->dettaglio[0] != '\0') {
            snprintf(out, out_size, "Carta %d (%s): dati non validi.",
                     errore->posizione, errore->dettaglio);
        } else {
            snprintf(out, out_size, "Carta %d: formato non valido.",
                     errore->posizione);
        }
        break;
    case OPENCARD_ERR_MEMORIA:
        copia(out, out_size, "Memoria esaurita.");
        break;
    case OPENCARD_ERR_NON_TROVATA:
        copia(out, out_size, "La carta non esiste più.");
        break;
    case OPENCARD_ERR_ALTRO_TRASF:
        copia(out, out_size,
              "Questo codice appartiene a un altro passaggio di carte. "
              "Ricomincia da capo su tutti e due i telefoni.");
        break;
    case OPENCARD_ERR_TRASF_INCOMPLETO:
        copia(out, out_size, "Mancano ancora dei codici da inquadrare.");
        break;
    case OPENCARD_ERR_TRASF_ROTTO:
        copia(out, out_size,
              "I codici letti non tornano. Ricomincia il passaggio delle carte.");
        break;
    case OPENCARD_ERR_TRASF_VERSIONE:
        snprintf(out, out_size,
                 "Il codice arriva da una versione più recente di OpenCard "
                 "(formato %d). Aggiorna l'app su questo telefono.",
                 errore->schema_trovato);
        break;
    case OPENCARD_ERR_TRASF_TROPPE:
        copia(out, out_size,
              "Le carte sono troppe per il passaggio con i QR. "
              "Usa l'esportazione su file.");
        break;
    default:
        copia(out, out_size, "Errore imprevisto.");
        break;
    }
}
