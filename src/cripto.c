/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 *
 * Il pacchetto cifrato: come è fatto sta scritto in cripto.h.
 *
 * Disposizione dei byte, tutti i numeri in little endian:
 *
 *   0   6   "OCENC1"
 *   6   1   versione del formato, 1
 *   7   1   come si ricava la chiave: 1 = Argon2id
 *   8   4   passate
 *  12   4   blocchi di memoria, in KiB
 *  16  16   sale
 *  32  24   nonce
 *  56  16   firma (MAC)
 *  72   n   testo cifrato
 *
 * I primi 56 byte entrano nel calcolo della firma come dati aggiuntivi: chi
 * cambia le passate o il sale per far lavorare meno la macchina di chi apre
 * si ritrova la firma che non torna.
 */

#include "cripto.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "third-party/monocypher/monocypher.h"

#define SALE_N   16
#define NONCE_N  24
#define MAC_N    16
#define CHIAVE_N 32
#define INTESTAZIONE_N 56
#define TESTA_N  (INTESTAZIONE_N + MAC_N)   /* 72 */

#define KDF_ARGON2ID 1
#define KDF_CHIAVE   2   /* chiave gia' pronta, nessun passaggio */

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

static void scrivi32(unsigned char *out, unsigned int valore)
{
    out[0] = (unsigned char)(valore & 0xFF);
    out[1] = (unsigned char)((valore >> 8) & 0xFF);
    out[2] = (unsigned char)((valore >> 16) & 0xFF);
    out[3] = (unsigned char)((valore >> 24) & 0xFF);
}

static unsigned int leggi32(const unsigned char *dati)
{
    return (unsigned int)dati[0]
           | ((unsigned int)dati[1] << 8)
           | ((unsigned int)dati[2] << 16)
           | ((unsigned int)dati[3] << 24);
}

/* Byte a caso dal sistema. Android e iPhone hanno tutti e due /dev/urandom, e
 * questa è l'unica cosa che il core prende da fuori: se non si può leggere si
 * torna un errore, non si tira a indovinare con l'orologio. */
static int byte_a_caso(unsigned char *out, size_t n)
{
    FILE *f = fopen("/dev/urandom", "rb");
    size_t letti;

    if (f == NULL) {
        return 0;
    }
    letti = fread(out, 1, n, f);
    fclose(f);
    return letti == n;
}

/* La chiave dalla password. `blocchi` è in KiB e va già controllato. */
static int chiave_da_password(const char *password, const unsigned char *sale,
                              unsigned int passate, unsigned int blocchi,
                              unsigned char *chiave)
{
    crypto_argon2_config config;
    crypto_argon2_inputs inputs;
    crypto_argon2_extras extras = { NULL, NULL, 0, 0 };
    void *area;

    area = malloc((size_t)blocchi * 1024u);
    if (area == NULL) {
        return 0;
    }

    config.algorithm = CRYPTO_ARGON2_ID;
    config.nb_blocks = blocchi;
    config.nb_passes = passate;
    config.nb_lanes  = 1;

    inputs.pass      = (const uint8_t *)password;
    inputs.pass_size = (uint32_t)strlen(password);
    inputs.salt      = sale;
    inputs.salt_size = SALE_N;

    crypto_argon2(chiave, CHIAVE_N, area, config, inputs, extras);

    /* L'area di lavoro contiene tracce della password: si azzera prima di
     * restituirla al sistema. */
    crypto_wipe(area, (size_t)blocchi * 1024u);
    free(area);
    return 1;
}

int opencard_cripto_e_cifrato(const unsigned char *dati, size_t n)
{
    if (dati == NULL || n < TESTA_N) {
        return 0;
    }
    return memcmp(dati, OPENCARD_CRIPTO_MAGIA, OPENCARD_CRIPTO_MAGIA_N) == 0;
}

