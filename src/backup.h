/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 *
 * Esportazione e lettura dei backup.
 *
 * Il backup ha lo stesso formato del file dei dati, con due campi in piu'
 * (`app` e `exported_at`) per riconoscerlo a colpo d'occhio quando lo si apre.
 *
 * Il core produce e consuma byte: chi sceglie dove salvare e cosa aprire e' il
 * selettore di file di sistema, che sta nella parte nativa.
 */

#ifndef OPENCARD_BACKUP_H
#define OPENCARD_BACKUP_H

#include <stddef.h>

#include "store.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Nome proposto per il file, tipo "opencard-20260811.json".
 * `oggi` e' la data in formato YYYYMMDD: la sa la piattaforma, che conosce il
 * fuso orario dell'utente. */
void opencard_backup_nome(const char *oggi, char *out, size_t out_size);

/* Contenuto del file di backup, come testo UTF-8 terminato da NUL.
 * `esportato_il` e' l'istante in formato ISO 8601, dato dalla piattaforma.
 *
 * Gli id restano quelli che hanno: il colore di una carta che non ne ha uno
 * scelto a mano si calcola dall'id, e rinumerare cambierebbe quei colori.
 *
 * Chi chiama libera il risultato con opencard_backup_free().
 */
opencard_esito opencard_backup_esporta(const char *esportato_il, char **testo,
                                       opencard_errore *errore);

void opencard_backup_free(char *testo);

/* Le carte contenute in un backup. Non tocca il file dei dati: sta a chi chiama
 * decidere se confermare con opencard_replace_all().
 *
 * `lunghezza` a 0 fa misurare la stringa da sola.
 */
opencard_esito opencard_backup_leggi(const char *testo, size_t lunghezza,
                                     opencard_lista *out, opencard_errore *errore);

#ifdef __cplusplus
}
#endif

#endif /* OPENCARD_BACKUP_H */
