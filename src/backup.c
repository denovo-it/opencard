/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 */

#include "backup.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
     * perche' qui nessuno garantisce che dopo l'ultimo byte ci sia uno zero. */
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