opencard_esito opencard_cripto_cifra(const unsigned char *dati, size_t n,
                                     const char *password,
                                     unsigned char **fuori, size_t *fuori_n,
                                     opencard_errore *errore)
{
    unsigned char chiave[CHIAVE_N];
    unsigned char *pacchetto;
    size_t totale;

    if (fuori == NULL || fuori_n == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    *fuori = NULL;
    *fuori_n = 0;
    if (dati == NULL || password == NULL || password[0] == '\0') {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }

    totale = TESTA_N + n;
    pacchetto = (unsigned char *)malloc(totale);
    if (pacchetto == NULL) {
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }

    memcpy(pacchetto, OPENCARD_CRIPTO_MAGIA, OPENCARD_CRIPTO_MAGIA_N);
    pacchetto[6] = 1;
    pacchetto[7] = KDF_ARGON2ID;
    scrivi32(pacchetto + 8, OPENCARD_CRIPTO_PASSATE);
    scrivi32(pacchetto + 12, OPENCARD_CRIPTO_BLOCCHI);

    if (!byte_a_caso(pacchetto + 16, SALE_N)
        || !byte_a_caso(pacchetto + 32, NONCE_N)) {
        free(pacchetto);
        return segnala(errore, OPENCARD_ERR_IO);
    }

    if (!chiave_da_password(password, pacchetto + 16, OPENCARD_CRIPTO_PASSATE,
                            OPENCARD_CRIPTO_BLOCCHI, chiave)) {
        free(pacchetto);
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }

    crypto_aead_lock(pacchetto + TESTA_N, pacchetto + INTESTAZIONE_N, chiave,
                     pacchetto + 32, pacchetto, INTESTAZIONE_N, dati, n);
    crypto_wipe(chiave, sizeof(chiave));

    *fuori = pacchetto;
    *fuori_n = totale;
    if (errore != NULL) {
        errore->codice = OPENCARD_OK;
    }
    return OPENCARD_OK;
}

opencard_esito opencard_cripto_decifra(const unsigned char *dati, size_t n,
                                       const char *password,
                                       unsigned char **fuori, size_t *fuori_n,
                                       opencard_errore *errore)
{
    unsigned char chiave[CHIAVE_N];
    unsigned char *chiaro;
    unsigned int passate, blocchi;
    size_t quanti;

    if (fuori == NULL || fuori_n == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    *fuori = NULL;
    *fuori_n = 0;
    if (dati == NULL || password == NULL || password[0] == '\0') {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    if (!opencard_cripto_e_cifrato(dati, n)) {
        return segnala(errore, OPENCARD_ERR_FORMATO);
    }
    if (dati[6] != 1 || dati[7] != KDF_ARGON2ID) {
        /* Pacchetto di una versione più nuova: chi apre non sa come è fatto. */
        if (errore != NULL) {
            errore->schema_trovato = dati[6];
        }
        return segnala(errore, OPENCARD_ERR_SCHEMA);
    }

    passate = leggi32(dati + 8);
    blocchi = leggi32(dati + 12);
    /* Un pacchetto che chiede più memoria del tetto, o zero passate, non si
     * apre: sarebbe un modo per bloccare il telefono di chi lo riceve. */
    if (passate == 0 || passate > 16
        || blocchi < 8 || blocchi > OPENCARD_CRIPTO_BLOCCHI_MAX) {
        return segnala(errore, OPENCARD_ERR_FORMATO);
    }

    quanti = n - TESTA_N;
    /* Uno zero in fondo, che non fa parte del contenuto: il chiamante può
     * passare il risultato a chi si aspetta una stringa. */
    chiaro = (unsigned char *)malloc(quanti + 1);
    if (chiaro == NULL) {
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }

    if (!chiave_da_password(password, dati + 16, passate, blocchi, chiave)) {
        free(chiaro);
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }

    if (crypto_aead_unlock(chiaro, dati + INTESTAZIONE_N, chiave, dati + 32,
                           dati, INTESTAZIONE_N, dati + TESTA_N, quanti) != 0) {
        crypto_wipe(chiave, sizeof(chiave));
        crypto_wipe(chiaro, quanti);
        free(chiaro);
        return segnala(errore, OPENCARD_ERR_PASSWORD);
    }
    crypto_wipe(chiave, sizeof(chiave));

    chiaro[quanti] = '\0';
    *fuori = chiaro;
    *fuori_n = quanti;
    if (errore != NULL) {
        errore->codice = OPENCARD_OK;
    }
    return OPENCARD_OK;
}

opencard_esito opencard_cripto_cifra_chiave(const unsigned char *dati, size_t n,
                                            const unsigned char *chiave,
                                            unsigned char **fuori, size_t *fuori_n,
                                            opencard_errore *errore)
{
    unsigned char *pacchetto;
    size_t totale;

    if (fuori == NULL || fuori_n == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    *fuori = NULL;
    *fuori_n = 0;
    if (dati == NULL || chiave == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }

    totale = TESTA_N + n;
    pacchetto = (unsigned char *)malloc(totale);
    if (pacchetto == NULL) {
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }

    memcpy(pacchetto, OPENCARD_CRIPTO_MAGIA, OPENCARD_CRIPTO_MAGIA_N);
    pacchetto[6] = 1;
    pacchetto[7] = KDF_CHIAVE;
    /* Niente passate e niente blocchi: la chiave arriva gia' fatta. Il sale
     * resta a zero, non serve a nulla senza un passaggio da password. */
    memset(pacchetto + 8, 0, 8 + SALE_N);

    if (!byte_a_caso(pacchetto + 32, NONCE_N)) {
        free(pacchetto);
        return segnala(errore, OPENCARD_ERR_IO);
    }

    crypto_aead_lock(pacchetto + TESTA_N, pacchetto + INTESTAZIONE_N, chiave,
                     pacchetto + 32, pacchetto, INTESTAZIONE_N, dati, n);

    *fuori = pacchetto;
    *fuori_n = totale;
    if (errore != NULL) {
        errore->codice = OPENCARD_OK;
    }
    return OPENCARD_OK;
}

opencard_esito opencard_cripto_decifra_chiave(const unsigned char *dati, size_t n,
                                              const unsigned char *chiave,
                                              unsigned char **fuori, size_t *fuori_n,
                                              opencard_errore *errore)
{
    unsigned char *chiaro;
    size_t quanti;

    if (fuori == NULL || fuori_n == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    *fuori = NULL;
    *fuori_n = 0;
    if (dati == NULL || chiave == NULL) {
        return segnala(errore, OPENCARD_ERR_ARGOMENTI);
    }
    if (!opencard_cripto_e_cifrato(dati, n)) {
        return segnala(errore, OPENCARD_ERR_FORMATO);
    }
    if (dati[6] != 1 || dati[7] != KDF_CHIAVE) {
        return segnala(errore, OPENCARD_ERR_SCHEMA);
    }

    quanti = n - TESTA_N;
    chiaro = (unsigned char *)malloc(quanti + 1);
    if (chiaro == NULL) {
        return segnala(errore, OPENCARD_ERR_MEMORIA);
    }
    if (crypto_aead_unlock(chiaro, dati + INTESTAZIONE_N, chiave, dati + 32,
                           dati, INTESTAZIONE_N, dati + TESTA_N, quanti) != 0) {
        crypto_wipe(chiaro, quanti);
        free(chiaro);
        return segnala(errore, OPENCARD_ERR_PASSWORD);
    }

    chiaro[quanti] = '\0';
    *fuori = chiaro;
    *fuori_n = quanti;
    if (errore != NULL) {
        errore->codice = OPENCARD_OK;
    }
    return OPENCARD_OK;
}

void opencard_cripto_free(unsigned char *dati)
{
    free(dati);
}
