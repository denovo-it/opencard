/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 *
 * Il CSV, nel formato di Catima.
 *
 * Serve per uscire e per entrare: chi lascia OpenCard deve potersi portare via
 * le carte in un formato che un'altra app legge, e chi arriva da Catima deve
 * poter entrare senza ribattere venti tessere a mano. Il formato è documentato
 * in `docs/EXPORT_FORMAT.md` del loro repository.
 *
 * Il file ha tre tabelle separate da righe vuote: i gruppi, le carte, e i
 * collegamenti fra le due. I gruppi non li abbiamo, quindi in uscita quella
 * tabella è vuota e in entrata si salta.
 *
 * Quello che si perde passando di qui, ed è il motivo per cui l'archivio resta
 * il modo consigliato: le foto, che nel CSV non ci stanno, e la distinzione fra
 * carta normale e usa e getta, che nel loro formato non esiste.
 *
 * Fino alla 1.0.6 lo scrivevano e lo leggevano le due interfacce, ognuna a
 * modo suo: adesso sta qui, e un CSV esce uguale dai due telefoni.
 */

#ifndef OPENCARD_CSV_H
#define OPENCARD_CSV_H

#include <stddef.h>

#include "store.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Vero se i byte cominciano come un CSV di Catima: la versione "2" in testa e
 * la colonna "_id" nei primi 200 byte. Non alloca niente. */
int opencard_csv_e_csv(const unsigned char *dati, size_t quanti);

/* Il CSV delle carte, in UTF-8, terminato da NUL. `*quanti` non conta il NUL.
 * Chi chiama libera con free(). */
opencard_esito opencard_csv_scrivi(const opencard_lista *lista, char **testo,
                                   size_t *quanti, opencard_errore *errore);

/* Le carte di un CSV. Gli id restano a 0: li assegna chi le scrive nel file
 * dei dati. Una riga senza nome o senza codice si salta. Chi chiama libera
 * con opencard_lista_free(). */
opencard_esito opencard_csv_leggi(const unsigned char *dati, size_t quanti,
                                  opencard_lista *out, opencard_errore *errore);

#ifdef __cplusplus
}
#endif

#endif /* OPENCARD_CSV_H */
