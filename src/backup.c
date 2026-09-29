/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

#include "backup.h"

#include "archivio.h"
#include "cripto.h"
#include "csv.h"
#include "third-party/monocypher/monocypher.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "third-party/cJSON.h"

/* Adesso in UTC, "AAAA-MM-GGTHH:MM:SSZ", per il campo exported_at. Fino alla
 * 1.0.7-dev lo scrivevano le app: Android in UTC, iPhone con il suo fuso. */
static const char *adesso(char *out, size_t out_size)
{
    time_t ora = time(NULL);
    struct tm scomposto;

    if (gmtime_r(&ora, &scomposto) == NULL
        || strftime(out, out_size, "%Y-%m-%dT%H:%M:%SZ", &scomposto) == 0) {
        out[0] = '\0';
    }
    return out;
}

/* Il nome con la data di oggi nel fuso del telefono, "opencard-AAAAMMGG",
 * più quello che segue. */
static void nome_di_oggi(const char *coda, char *out, size_t out_size)
{
    time_t ora = time(NULL);
    struct tm scomposto;
    char data[16];

    if (out == NULL || out_size == 0) {
        return;
    }
    if (localtime_r(&ora, &scomposto) == NULL
        || strftime(data, sizeof(data), "%Y%m%d", &scomposto) == 0) {
        snprintf(out, out_size, "opencard%s", coda);
        return;
    }
    snprintf(out, out_size, "opencard-%s%s", data, coda);
}

void opencard_esporta_nome(opencard_formato formato, const char *password,
                           char *out, size_t out_size)
{
    const char *estensione = formato == OPENCARD_FORMATO_CSV ? ".csv" : ".zip";

    if (password != NULL && password[0] != '\0') {
        estensione = ".opencard";
    }
    nome_di_oggi(estensione, out, out_size);
}

void opencard_codici_nome(char *out, size_t out_size)
{
    nome_di_oggi("-codici.pdf", out, out_size);
}

