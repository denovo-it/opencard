/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 *
 * Il pacchetto cifrato con password.
 *
 * Serve al backup su file: chi vuole mette una password e il file non si legge
 * più a occhio nudo. Senza password il backup resta il JSON di sempre, perché
 * un file leggibile è una delle cose per cui OpenCard esiste.
 *
 * Dentro c'è XChaCha20-Poly1305 per cifrare e autenticare, e Argon2id per
 * ricavare la chiave dalla password. Li fa monocypher, che sta in
 * third-party/monocypher: un file solo, senza dipendenze, dominio pubblico.
 *
 * Il formato è uguale su Android e su iPhone perché lo scrive questo file: un
 * backup fatto con un telefono si apre con l'altro.
 */

#ifndef OPENCARD_CRIPTO_H
#define OPENCARD_CRIPTO_H

#include <stddef.h>

#include "store.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Il pacchetto comincia con questi byte, che servono a riconoscerlo senza
 * provare a decifrarlo. */
#define OPENCARD_CRIPTO_MAGIA "OCENC1"
#define OPENCARD_CRIPTO_MAGIA_N 6

/* Quanto lavoro fa Argon2id per ricavare la chiave. Sono i valori con cui si
 * scrive; leggendo si usano quelli scritti nel file, entro il tetto qui
 * sotto. 32 MiB e tre passate sono il compromesso fra un telefono del 2015 e
 * una password corta. */
#define OPENCARD_CRIPTO_BLOCCHI 32768   /* in KiB: 32 MiB */
#define OPENCARD_CRIPTO_PASSATE 3

/* Tetto su quello che un file può chiedere. Senza, un file scritto apposta
 * potrebbe far allocare gigabyte al telefono di chi lo apre. */
#define OPENCARD_CRIPTO_BLOCCHI_MAX 262144  /* 256 MiB */

/* Vero se i byte cominciano con la magia, cioè se questo è un backup cifrato.
 * Non prova la password e non alloca niente: serve alla UI per sapere se
 * deve chiederla. */
int opencard_cripto_e_cifrato(const unsigned char *dati, size_t n);

/* Cifra. `password` non può essere vuota: senza password il backup si scrive
 * in chiaro, e la scelta la fa chi chiama, non questa funzione.
 *
 * Chi chiama libera il risultato con opencard_cripto_free().
 */
opencard_esito opencard_cripto_cifra(const unsigned char *dati, size_t n,
                                     const char *password,
                                     unsigned char **fuori, size_t *fuori_n,
                                     opencard_errore *errore);

/* Decifra. Password sbagliata e pacchetto manomesso danno lo stesso codice,
 * OPENCARD_ERR_PASSWORD: dall'esterno non si distinguono, ed è giusto così.
 *
 * Il risultato ha sempre uno zero in fondo, oltre ai `fuori_n` byte
 * dichiarati, così si può passare direttamente alle funzioni che vogliono
 * una stringa.
 */
opencard_esito opencard_cripto_decifra(const unsigned char *dati, size_t n,
                                       const char *password,
                                       unsigned char **fuori, size_t *fuori_n,
                                       opencard_errore *errore);

/* Le stesse due operazioni con una chiave gia' pronta di 32 byte, senza
 * passare da Argon2.
 *
 * Servono al file dei dati, che si riscrive a ogni salvataggio: ricavare la
 * chiave da una password costa quasi mezzo secondo, e mezzo secondo per
 * accendere una stella non si puo' guardare. La chiave la tiene la
 * piattaforma, nel portachiavi di sistema.
 */
#define OPENCARD_CRIPTO_CHIAVE_N 32

opencard_esito opencard_cripto_cifra_chiave(const unsigned char *dati, size_t n,
                                            const unsigned char *chiave,
                                            unsigned char **fuori, size_t *fuori_n,
                                            opencard_errore *errore);

opencard_esito opencard_cripto_decifra_chiave(const unsigned char *dati, size_t n,
                                              const unsigned char *chiave,
                                              unsigned char **fuori, size_t *fuori_n,
                                              opencard_errore *errore);

void opencard_cripto_free(unsigned char *dati);

#ifdef __cplusplus
}
#endif

#endif /* OPENCARD_CRIPTO_H */
