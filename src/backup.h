/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 *
 * Esportazione e lettura dei backup.
 *
 * Il backup ha lo stesso formato del file dei dati, con due campi in più
 * (`app` e `exported_at`) per riconoscerlo a colpo d'occhio quando lo si apre.
 *
 * Il core produce e consuma byte: chi sceglie dove salvare e cosa aprire è il
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
 * `oggi` è la data in formato YYYYMMDD: la sa la piattaforma, che conosce il
 * fuso orario dell'utente. */
void opencard_backup_nome(const char *oggi, char *out, size_t out_size);

/* Contenuto del file di backup, come testo UTF-8 terminato da NUL.
 * `esportato_il` è l'istante in formato ISO 8601, dato dalla piattaforma.
 *
 * Gli id restano quelli che hanno: il colore di una carta che non ne ha uno
 * scelto a mano si calcola dall'id, e rinumerare cambierebbe quei colori.
 *
 * Chi chiama libera il risultato con opencard_backup_free().
 */
opencard_esito opencard_backup_esporta(const char *esportato_il, char **testo,
                                       opencard_errore *errore);

void opencard_backup_free(char *testo);

/* Lo stesso backup, chiuso con una password: quello che esce è il pacchetto
 * cifrato di cripto.h, byte e non testo. Password vuota torna
 * OPENCARD_ERR_ARGOMENTI, perché la scelta di cifrare o no la fa la UI e qui
 * non si indovina.
 *
 * Chi chiama libera con opencard_cripto_free().
 */
opencard_esito opencard_backup_esporta_cifrato(const char *esportato_il,
                                               const char *password,
                                               unsigned char **byte, size_t *quanti,
                                               opencard_errore *errore);

/* Le carte da un file di backup che può essere in chiaro o cifrato.
 *
 * Il file cifrato senza password torna OPENCARD_ERR_PASSWORD: è così che la UI
 * capisce che deve chiederla, invece di dover riconoscere il formato da sé.
 */
opencard_esito opencard_backup_leggi_file(const unsigned char *dati, size_t quanti,
                                          const char *password,
                                          opencard_lista *out,
                                          opencard_errore *errore);

/* ----------------------------------------------------- esportare e importare
 *
 * Tutto il giro del file che l'utente salva o apre, uguale sui due telefoni:
 * le interfacce scelgono il formato e la password, e scrivono o leggono i
 * byte con il selettore di sistema. Fino alla 1.0.6 lo facevano loro, ognuna
 * con il suo ZIP e il suo CSV. */

typedef enum {
    /* ZIP con opencard.json e le foto: il formato consigliato. */
    OPENCARD_FORMATO_ARCHIVIO = 0,
    /* CSV di Catima: niente foto e niente usa e getta, ma lo leggono altre app. */
    OPENCARD_FORMATO_CSV = 1
} opencard_formato;

/* Quello che un file sembra, per scegliere la domanda da fare prima di
 * importarlo: un CSV chiede se aggiungere o sostituire, un file cifrato la
 * password, gli altri la conferma della sostituzione. */
typedef enum {
    OPENCARD_FILE_JSON = 0,     /* il backup dei tempi prima delle foto, o altro */
    OPENCARD_FILE_ARCHIVIO = 1,
    OPENCARD_FILE_CSV = 2,
    OPENCARD_FILE_CIFRATO = 3
} opencard_tipo_file;

opencard_tipo_file opencard_file_tipo(const unsigned char *dati, size_t quanti);

/* Il file da salvare, con tutte le carte. Con `password` non vuota esce chiuso
 * dalla cassaforte di cripto.h, archivio intero, foto comprese: lo ZIP da solo
 * cifra male. Le foto nominate da una carta ma sparite dal disco si saltano,
 * e una foto nominata da due carte entra una volta.
 * `esportato_il` è l'istante ISO 8601, dato dalla piattaforma.
 * Chi chiama libera con opencard_cripto_free().
 */
opencard_esito opencard_esporta(opencard_formato formato, const char *esportato_il,
                                const char *password,
                                unsigned char **byte, size_t *quanti,
                                opencard_errore *errore);

/* Legge un file salvato con opencard_esporta(), o un backup JSON, o un CSV di
 * Catima, e lo scrive nel file dei dati in una scrittura sola.
 *
 * Archivio e JSON sostituiscono le carte che ci sono. Il CSV si aggiunge in
 * fondo, oppure con `sostituisci` prende il loro posto. Le foto dell'archivio
 * tornano nella cartella delle foto con il loro nome, e solo quelle che una
 * carta nomina: il nome non può portare fuori dalla cartella.
 *
 * Un file cifrato senza password torna OPENCARD_ERR_PASSWORD. Un archivio
 * senza opencard.json torna OPENCARD_ERR_FORMATO. In `quante`, se non è NULL,
 * le carte entrate.
 */
opencard_esito opencard_importa(const unsigned char *dati, size_t quanti,
                                const char *password, int sostituisci,
                                int *quante, opencard_errore *errore);

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
