/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

#include "cripto.h"
#include "third-party/monocypher/monocypher.h"
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

/* La chiave del file dei dati, quando la piattaforma ce l'ha data. Tutti zeri
 * e `con_chiave` a zero vuol dire file in chiaro, come prima. */
static unsigned char chiave_dati[OPENCARD_CRIPTO_CHIAVE_N];
static int con_chiave = 0;

void opencard_store_chiave(const unsigned char *chiave)
{
    if (chiave == NULL) {
        crypto_wipe(chiave_dati, sizeof(chiave_dati));
        con_chiave = 0;
        return;
    }
    memcpy(chiave_dati, chiave, sizeof(chiave_dati));
    con_chiave = 1;
}


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

    /* Il file puo' essere cifrato o in chiaro, e si riconosce dai primi byte.
     * In chiaro si legge sempre, anche con la chiave in mano: e' il file di
     * chi aggiorna da una versione precedente, e la prima scrittura lo
     * converte. Cifrato senza chiave non si apre, ed e' il punto. */
    if (opencard_cripto_e_cifrato((const unsigned char *)testo, letti)) {
        unsigned char *chiaro = NULL;
        size_t chiaro_n = 0;

        if (!con_chiave) {
            free(testo);
            segnala(errore, OPENCARD_ERR_PASSWORD);
            return NULL;
        }
        if (opencard_cripto_decifra_chiave((const unsigned char *)testo, letti,
                                           chiave_dati, &chiaro, &chiaro_n,
                                           errore) != OPENCARD_OK) {
            free(testo);
            return NULL;
        }
        free(testo);
        testo = (char *)chiaro;
    }

    radice = cJSON_Parse(testo);
    crypto_wipe(testo, strlen(testo));
    free(testo);
    if (radice == NULL) {
        segnala(errore, OPENCARD_ERR_JSON);
        return NULL;
    }
    return radice;
}

/* Una carta dal suo oggetto JSON. `posizione` serve solo ai messaggi. */
/* I nomi con cui le simbologie viaggiano nel file. L'indice è il valore
 * dell'enum: chi aggiunge una simbologia aggiunge una riga in fondo, qui e in
 * store.h, e non tocca quelle che ci sono. */
static const char *const NOMI_SIMBOLOGIA[OPENCARD_SIM_QUANTE] = {
    "code128", "qr", "aztec", "codabar", "code39", "code93", "datamatrix",
    "ean8", "ean13", "itf", "pdf417", "upca", "upce", "microqr", "gs1_128",
    "databar", "databar_espanso", "msi"
};

/* Le cifre di un codice, saltando gli spazi ai capi. */
static int solo_cifre_fra_spazi(const char *code, size_t *quante)
{
    const char *p = code;
    const char *fine;
    size_t i, n;

    *quante = 0;
    if (code == NULL) {
        return 0;
    }
    while (*p != '\0' && (*p == ' ' || *p == '\t' || *p == '\n')) {
        p++;
    }
    fine = p + strlen(p);
    while (fine > p && (fine[-1] == ' ' || fine[-1] == '\t' || fine[-1] == '\n')) {
        fine--;
    }
    n = (size_t)(fine - p);
    if (n == 0) {
        return 0;
    }
    for (i = 0; i < n; i++) {
        if (p[i] < '0' || p[i] > '9') {
            return 0;
        }
    }
    *quante = n;
    return 1;
}

opencard_simbologia opencard_simbologia_indovinata(const char *code, int is_qrcode)
{
    size_t cifre;

    if (is_qrcode) {
        return OPENCARD_SIM_QR;
    }
    if (solo_cifre_fra_spazi(code, &cifre)) {
        if (cifre == 13) {
            return OPENCARD_SIM_EAN13;
        }
        if (cifre == 8) {
            return OPENCARD_SIM_EAN8;
        }
        if (cifre == 12) {
            return OPENCARD_SIM_UPCA;
        }
    }
    return OPENCARD_SIM_CODE128;
}

const char *opencard_simbologia_nome(opencard_simbologia simbologia)
{
    if (simbologia < 0 || simbologia >= OPENCARD_SIM_QUANTE) {
        return NULL;
    }
    return NOMI_SIMBOLOGIA[simbologia];
}

