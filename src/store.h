/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 *
 * Persistenza delle carte in un file JSON.
 *
 * Il file e' leggibile a occhio nudo, si copia via e si rimette a posto senza
 * strumenti: il file dei dati e il file di backup hanno lo stesso formato.
 */

#ifndef OPENCARD_STORE_H
#define OPENCARD_STORE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define OPENCARD_SCHEMA_VERSION 1

/* Limiti generosi rispetto all'uso reale: una tessera fedelta' ha un nome
 * corto e un codice di poche decine di caratteri. Sono fissi per non spargere
 * malloc in tutto il core; chi supera il limite viene troncato, non corrotto. */
#define OPENCARD_LABEL_MAX 128
#define OPENCARD_CODE_MAX  512
#define OPENCARD_COLOR_MAX 8     /* "#RRGGBB" piu' il terminatore */

/* Codici di errore. Le stringhe da mostrare le compone la UI, che sa in che
 * lingua sta parlando: opencard_errore_testo() da' la versione italiana. */
typedef enum {
    OPENCARD_OK = 0,
    OPENCARD_ERR_IO = -1,           /* il file non si legge o non si scrive */
    OPENCARD_ERR_JSON = -2,         /* il contenuto non e' JSON valido */
    OPENCARD_ERR_FORMATO = -3,      /* e' JSON ma non un file di OpenCard */
    OPENCARD_ERR_SCHEMA = -4,       /* schema di un'altra versione */
    OPENCARD_ERR_CARTA = -5,        /* una carta e' malformata: vedi contesto */
    OPENCARD_ERR_MEMORIA = -6,
    OPENCARD_ERR_ARGOMENTI = -7,
    OPENCARD_ERR_NON_TROVATA = -8,
    /* Passaggio delle carte con i QR: vedi transfer.h */
    OPENCARD_ERR_ALTRO_TRASF = -9,      /* pezzo di un altro trasferimento */
    OPENCARD_ERR_TRASF_INCOMPLETO = -10,/* mancano dei pezzi */
    OPENCARD_ERR_TRASF_ROTTO = -11,     /* i pezzi ci sono ma non tornano */
    OPENCARD_ERR_TRASF_VERSIONE = -12,  /* scritto da una versione piu' nuova */
    OPENCARD_ERR_TRASF_TROPPE = -13     /* troppe carte per stare nei QR */
} opencard_esito;

/* Che cosa e' andato storto, per comporre un messaggio utile all'utente.
 * `posizione` conta le carte da 1, `dettaglio` puo' essere il nome
 * della carta o il numero di schema trovato. */
typedef struct {
    opencard_esito codice;
    int posizione;
    char dettaglio[OPENCARD_LABEL_MAX];
    int schema_trovato;
} opencard_errore;

typedef struct {
    int id;
    char label[OPENCARD_LABEL_MAX];
    char code[OPENCARD_CODE_MAX];
    int is_qrcode;                      /* 0 = barcode, 1 = qrcode */
    char color[OPENCARD_COLOR_MAX];     /* "" se lo decide l'id */
    int disposable;
    /* Preferita: la carta compare anche nella scheda con la stella, che sia
     * fedelta' o usa e getta. Nel file il campo c'e' solo quando e' accesa,
     * quindi un file scritto da una versione precedente si legge senza
     * conversioni e nessuna carta risulta preferita. */
    int favorite;
} opencard_card;

typedef struct {
    opencard_card *carte;
    size_t n;
    size_t capacita;
} opencard_lista;

/* Dove stanno i dati. Va chiamata una volta all'avvio, prima di tutto il resto.
 * Su Android e iOS il percorso lo sa solo la piattaforma, quindi lo passa lei.
 *
 * Attenzione, e' la ragione per cui esiste questa funzione: la directory deve
 * essere quella dei dati dell'app, non quella del codice. */
opencard_esito opencard_store_init(const char *directory_dati);

/* Il file dei dati, per chi deve mostrarlo o copiarlo. */
const char *opencard_store_percorso(void);

/* Primo avvio: vero finche' lo splash non e' mai stato mostrato. */
int opencard_is_first_run(void);
void opencard_mark_first_run_done(void);

/* Crea il file dei dati se non c'e'. */
opencard_esito opencard_init_db(void);

/* Lista: chi chiama la libera con opencard_lista_free(). */
void opencard_lista_free(opencard_lista *lista);

/* Tutte le carte, nell'ordine in cui vanno mostrate. */
opencard_esito opencard_get_all(opencard_lista *out, opencard_errore *errore);

/* Solo le carte di un gruppo: disposable 0 = fedelta', 1 = usa e getta. */
opencard_esito opencard_get_gruppo(int disposable, opencard_lista *out,
                                   opencard_errore *errore);

