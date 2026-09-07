/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 *
 * Lo ZIP del backup: l'elenco delle carte e le foto in un file solo.
 *
 * Android lo fa con `java.util.zip`, che sta nella libreria di sistema; iPhone
 * una libreria per lo ZIP non ce l'ha, e questo è il motivo per cui il formato
 * si scrive qui invece che nelle due interfacce. Il file che esce è lo stesso,
 * quindi un archivio fatto con un telefono si apre con l'altro.
 *
 * Niente password: quella la mette la cassaforte in cripto.c, che chiude tutto
 * l'archivio. Lo ZIP la cifratura ce l'avrebbe, ed è vecchia e rotta.
 *
 * Fuori restano zip64, i volumi divisi e i commenti: un backup di tessere non
 * arriva a quattro gigabyte.
 */

#ifndef OPENCARD_ARCHIVIO_H
#define OPENCARD_ARCHIVIO_H

#include <stddef.h>

#include "store.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Un file dentro l'archivio. In scrittura i byte li presta chi chiama; in
 * lettura li alloca opencard_zip_leggi() e li libera opencard_zip_libera(). */
typedef struct {
    char nome[256];
    unsigned char *dati;
    size_t quanti;
} opencard_zip_voce;

typedef struct {
    opencard_zip_voce *voci;
    size_t n;
} opencard_zip_lettura;

/* Vero se i byte cominciano come uno ZIP. Non lo apre e non alloca niente. */
int opencard_zip_e_archivio(const unsigned char *dati, size_t quanti);

/* Scrive l'archivio in memoria. Chi chiama libera con opencard_zip_free(). */
opencard_esito opencard_zip_scrivi(const opencard_zip_voce *voci, size_t n,
                                   unsigned char **fuori, size_t *fuori_n,
                                   opencard_errore *errore);

/* Legge un archivio. Le voci escono nell'ordine in cui stanno nell'indice. */
opencard_esito opencard_zip_leggi(const unsigned char *dati, size_t quanti,
                                  opencard_zip_lettura *out,
                                  opencard_errore *errore);

void opencard_zip_libera(opencard_zip_lettura *lettura);
void opencard_zip_free(unsigned char *dati);

#ifdef __cplusplus
}
#endif

#endif /* OPENCARD_ARCHIVIO_H */