opencard_simbologia opencard_simbologia_da_nome(const char *nome)
{
    int i;

    if (nome == NULL) {
        return OPENCARD_SIM_QUANTE;
    }
    for (i = 0; i < (int)OPENCARD_SIM_QUANTE; i++) {
        if (strcmp(nome, NOMI_SIMBOLOGIA[i]) == 0) {
            return (opencard_simbologia)i;
        }
    }
    return OPENCARD_SIM_QUANTE;
}

/* Le uniche due simbologie che l'app disegnava prima della 1.0.3, e che le
 * interfacce continuano a chiedere finché non passano a `simbologia`. */
static void allinea_is_qrcode(opencard_card *card)
{
    card->is_qrcode = (card->simbologia == OPENCARD_SIM_QR
                       || card->simbologia == OPENCARD_SIM_MICROQR) ? 1 : 0;
}

/* Una data si accetta vuota oppure scritta per intero: "AAAA-MM-GG". Non
 * controlla che il giorno esista davvero, controlla che sia una data e non
 * testo libero, perché è su questo che poi si ordina e si avvisa. */
static int data_valida(const char *testo)
{
    int i;

    if (testo == NULL || testo[0] == '\0') {
        return 1;
    }
    if (strlen(testo) != 10 || testo[4] != '-' || testo[7] != '-') {
        return 0;
    }
    for (i = 0; i < 10; i++) {
        if (i == 4 || i == 7) {
            continue;
        }
        if (testo[i] < '0' || testo[i] > '9') {
            return 0;
        }
    }
    return 1;
}

