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
#include <sys/stat.h>

#include "third-party/cJSON.h"

/* Come in store.c: chi chiama legge il messaggio da `errore`, quindi ogni
 * uscita con un codice diverso da OPENCARD_OK deve valorizzarlo. Lasciarlo
 * com'era fa leggere ai ponti una struttura mai scritta. */
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

void opencard_backup_nome(const char *oggi, char *out, size_t out_size)
{
    if (out == NULL || out_size == 0) {
        return;
    }
    if (oggi == NULL || oggi[0] == '\0') {
        snprintf(out, out_size, "opencard.json");
        return;
    }
    snprintf(out, out_size, "opencard-%s.json", oggi);
}

opencard_esito opencard_backup_esporta(const char *esportato_il, char **testo,
                                       opencard_errore *errore)
{
    opencard_lista tutte;
    opencard_esito esito;
    cJSON *radice;
    char *stampato;

    if (testo == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    *testo = NULL;

    esito = opencard_get_all(&tutte, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }

    radice = (cJSON *)opencard_carte_a_json(&tutte,
                                            esportato_il != NULL ? esportato_il : "");
    opencard_lista_free(&tutte);
    if (radice == NULL) {
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }

    stampato = cJSON_Print(radice);
    cJSON_Delete(radice);
    if (stampato == NULL) {
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    *testo = stampato;
    return OPENCARD_OK;
}

opencard_esito opencard_backup_esporta_cifrato(const char *esportato_il,
                                               const char *password,
                                               unsigned char **byte, size_t *quanti,
                                               opencard_errore *errore)
{
    char *testo = NULL;
    opencard_esito esito;

    if (byte == NULL || quanti == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    *byte = NULL;
    *quanti = 0;
    if (password == NULL || password[0] == '\0') {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }

    esito = opencard_backup_esporta(esportato_il, &testo, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }

    esito = opencard_cripto_cifra((const unsigned char *)testo, strlen(testo),
                                  password, byte, quanti, errore);
    /* Il JSON in chiaro non deve restare in memoria dopo: qui dentro ci sono
     * i numeri delle tessere. */
    crypto_wipe(testo, strlen(testo));
    opencard_backup_free(testo);
    return esito;
}

opencard_esito opencard_backup_leggi_file(const unsigned char *dati, size_t quanti,
                                          const char *password,
                                          opencard_lista *out,
                                          opencard_errore *errore)
{
    unsigned char *chiaro = NULL;
    size_t chiaro_n = 0;
    opencard_esito esito;

    if (out == NULL || dati == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    if (!opencard_cripto_e_cifrato(dati, quanti)) {
        return opencard_backup_leggi((const char *)dati, quanti, out, errore);
    }
    if (password == NULL || password[0] == '\0') {
        memset(out, 0, sizeof(*out));
        return segnala(errore, OPENCARD_ERR_PASSWORD);
    }

    esito = opencard_cripto_decifra(dati, quanti, password, &chiaro, &chiaro_n, errore);
    if (esito != OPENCARD_OK) {
        memset(out, 0, sizeof(*out));
        return esito;
    }

    esito = opencard_backup_leggi((const char *)chiaro, chiaro_n, out, errore);
    crypto_wipe(chiaro, chiaro_n);
    opencard_cripto_free(chiaro);
    return esito;
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
    size_t i, j;
    int rinumera = 0;

    if (testo == NULL || out == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
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
        return segnala(errore, OPENCARD_ERR_JSON);      /* file vuoto */
    }

    radice = cJSON_ParseWithLength(testo, lunghezza);
    if (radice == NULL) {
        return segnala(errore, OPENCARD_ERR_JSON);
    }

    /* Un backup arriva da fuori, quindi lo schema si controlla. */
    esito = opencard_carte_da_json(radice, 1, out, errore);
    cJSON_Delete(radice);
    if (esito != OPENCARD_OK) {
        return esito;
    }

    /* Id assenti, non validi o ripetuti: si rinumera tutto, altrimenti due
     * carte diverse finirebbero sullo stesso id e modificarne una toccherebbe
     * l'altra. */
    for (i = 0; i < out->n && !rinumera; i++) {
        if (out->carte[i].id < 1) {
            rinumera = 1;
            break;
        }
        for (j = 0; j < i; j++) {
            if (out->carte[j].id == out->carte[i].id) {
                rinumera = 1;
                break;
            }
        }
    }
    if (rinumera) {
        for (i = 0; i < out->n; i++) {
            out->carte[i].id = (int)i + 1;
        }
    }

    return OPENCARD_OK;
}

/* ----------------------------------------------------- esportare e importare */

#define NOME_ELENCO "opencard.json"

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
        return OPENCARD_FILE_ARCHIVIO;
    }
    return OPENCARD_FILE_JSON;
}

/* Un nome di foto che resta dentro la cartella: niente barre, niente "..",
 * niente file nascosti. Un archivio costruito male potrebbe portare
 * `../../altro`, e un file scritto fuori dalla cartella sarebbe un guaio. */
static int nome_sicuro(const char *nome)
{
    return nome[0] != '\0' && nome[0] != '.' && strchr(nome, '/') == NULL
           && strchr(nome, '\\') == NULL && strstr(nome, "..") == NULL;
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

static void scrivi_foto(const char *nome, const unsigned char *dati, size_t quanti)
{
    char percorso[1100];
    FILE *f;

    /* La cartella la crea la piattaforma alla prima foto: su un telefono
     * appena installato può non esserci ancora. */
    mkdir(opencard_store_cartella_foto(), 0700);
    if (!percorso_foto(nome, percorso, sizeof(percorso))
        || (f = fopen(percorso, "wb")) == NULL) {
        return;
    }
    fwrite(dati, 1, quanti, f);
    fclose(f);
}

/* L'archivio: l'elenco e le foto che esistono davvero, una volta ciascuna. */
static opencard_esito scrivi_archivio(const opencard_lista *tutte,
                                      const char *esportato_il,
                                      unsigned char **fuori, size_t *fuori_n,
                                      opencard_errore *errore)
{
    opencard_zip_voce *voci;
    size_t n = 0, i, j, k;
    cJSON *radice;
    char *elenco;
    opencard_esito esito;

    radice = (cJSON *)opencard_carte_a_json(tutte, esportato_il != NULL ? esportato_il : "");
    elenco = radice != NULL ? cJSON_Print(radice) : NULL;
    cJSON_Delete(radice);
    voci = calloc(1 + 2 * tutte->n, sizeof(*voci));
    if (elenco == NULL || voci == NULL) {
        cJSON_free(elenco);
        free(voci);
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }

    snprintf(voci[n].nome, sizeof(voci[n].nome), "%s", NOME_ELENCO);
    voci[n].dati = (unsigned char *)elenco;
    voci[n].quanti = strlen(elenco);
    n++;

    for (i = 0; i < tutte->n; i++) {
        const char *foto[2] = {tutte->carte[i].foto_fronte, tutte->carte[i].foto_retro};

        for (j = 0; j < 2; j++) {
            int gia = 0;

            if (!nome_sicuro(foto[j])) {
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
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
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
        return OPENCARD_OK;
    }
    esito = opencard_cripto_cifra(chiaro, chiaro_n, password, byte, quanti, errore);
    /* In chiaro qui dentro ci sono i numeri delle tessere e le foto. */
    crypto_wipe(chiaro, chiaro_n);
    free(chiaro);
    return esito;
}

/* Le carte di un archivio, con le foto rimesse a posto. */
static opencard_esito leggi_archivio(const unsigned char *dati, size_t quanti,
                                     opencard_lista *out, opencard_errore *errore)
{
    opencard_zip_lettura lettura;
    opencard_esito esito;
    const opencard_zip_voce *elenco = NULL;
    size_t i, j;

    memset(out, 0, sizeof(*out));
    esito = opencard_zip_leggi(dati, quanti, &lettura, errore);
    if (esito != OPENCARD_OK) {
        return esito;
    }
    for (i = 0; i < lettura.n && elenco == NULL; i++) {
        const char *base = strrchr(lettura.voci[i].nome, '/');

        base = base != NULL ? base + 1 : lettura.voci[i].nome;
        if (strcmp(base, NOME_ELENCO) == 0) {
            elenco = &lettura.voci[i];
        }
    }
    if (elenco == NULL) {
        opencard_zip_libera(&lettura);
        return segnala(errore, OPENCARD_ERR_FORMATO);
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
        const char *base = strrchr(lettura.voci[i].nome, '/');
        int nominata = 0;

        base = base != NULL ? base + 1 : lettura.voci[i].nome;
        if (!nome_sicuro(base) || strcmp(base, NOME_ELENCO) == 0) {
            continue;
        }
        for (j = 0; j < out->n && !nominata; j++) {
            nominata = strcmp(out->carte[j].foto_fronte, base) == 0
                       || strcmp(out->carte[j].foto_retro, base) == 0;
        }
        if (nominata) {
            scrivi_foto(base, lettura.voci[i].dati, lettura.voci[i].quanti);
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
    int aggiungi = 0;

    if (quante != NULL) {
        *quante = 0;
    }
    if (dati == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    /* Un file vuoto non è un backup. Va fermato qui: più sotto una lunghezza
     * a zero vorrebbe dire "misura la stringa", su un buffer senza NUL. */
    if (quanti == 0) {
        return segnala(errore, OPENCARD_ERR_JSON);
    }
    if (opencard_cripto_e_cifrato(dati, quanti)) {
        if (password == NULL || password[0] == '\0') {
            return segnala(errore, OPENCARD_ERR_PASSWORD);
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
        esito = leggi_archivio(aperto, aperto_n, &lista, errore);
    } else if (opencard_csv_e_csv(aperto, aperto_n)) {
        esito = opencard_csv_leggi(aperto, aperto_n, &lista, errore);
        if (esito == OPENCARD_OK && sostituisci) {
            for (i = 0; i < lista.n; i++) {
                lista.carte[i].id = (int)i + 1;
            }
        }
        aggiungi = !sostituisci;
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