opencard_esito opencard_backup_esporta(const char *esportato_il, char **testo,
                                       opencard_errore *errore)
{
    opencard_lista tutte;
    opencard_esito esito;
    cJSON *radice;
    char *stampato;
    char istante[32];

    if (testo == NULL) {
        return opencard_errore_segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    *testo = NULL;

    esito = opencard_get_all(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }

    radice = (cJSON *)opencard_carte_a_json(&tutte, esportato_il != NULL
                                                        ? esportato_il
                                                        : adesso(istante, sizeof(istante)));
    opencard_lista_free(&tutte);
    if (radice == NULL) {
        return opencard_errore_segnala(errore, OPENCARD_ERR_MEMORIA);
    }

    stampato = cJSON_Print(radice);
    cJSON_Delete(radice);
    if (stampato == NULL) {
        return opencard_errore_segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    *testo = stampato;
    return OPENCARD_OK;
}

void opencard_backup_free(char *testo)
{
    /* cJSON_Print alloca col suo allocatore: si libera con la sua funzione. */
    cJSON_free(testo);
}

opencard_esito opencard_backup_leggi(const char *testo, size_t lunghezza,
                                     opencard_lista *out, opencard_errore *errore)
{
    cJSON *radice;
    opencard_esito esito;

    if (testo == NULL || out == NULL) {
        return opencard_errore_segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    out->carte = NULL;
    out->n = 0;
    out->capacita = 0;

    /* Con lunghezza a zero si conta col terminatore: va bene solo per le
     * stringhe C. Un buffer letto da un file passa sempre la lunghezza vera,
     * perché qui nessuno garantisce che dopo l'ultimo byte ci sia uno zero. */
    if (lunghezza == 0) {
        lunghezza = strlen(testo);
    }
    if (lunghezza == 0) {
        return opencard_errore_segnala(errore, OPENCARD_ERR_JSON);      /* file vuoto */
    }

    radice = cJSON_ParseWithLength(testo, lunghezza);
    if (radice == NULL) {
        return opencard_errore_segnala(errore, OPENCARD_ERR_JSON);
    }

    /* Un backup arriva da fuori, quindi lo schema si controlla. */
    esito = opencard_carte_da_json(radice, 1, out, errore);
    cJSON_Delete(radice);
    if (esito != OPENCARD_OK) {
        return esito;
    }

    /* Id assenti, non validi o ripetuti: si rinumera tutto, altrimenti due
     * carte diverse finirebbero sullo stesso id e modificarne una toccherebbe
     * l'altra. È la stessa regola della lettura del file delle carte. */
    opencard_rinumera_se_serve(out);
    return OPENCARD_OK;
}

/* ----------------------------------------------------- esportare e importare */

#define NOME_ELENCO "opencard.json"
/* Il CSV dentro lo ZIP che esporta Catima. */
#define NOME_CATIMA "catima.csv"

/* Il nome di una voce senza le cartelle davanti. */
static const char *base_nome(const char *nome)
{
    const char *barra = strrchr(nome, '/');

    return barra != NULL ? barra + 1 : nome;
}

/* La voce con quel nome, o NULL. */
static const opencard_zip_voce *voce(const opencard_zip_lettura *lettura, const char *nome)
{
    size_t i;

    for (i = 0; i < lettura->n; i++) {
        if (strcmp(base_nome(lettura->voci[i].nome), nome) == 0) {
            return &lettura->voci[i];
        }
    }
    return NULL;
}

/* Vero se è lo ZIP di Catima: dentro c'è catima.csv e non il nostro elenco.
 * Guarda solo l'indice: fino alla 1.0.7-dev decomprimeva tutto l'archivio,
 * foto comprese, e Android lo chiedeva due volte prima di importarlo. */
static int zip_di_catima(const unsigned char *dati, size_t quanti)
{
    return opencard_zip_ha_voce(dati, quanti, NOME_CATIMA)
           && !opencard_zip_ha_voce(dati, quanti, NOME_ELENCO);
}

opencard_tipo_file opencard_file_tipo(const unsigned char *dati, size_t quanti)
{
    if (dati == NULL || quanti == 0) {
        return OPENCARD_FILE_JSON;
    }
    /* Il CSV prima: è testo, e un testo non passa mai per cifrato o per ZIP. */
    if (opencard_csv_e_csv(dati, quanti)) {
        return OPENCARD_FILE_CSV;
    }
    if (opencard_cripto_e_cifrato(dati, quanti)) {
        return OPENCARD_FILE_CIFRATO;
    }
    if (opencard_zip_e_archivio(dati, quanti)) {
        /* Lo ZIP di Catima porta un CSV: la domanda è quella del CSV. */
        return zip_di_catima(dati, quanti) ? OPENCARD_FILE_CSV : OPENCARD_FILE_ARCHIVIO;
    }
    return OPENCARD_FILE_JSON;
}

static int percorso_foto(const char *nome, char *out, size_t out_size)
{
    const char *cartella = opencard_store_cartella_foto();

    return cartella[0] != '\0'
           && snprintf(out, out_size, "%s/%s", cartella, nome) < (int)out_size;
}

static unsigned char *leggi_foto(const char *nome, size_t *quanti)
{
    char percorso[1100];
    unsigned char *byte;
    FILE *f;
    long lunghezza;

    if (!percorso_foto(nome, percorso, sizeof(percorso))
        || (f = fopen(percorso, "rb")) == NULL) {
        return NULL;
    }
    if (fseek(f, 0, SEEK_END) != 0 || (lunghezza = ftell(f)) < 0
        || fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return NULL;
    }
    byte = malloc(lunghezza > 0 ? (size_t)lunghezza : 1);
    if (byte != NULL && fread(byte, 1, (size_t)lunghezza, f) != (size_t)lunghezza) {
        free(byte);
        byte = NULL;
    }
    fclose(f);
    *quanti = (size_t)lunghezza;
    return byte;
}

/* L'archivio: l'elenco e le foto che esistono davvero, una volta ciascuna. */
static opencard_esito scrivi_archivio(const opencard_lista *tutte,
                                      const char *esportato_il,
                                      unsigned char **fuori, size_t *fuori_n,
                                      opencard_errore *errore)
{
    char istante[32];
    opencard_zip_voce *voci;
    size_t n = 0, i, j, k;
    cJSON *radice;
    char *elenco;
    opencard_esito esito;

    radice = (cJSON *)opencard_carte_a_json(tutte, esportato_il != NULL
                                                       ? esportato_il
                                                       : adesso(istante, sizeof(istante)));
    elenco = radice != NULL ? cJSON_Print(radice) : NULL;
    cJSON_Delete(radice);
    voci = calloc(1 + 2 * tutte->n, sizeof(*voci));
    if (elenco == NULL || voci == NULL) {
        cJSON_free(elenco);
        free(voci);
        return opencard_errore_segnala(errore, OPENCARD_ERR_MEMORIA);
    }

    snprintf(voci[n].nome, sizeof(voci[n].nome), "%s", NOME_ELENCO);
    voci[n].dati = (unsigned char *)elenco;
    voci[n].quanti = strlen(elenco);
    n++;

    for (i = 0; i < tutte->n; i++) {
        const char *foto[2] = {tutte->carte[i].foto_fronte, tutte->carte[i].foto_retro};

        for (j = 0; j < 2; j++) {
            int gia = 0;

            if (!opencard_foto_nome_sicuro(foto[j])) {
                continue;
            }
            for (k = 1; k < n && !gia; k++) {
                gia = strcmp(voci[k].nome, foto[j]) == 0;
            }
            if (gia) {
                continue;
            }
            voci[n].dati = leggi_foto(foto[j], &voci[n].quanti);
            if (voci[n].dati == NULL) {
                continue;               /* sparita dal disco: si salta */
            }
            snprintf(voci[n].nome, sizeof(voci[n].nome), "%s", foto[j]);
            n++;
        }
    }

    esito = opencard_zip_scrivi(voci, n, fuori, fuori_n, errore);

    crypto_wipe(elenco, strlen(elenco));
    cJSON_free(elenco);
    for (k = 1; k < n; k++) {
        free(voci[k].dati);
    }
    free(voci);
    return esito;
}

opencard_esito opencard_esporta(opencard_formato formato, const char *esportato_il,
                                const char *password,
                                unsigned char **byte, size_t *quanti,
                                opencard_errore *errore)
{
    opencard_lista tutte;
    unsigned char *chiaro = NULL;
    size_t chiaro_n = 0;
    opencard_esito esito;

    if (byte == NULL || quanti == NULL) {
        return opencard_errore_segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    *byte = NULL;
    *quanti = 0;

    esito = opencard_get_all(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    if (formato == OPENCARD_FORMATO_CSV) {
        esito = opencard_csv_scrivi(&tutte, (char **)&chiaro, &chiaro_n, errore);
    } else {
        esito = scrivi_archivio(&tutte, esportato_il, &chiaro, &chiaro_n, errore);
    }
    opencard_lista_free(&tutte);
    if (esito != OPENCARD_OK) {
        return esito;
    }

    if (password == NULL || password[0] == '\0') {
        *byte = chiaro;
        *quanti = chiaro_n;
    } else {
        esito = opencard_cripto_cifra(chiaro, chiaro_n, password, byte, quanti, errore);
        /* In chiaro qui dentro ci sono i numeri delle tessere e le foto. */
        crypto_wipe(chiaro, chiaro_n);
        free(chiaro);
        if (esito != OPENCARD_OK) {
            return esito;
        }
    }
    /* Un file che l'importazione rifiuterebbe non esce: meglio saperlo adesso
     * che il giorno in cui serve il ripristino. */
    if (*quanti > OPENCARD_FILE_MAX) {
        crypto_wipe(*byte, *quanti);
        free(*byte);
        *byte = NULL;
        *quanti = 0;
        return opencard_errore_segnala(errore, OPENCARD_ERR_TROPPO_GRANDE);
    }
    return OPENCARD_OK;
}

/* Le carte di un archivio, con le foto rimesse a posto. Uno ZIP di Catima
 * dà le carte del suo CSV e `*e_csv` a 1: le sue immagini hanno nomi che le
 * nostre carte non conoscono, e restano fuori. */
static opencard_esito leggi_archivio(const unsigned char *dati, size_t quanti,
                                     opencard_lista *out, int *e_csv,
                                     opencard_errore *errore)
{
    opencard_zip_lettura lettura;
    opencard_esito esito;
    const opencard_zip_voce *elenco, *catima;
    size_t i, j;

    memset(out, 0, sizeof(*out));
    *e_csv = 0;
    esito = opencard_zip_leggi(dati, quanti, &lettura, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    elenco = voce(&lettura, NOME_ELENCO);
    catima = voce(&lettura, NOME_CATIMA);
    if (elenco == NULL && catima != NULL) {
        esito = opencard_csv_leggi(catima->dati, catima->quanti, out, errore);
        opencard_zip_libera(&lettura);
        *e_csv = 1;
        return esito;
    }
    if (elenco == NULL) {
        opencard_zip_libera(&lettura);
        return opencard_errore_segnala(errore, OPENCARD_ERR_FORMATO);
    }
    esito = opencard_backup_leggi((const char *)elenco->dati, elenco->quanti, out, errore);
    if (esito != OPENCARD_OK) {
        opencard_zip_libera(&lettura);
        return esito;
    }

    /* Le foto tornano con il nome che avevano, perché nella carta sta scritto
     * quello; e solo quelle che una carta nomina. Si scrivono prima che le
     * carte entrino nel file: se poi la scrittura fallisce, restano file che
     * nessuna carta nomina e che la pulizia toglie. */
    for (i = 0; i < lettura.n; i++) {
        const char *base = base_nome(lettura.voci[i].nome);
        int nominata = 0;

        if (!opencard_foto_nome_sicuro(base) || strcmp(base, NOME_ELENCO) == 0) {
            continue;
        }
        for (j = 0; j < out->n && !nominata; j++) {
            nominata = strcmp(out->carte[j].foto_fronte, base) == 0
                       || strcmp(out->carte[j].foto_retro, base) == 0;
        }
        if (nominata) {
            /* Atomica come le altre: se si ferma a metà, la foto che c'era
             * con quel nome resta intera. */
            opencard_foto_scrivi(base, lettura.voci[i].dati, lettura.voci[i].quanti, NULL);
        }
    }
    opencard_zip_libera(&lettura);
    return OPENCARD_OK;
}

opencard_esito opencard_importa(const unsigned char *dati, size_t quanti,
                                const char *password, int sostituisci,
                                int *quante, opencard_errore *errore)
{
    unsigned char *chiaro = NULL;
    size_t chiaro_n = 0;
    const unsigned char *aperto = dati;
    size_t aperto_n = quanti;
    opencard_lista lista;
    opencard_esito esito;
    size_t i;
    int aggiungi = 0, e_csv = 0;

    if (quante != NULL) {
        *quante = 0;
    }
    if (dati == NULL) {
        return opencard_errore_segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    /* Un file vuoto non è un backup. Va fermato qui: più sotto una lunghezza
     * a zero vorrebbe dire "misura la stringa", su un buffer senza NUL. */
    if (quanti == 0) {
        return opencard_errore_segnala(errore, OPENCARD_ERR_JSON);
    }
    if (quanti > OPENCARD_FILE_MAX) {
        return opencard_errore_segnala(errore, OPENCARD_ERR_TROPPO_GRANDE);
    }
    if (opencard_cripto_e_cifrato(dati, quanti)) {
        if (password == NULL || password[0] == '\0') {
            return opencard_errore_segnala(errore, OPENCARD_ERR_PASSWORD);
        }
        esito = opencard_cripto_decifra(dati, quanti, password, &chiaro, &chiaro_n, errore);
        if (esito != OPENCARD_OK) {
            return esito;
        }
        aperto = chiaro;
        aperto_n = chiaro_n;
    }

    /* Tre forme, in ordine di quanto sono recenti: l'archivio con le foto, il
     * CSV di un'altra app, e il solo JSON dei backup fatti prima delle foto. */
    if (opencard_zip_e_archivio(aperto, aperto_n)) {
        esito = leggi_archivio(aperto, aperto_n, &lista, &e_csv, errore);
    } else if (opencard_csv_e_csv(aperto, aperto_n)) {
        esito = opencard_csv_leggi(aperto, aperto_n, &lista, errore);
        e_csv = 1;
    } else {
        esito = opencard_backup_leggi((const char *)aperto, aperto_n, &lista, errore);
    }
    if (chiaro != NULL) {
        crypto_wipe(chiaro, chiaro_n);
        opencard_cripto_free(chiaro);
    }
    if (esito != OPENCARD_OK) {
        return esito;
    }
    /* Il CSV, sciolto o dentro lo ZIP di Catima, si aggiunge oppure prende il
     * posto delle carte; sostituendo, gli id ripartono da 1. */
    if (e_csv && sostituisci) {
        for (i = 0; i < lista.n; i++) {
            lista.carte[i].id = (int)i + 1;
        }
    }
    aggiungi = e_csv && !sostituisci;

    /* Una scrittura sola. Sostituendo, il core toglie anche le foto delle
     * carte che se ne vanno. */
    esito = aggiungi ? opencard_append_all(&lista, errore)
                     : opencard_replace_all(&lista, errore);
    if (esito == OPENCARD_OK && quante != NULL) {
        *quante = (int)lista.n;
    }
    opencard_lista_free(&lista);
    return esito;
}