/* Le carte preferite, dei due gruppi insieme, nell'ordine in cui stanno.
 * Se non ce n'e' nessuna la lista torna vuota e la scheda con la stella non
 * si mostra. */
opencard_esito opencard_get_preferite(opencard_lista *out, opencard_errore *errore);

/* Accende o spegne la stella di una carta, lasciando tutto il resto com'e'.
 * Sta a se' e non dentro opencard_update() perche' la stella si tocca da un
 * punto solo, la carta aperta, dove non c'e' niente altro da riscrivere. */
opencard_esito opencard_set_favorite(int id, int preferita, opencard_errore *errore);

/* Una carta sola. OPENCARD_ERR_NON_TROVATA se l'id non c'e'. */
opencard_esito opencard_get(int id, opencard_card *out, opencard_errore *errore);

/* Id che avra' la prossima carta inserita: serve al form di aggiunta, che
 * mostra in anticipo il colore che la carta prenderebbe da sola. */
int opencard_next_id(void);

/* Inserisce e restituisce il nuovo id in *nuovo_id.
 * `color` puo' essere NULL o "": si scrive solo se diverso da quello dell'id. */
opencard_esito opencard_insert(const char *label, const char *code, int is_qrcode,
                               const char *color, int disposable,
                               int *nuovo_id, opencard_errore *errore);

opencard_esito opencard_update(int id, const char *label, const char *code,
                               int is_qrcode, const char *color, int disposable,
                               opencard_errore *errore);

opencard_esito opencard_delete(int id, opencard_errore *errore);

/* Riscrive l'ordine di un gruppo lasciando l'altro dov'e'.
 * Se gli id non sono esattamente quelli del gruppo non tocca niente: meglio un
 * riordino perso che una carta persa. */
opencard_esito opencard_reorder(int disposable, const int *ids, size_t n,
                                opencard_errore *errore);

/* Sostituisce tutte le carte: la usa il ripristino di un backup. */
opencard_esito opencard_replace_all(const opencard_lista *lista,
                                    opencard_errore *errore);

/* Mette le carte in fondo a quelle che ci sono, con id nuovi: la usa il
 * passaggio delle carte fra due telefoni, dove gli id di chi cede non
 * significano niente per chi riceve.
 *
 * Non guarda i doppioni: se una tessera c'e' gia' ci finisce due volte.
 * Una lettura e una scrittura sole, non una per carta. */
opencard_esito opencard_append_all(const opencard_lista *lista,
                                   opencard_errore *errore);

/* Colore di sfondo stabile a partire dall'id. `out` almeno OPENCARD_COLOR_MAX. */
void opencard_color_for_id(int id, char *out, size_t out_size);

/* Colore di una carta: quello scelto a mano, altrimenti quello dell'id. */
void opencard_card_color(const opencard_card *card, char *out, size_t out_size);

/* Messaggio italiano per un errore, pronto da mostrare. */
void opencard_errore_testo(const opencard_errore *errore, char *out, size_t out_size);

/* Ripara una stringa in posto perche' diventi UTF-8 valido.
 *
 * Serve sui dati che entrano da fuori (backup, QR) e su quelli scritti dalle
 * versioni Android precedenti, che salvavano le emoji nel modified UTF-8 di
 * Java: quelle coppie si ricodificano in UTF-8 vero, cosi' il nome non si
 * perde. I byte che non tornano diventano '?', e una sequenza tagliata in
 * fondo si toglie. Il risultato non e' mai piu' lungo dell'originale.
 *
 * Senza questa pulizia una stringa non valida arriva ai ponti verso Java e
 * verso NSString, dove il comportamento non e' definito: e' li' che un backup
 * costruito apposta puo' far cadere l'app. */
void opencard_utf8_ripara(char *s);

/* Servizio interno, condiviso con il modulo dei backup: il file dei dati e il
 * file di backup hanno lo stesso formato, quindi la lettura e la scrittura
 * delle carte sono le stesse. I puntatori sono `void *` per non far entrare
 * cJSON in questa intestazione.
 *
 * `controlla_schema` acceso rifiuta un file scritto da un'altra versione: si
 * usa sui backup, che arrivano da fuori, non sul file dei dati.
 * `esportato_il`, se non NULL, aggiunge i campi che fanno riconoscere un backup
 * a colpo d'occhio quando lo si apre. */
opencard_esito opencard_carte_da_json(const void *radice_json, int controlla_schema,
                                      opencard_lista *out, opencard_errore *errore);
void *opencard_carte_a_json(const opencard_lista *lista, const char *esportato_il);

#ifdef __cplusplus
}
#endif

#endif /* OPENCARD_STORE_H */