static opencard_esito carta_da_json(const cJSON *nodo, int posizione, int schema_del_file,
                                    opencard_card *out, opencard_errore *errore)
{
    const cJSON *label = cJSON_GetObjectItemCaseSensitive(nodo, "label");
    const cJSON *code = cJSON_GetObjectItemCaseSensitive(nodo, "code");
    const cJSON *tipo = cJSON_GetObjectItemCaseSensitive(nodo, "type");
    const cJSON *id = cJSON_GetObjectItemCaseSensitive(nodo, "id");
    const cJSON *color = cJSON_GetObjectItemCaseSensitive(nodo, "color");
    const cJSON *disposable = cJSON_GetObjectItemCaseSensitive(nodo, "disposable");
    const cJSON *favorite = cJSON_GetObjectItemCaseSensitive(nodo, "favorite");
    const cJSON *simbologia = cJSON_GetObjectItemCaseSensitive(nodo, "symbology");
    const cJSON *note = cJSON_GetObjectItemCaseSensitive(nodo, "note");
    const cJSON *scadenza = cJSON_GetObjectItemCaseSensitive(nodo, "expiry");
    const cJSON *saldo = cJSON_GetObjectItemCaseSensitive(nodo, "balance");
    const cJSON *foto_fronte = cJSON_GetObjectItemCaseSensitive(nodo, "photo_front");
    const cJSON *foto_retro = cJSON_GetObjectItemCaseSensitive(nodo, "photo_back");

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
        out->simbologia = OPENCARD_SIM_QR;
    } else if (strcmp(tipo->valuestring, "barcode") == 0) {
        /* Nessuna simbologia scritta vuol dire carta salvata prima della
         * 1.0.3: si indovina dal codice, com'era prima. Darle Code 128 le
         * toglierebbe le guardie dell'EAN, che i lettori da cassa si
         * aspettano e che si vedono a occhio. */
        out->simbologia = opencard_simbologia_indovinata(
            cJSON_IsString(code) ? code->valuestring : NULL, 0);
    } else {
        return segnala(errore, OPENCARD_ERR_CARTA);
    }
    /* Dallo schema 2 la simbologia sta per esteso e vince su "type", che
     * resta scritto per non rompere gli strumenti che leggono i backup.
     * Un nome che non conosciamo arriva da una versione più nuova: la carta
     * si tiene, e il codice si disegna come Code 128, che è il ripiego di
     * sempre. */
    if (cJSON_IsString(simbologia) && simbologia->valuestring != NULL) {
        opencard_simbologia letta = opencard_simbologia_da_nome(simbologia->valuestring);
        opencard_simbologia proposta = opencard_simbologia_indovinata(
            cJSON_IsString(code) ? code->valuestring : NULL, 0);
        /* Nei file di schema 2 il «code128» non vuol dire scelto: quelle build
         * lo scrivevano su tutto quello che leggevano da un file di schema 1.
         * Su un codice che si indovinerebbe EAN o UPC si preferisce la
         * proposta, che è quello che l'app faceva prima e che ha le guardie. */
        if (letta == OPENCARD_SIM_CODE128 && schema_del_file <= 2
            && proposta != OPENCARD_SIM_CODE128 && proposta != OPENCARD_SIM_QR) {
            out->simbologia = proposta;
        } else if (letta != OPENCARD_SIM_QUANTE) {
            out->simbologia = letta;
        }
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
    allinea_is_qrcode(out);

    /* I campi in più: assenti vuol dire vuoti, e un file di schema 1 non ne
     * ha nemmeno uno. Quello che c'è ma non è testo è un file malformato. */
    if (cJSON_IsString(note) && note->valuestring != NULL) {
        copia(out->note, sizeof(out->note), note->valuestring);
        opencard_utf8_ripara(out->note);
    } else if (note != NULL && !cJSON_IsNull(note)) {
        return segnala(errore, OPENCARD_ERR_CARTA);
    }
    if (cJSON_IsString(saldo) && saldo->valuestring != NULL) {
        copia(out->saldo, sizeof(out->saldo), saldo->valuestring);
        opencard_utf8_ripara(out->saldo);
    } else if (saldo != NULL && !cJSON_IsNull(saldo)) {
        return segnala(errore, OPENCARD_ERR_CARTA);
    }
    if (cJSON_IsString(scadenza) && scadenza->valuestring != NULL) {
        if (!data_valida(scadenza->valuestring)) {
            return segnala(errore, OPENCARD_ERR_CARTA);
        }
        copia(out->scadenza, sizeof(out->scadenza), scadenza->valuestring);
    } else if (scadenza != NULL && !cJSON_IsNull(scadenza)) {
        return segnala(errore, OPENCARD_ERR_CARTA);
    }
    if (cJSON_IsString(foto_fronte) && foto_fronte->valuestring != NULL) {
        copia(out->foto_fronte, sizeof(out->foto_fronte), foto_fronte->valuestring);
        opencard_utf8_ripara(out->foto_fronte);
    } else if (foto_fronte != NULL && !cJSON_IsNull(foto_fronte)) {
        return segnala(errore, OPENCARD_ERR_CARTA);
    }
    if (cJSON_IsString(foto_retro) && foto_retro->valuestring != NULL) {
        copia(out->foto_retro, sizeof(out->foto_retro), foto_retro->valuestring);
        opencard_utf8_ripara(out->foto_retro);
    } else if (foto_retro != NULL && !cJSON_IsNull(foto_retro)) {
        return segnala(errore, OPENCARD_ERR_CARTA);
    }

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
    int schema_del_file;
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
    schema = cJSON_GetObjectItemCaseSensitive(radice, "schema");
    /* Serve anche quando non si controlla: il file dei dati si legge senza
     * controllo di versione, e la correzione del «code128» dipende da quale
     * schema l'ha scritto. Zero vuol dire "non lo dice", cioè vecchio. */
    schema_del_file = cJSON_IsNumber(schema) ? intero_da(schema->valuedouble) : 0;

    if (controlla_schema) {
        int trovato = schema_del_file;

        /* Uno schema più vecchio si legge: i campi che non ha restano vuoti,
         * ed è il motivo per cui i campi nuovi sono tutti facoltativi. Uno
         * più nuovo no: avrebbe roba che qui si perderebbe riscrivendo. */
        if (!cJSON_IsNumber(schema) || trovato < 1 || trovato > OPENCARD_SCHEMA_VERSION) {
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
        esito = carta_da_json(nodo, posizione, schema_del_file, &card, errore);
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

/* Il nome della simbologia di una carta. Una carta costruita a mano dalle
 * interfacce, che oggi riempiono solo is_qrcode, arriva qui con simbologia a
 * zero: il ripiego la fa tornare QR o Code 128 come si aspetta chi legge. */
static const char *nome_simbologia_scritta(const opencard_card *card)
{
    const char *nome = opencard_simbologia_nome(card->simbologia);

    if (nome == NULL || (card->simbologia == OPENCARD_SIM_CODE128 && card->is_qrcode)) {
        return card->is_qrcode ? "qr" : "code128";
    }
    return nome;
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
        /* La simbologia si scrive sempre: "type" da solo saprebbe dire solo
         * QR o non QR, e una carta Aztec riletta diventerebbe un Code 128. */
        if (cJSON_AddStringToObject(nodo, "symbology",
                                    nome_simbologia_scritta(card)) == NULL) {
            goto fallito;
        }
        if (card->note[0] != '\0' &&
            cJSON_AddStringToObject(nodo, "note", card->note) == NULL) {
            goto fallito;
        }
        if (card->scadenza[0] != '\0' &&
            cJSON_AddStringToObject(nodo, "expiry", card->scadenza) == NULL) {
            goto fallito;
        }
        if (card->saldo[0] != '\0' &&
            cJSON_AddStringToObject(nodo, "balance", card->saldo) == NULL) {
            goto fallito;
        }
        if (card->foto_fronte[0] != '\0' &&
            cJSON_AddStringToObject(nodo, "photo_front", card->foto_fronte) == NULL) {
            goto fallito;
        }
        if (card->foto_retro[0] != '\0' &&
            cJSON_AddStringToObject(nodo, "photo_back", card->foto_retro) == NULL) {
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

    /* Con la chiave sul disco ci va il pacchetto cifrato, non il JSON. Il
     * JSON in chiaro resta in memoria il tempo di cifrarlo e poi si azzera:
     * dentro ci sono i numeri delle tessere. */
    if (con_chiave) {
        unsigned char *pacchetto = NULL;
        size_t pacchetto_n = 0;

        if (opencard_cripto_cifra_chiave((const unsigned char *)testo, lunghezza,
                                         chiave_dati, &pacchetto, &pacchetto_n,
                                         errore) != OPENCARD_OK) {
            crypto_wipe(testo, lunghezza);
            free(testo);
            return errore != NULL ? errore->codice : OPENCARD_ERR_MEMORIA;
        }
        crypto_wipe(testo, lunghezza);
        free(testo);
        testo = (char *)pacchetto;
        lunghezza = pacchetto_n;
    }

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

/* Cerca una carta e la passa a chi la deve cambiare. Il salvataggio avviene
 * una volta sola, e se la modifica non cambia niente il file non si tocca. */
static opencard_esito cambia_carta(int id, opencard_errore *errore,
                                   int (*modifica)(opencard_card *, const void *),
                                   const void *dati)
{
    opencard_lista tutte;
    opencard_esito esito;
    size_t i;

    azzera_errore(errore);
    esito = carica(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    for (i = 0; i < tutte.n; i++) {
        if (tutte.carte[i].id != id) {
            continue;
        }
        switch (modifica(&tutte.carte[i], dati)) {
        case 0:                                 /* già così: niente da scrivere */
            opencard_lista_free(&tutte);
            return OPENCARD_OK;
        case -1:                                /* valori non validi */
            opencard_lista_free(&tutte);
            return segnala(errore, OPENCARD_ERR_ARGOMENTI);
        default:
            esito = salva(&tutte, errore);
            opencard_lista_free(&tutte);
            return esito;
        }
    }
    opencard_lista_free(&tutte);
    return segnala(errore, OPENCARD_ERR_NON_TROVATA);
}

static int scrivi_simbologia(opencard_card *card, const void *dati)
{
    opencard_simbologia voluta = *(const opencard_simbologia *)dati;

    if (voluta < 0 || voluta >= OPENCARD_SIM_QUANTE) {
        return -1;
    }
    if (card->simbologia == voluta) {
        return 0;
    }
    card->simbologia = voluta;
    allinea_is_qrcode(card);
    return 1;
}

opencard_esito opencard_set_simbologia(int id, opencard_simbologia simbologia,
                                       opencard_errore *errore)
{
    return cambia_carta(id, errore, scrivi_simbologia, &simbologia);
}

/* NULL vuol dire "lascia com'è": è quello che permette alle interfacce di
 * toccare un campo solo senza rileggere e riscrivere gli altri due. */
struct dettagli { const char *note; const char *scadenza; const char *saldo; };

static int scrivi_dettagli(opencard_card *card, const void *dati)
{
    const struct dettagli *d = dati;
    int cambiato = 0;

    if (d->scadenza != NULL && !data_valida(d->scadenza)) {
        return -1;
    }
    if (d->note != NULL && strcmp(card->note, d->note) != 0) {
        copia(card->note, sizeof(card->note), d->note);
        cambiato = 1;
    }
    if (d->scadenza != NULL && strcmp(card->scadenza, d->scadenza) != 0) {
        copia(card->scadenza, sizeof(card->scadenza), d->scadenza);
        cambiato = 1;
    }
    if (d->saldo != NULL && strcmp(card->saldo, d->saldo) != 0) {
        copia(card->saldo, sizeof(card->saldo), d->saldo);
        cambiato = 1;
    }
    return cambiato;
}

opencard_esito opencard_set_dettagli(int id, const char *note, const char *scadenza,
                                     const char *saldo, opencard_errore *errore)
{
    struct dettagli d;

    d.note = note;
    d.scadenza = scadenza;
    d.saldo = saldo;
    return cambia_carta(id, errore, scrivi_dettagli, &d);
}

struct foto { const char *fronte; const char *retro; };

static int scrivi_foto(opencard_card *card, const void *dati)
{
    const struct foto *f = dati;
    int cambiato = 0;

    if (f->fronte != NULL && strcmp(card->foto_fronte, f->fronte) != 0) {
        copia(card->foto_fronte, sizeof(card->foto_fronte), f->fronte);
        cambiato = 1;
    }
    if (f->retro != NULL && strcmp(card->foto_retro, f->retro) != 0) {
        copia(card->foto_retro, sizeof(card->foto_retro), f->retro);
        cambiato = 1;
    }
    return cambiato;
}

opencard_esito opencard_set_foto(int id, const char *fronte, const char *retro,
                                 opencard_errore *errore)
{
    struct foto f;

    f.fronte = fronte;
    f.retro = retro;
    return cambia_carta(id, errore, scrivi_foto, &f);
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
    card->simbologia = is_qrcode ? OPENCARD_SIM_QR : OPENCARD_SIM_CODE128;
    card->disposable = disposable ? 1 : 0;
    card->color[0] = '\0';
    /* La carta arriva dallo stack e non è azzerata: i campi in più vanno
     * messi a vuoto qui, altrimenti si porta dietro quello che c'era prima
     * in memoria e finisce nel file. */
    card->note[0] = '\0';
    card->scadenza[0] = '\0';
    card->saldo[0] = '\0';
    card->foto_fronte[0] = '\0';
    card->foto_retro[0] = '\0';

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
        /* Quello che componi() non sa: cambia l'id, non la carta. */
        card.simbologia = lista->carte[i].simbologia;
        allinea_is_qrcode(&card);
        copia(card.note, sizeof(card.note), lista->carte[i].note);
        copia(card.scadenza, sizeof(card.scadenza), lista->carte[i].scadenza);
        copia(card.saldo, sizeof(card.saldo), lista->carte[i].saldo);
        copia(card.foto_fronte, sizeof(card.foto_fronte), lista->carte[i].foto_fronte);
        copia(card.foto_retro, sizeof(card.foto_retro), lista->carte[i].foto_retro);
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
    case OPENCARD_ERR_PASSWORD:
        copia(out, out_size,
              "La password non apre questo backup, oppure il file è stato "
              "modificato.");
        break;
    default:
        copia(out, out_size, "Errore imprevisto.");
        break;
    }
}
