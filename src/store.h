/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 *
 * Persistenza delle carte in un file JSON.
 *
 * Il file è leggibile a occhio nudo, si copia via e si rimette a posto senza
 * strumenti: il file dei dati e il file di backup hanno lo stesso formato.
 */

#ifndef OPENCARD_STORE_H
#define OPENCARD_STORE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 2: la carta ha la simbologia per esteso, le note, la scadenza, il saldo e
 * i nomi delle due foto.
 *
 * 3: stessi campi, ma la simbologia scritta è affidabile. Le build interne del
 * 7 settembre 2026 scrivevano «code128» su tutte le carte lette da un file di
 * schema 1, anche sugli EAN, e quel valore poi si rispettava: risultato, i
 * codici a barre senza le guardie. Leggendo uno schema 2 il «code128» su un
 * codice che si indovinerebbe EAN o UPC si considera non scritto.
 *
 * Un file più vecchio si legge; uno più nuovo no, perché riscrivendolo si
 * perderebbe quello che non si conosce. */
#define OPENCARD_SCHEMA_VERSION 3

/* Limiti generosi rispetto all'uso reale: una tessera fedeltà ha un nome
 * corto e un codice di poche decine di caratteri. Sono fissi per non spargere
 * malloc in tutto il core; chi supera il limite viene troncato, non corrotto. */
#define OPENCARD_LABEL_MAX 128
#define OPENCARD_CODE_MAX  512
#define OPENCARD_COLOR_MAX 8     /* "#RRGGBB" più il terminatore */
#define OPENCARD_NOTE_MAX  512   /* una nota, non un diario */
#define OPENCARD_SALDO_MAX 32    /* testo libero: "12,50 €", "340 punti" */
#define OPENCARD_DATA_MAX  11    /* "AAAA-MM-GG" più il terminatore */
#define OPENCARD_FOTO_MAX  64    /* nome del file, non il percorso: le foto
                                  * stanno in una cartella dentro i dati
                                  * dell'app, e nel JSON viaggia solo il nome */

/* Le simbologie che l'app sa disegnare. L'ordine non conta, i numeri sì: il
 * passaggio a QR ne scrive uno per carta, quindi vanno aggiunte in fondo e mai
 * rinumerate. Nel file JSON viaggia il nome, non il numero. */
typedef enum {
    OPENCARD_SIM_CODE128 = 0,
    OPENCARD_SIM_QR = 1,
    OPENCARD_SIM_AZTEC = 2,
    OPENCARD_SIM_CODABAR = 3,
    OPENCARD_SIM_CODE39 = 4,
    OPENCARD_SIM_CODE93 = 5,
    OPENCARD_SIM_DATAMATRIX = 6,
    OPENCARD_SIM_EAN8 = 7,
    OPENCARD_SIM_EAN13 = 8,
    OPENCARD_SIM_ITF = 9,
    OPENCARD_SIM_PDF417 = 10,
    OPENCARD_SIM_UPCA = 11,
    OPENCARD_SIM_UPCE = 12,
    OPENCARD_SIM_MICROQR = 13,
    OPENCARD_SIM_GS1_128 = 14,
    OPENCARD_SIM_DATABAR = 15,
    OPENCARD_SIM_DATABAR_ESPANSO = 16,
    OPENCARD_SIM_MSI = 17,
    OPENCARD_SIM_QUANTE = 18
} opencard_simbologia;

/* Codici di errore. Le stringhe da mostrare le compone la UI, che sa in che
 * lingua sta parlando, dai pezzi di opencard_errore_scomponi(). */
typedef enum {
    OPENCARD_OK = 0,
    OPENCARD_ERR_IO = -1,           /* il file non si legge o non si scrive */
    OPENCARD_ERR_JSON = -2,         /* il contenuto non è JSON valido */
    OPENCARD_ERR_FORMATO = -3,      /* è JSON ma non un file di OpenCard */
    OPENCARD_ERR_SCHEMA = -4,       /* schema di un'altra versione */
    OPENCARD_ERR_CARTA = -5,        /* una carta è malformata: vedi contesto */
    OPENCARD_ERR_MEMORIA = -6,
    OPENCARD_ERR_ARGOMENTI = -7,
    OPENCARD_ERR_NON_TROVATA = -8,
    /* Passaggio delle carte con i QR: vedi transfer.h */
    OPENCARD_ERR_ALTRO_TRASF = -9,      /* pezzo di un altro trasferimento */
    OPENCARD_ERR_TRASF_INCOMPLETO = -10,/* mancano dei pezzi */
    OPENCARD_ERR_TRASF_ROTTO = -11,     /* i pezzi ci sono ma non tornano */
    OPENCARD_ERR_TRASF_VERSIONE = -12,  /* scritto da una versione più nuova */
    OPENCARD_ERR_TRASF_TROPPE = -13,    /* troppe carte per stare nei QR */
    /* Backup cifrato: password sbagliata o pacchetto manomesso. I due casi
     * danno lo stesso codice apposta, non si distinguono da fuori. */
    OPENCARD_ERR_PASSWORD = -14,
    /* Il file da importare, o quello che l'esportazione produrrebbe, supera
     * OPENCARD_FILE_MAX. */
    OPENCARD_ERR_TROPPO_GRANDE = -15
} opencard_esito;

/* Il file più grande che l'importazione accetta e che l'esportazione produce:
 * lo stesso numero dalle due parti, così un backup uscito dall'app si riapre
 * sempre. Una foto salvata pesa circa 230 KB, quindi ci stanno più di cento
 * carte con fronte e retro; il tetto tiene fuori il file sbagliato, che le
 * app caricano tutto in memoria. */
#define OPENCARD_FILE_MAX (64u * 1024u * 1024u)

/* Che cosa è andato storto, per comporre un messaggio utile all'utente.
 * `posizione` conta le carte da 1, `dettaglio` può essere il nome
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
    /* Quale codice è. Il core la tiene sempre allineata a is_qrcode. */
    opencard_simbologia simbologia;
    /* Vera solo per QR e Micro QR, e il core la tiene allineata a
     * `simbologia`. Dalla 1.0.7 le interfacce non la leggono più: resta perché
     * da lei esce il campo "type" del file, che le versioni prima della 1.0.3
     * leggono ancora ripristinando un backup. */
    int is_qrcode;
    char color[OPENCARD_COLOR_MAX];     /* "" se lo decide l'id */
    int disposable;
    /* I quattro campi in più della carta. Vuoti vuol dire non compilati, e
     * nel file compaiono solo quando c'è qualcosa dentro. Le foto sono nomi
     * di file: i byte stanno in una cartella a parte, altrimenti il file dei
     * dati diventa illeggibile e il passaggio a QR impossibile. */
    char note[OPENCARD_NOTE_MAX];
    char scadenza[OPENCARD_DATA_MAX];   /* "AAAA-MM-GG" oppure "" */
    char saldo[OPENCARD_SALDO_MAX];
    char foto_fronte[OPENCARD_FOTO_MAX];
    char foto_retro[OPENCARD_FOTO_MAX];
    /* Preferita: la carta compare anche nella scheda con la stella, che sia
     * fedeltà o usa e getta. Nel file il campo c'è solo quando è accesa,
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
 * Attenzione, è la ragione per cui esiste questa funzione: la directory deve
 * essere quella dei dati dell'app, non quella del codice. */
opencard_esito opencard_store_init(const char *directory_dati);

/* La chiave con cui il file dei dati sta cifrato sul telefono.
 *
 * Trentadue byte, che la piattaforma tiene nel portachiavi di sistema:
 * Keystore su Android, Keychain su iPhone. Va data prima di leggere o
 * scrivere, subito dopo opencard_store_init().
 *
 * Senza chiave il file resta in chiaro, come nelle versioni precedenti, e
 * un file in chiaro si legge lo stesso anche dopo: la prima scrittura lo
 * converte. Al contrario no: dato che la chiave l'ha solo il telefono, un file
 * cifrato senza chiave non si apre, ed e' il punto.
 *
 * `chiave` a NULL toglie la chiave: serve alle prove.
 */
void opencard_store_chiave(const unsigned char *chiave);

/* Il file dei dati, per chi deve mostrarlo o copiarlo. */
const char *opencard_store_percorso(void);

/* La cartella delle foto, <directory dei dati>/foto. La usano l'esportazione
 * e l'importazione, che mettono le foto nell'archivio e le rimettono a posto. */
const char *opencard_store_cartella_foto(void);

/* Primo avvio: vero finché lo splash non è mai stato mostrato. */
int opencard_is_first_run(void);
void opencard_mark_first_run_done(void);

/* Crea il file dei dati se non c'è. */
opencard_esito opencard_init_db(void);

/* Lista: chi chiama la libera con opencard_lista_free(). */
void opencard_lista_free(opencard_lista *lista);

/* Tutte le carte, nell'ordine in cui vanno mostrate. */
opencard_esito opencard_get_all(opencard_lista *out, opencard_errore *errore);

/* Solo le carte di un gruppo: disposable 0 = fedeltà, 1 = usa e getta. */
opencard_esito opencard_get_gruppo(int disposable, opencard_lista *out,
                                   opencard_errore *errore);

/* Le carte preferite, dei due gruppi insieme, nell'ordine in cui stanno.
 * Se non ce n'è nessuna la lista torna vuota e la scheda con la stella non
 * si mostra. */
opencard_esito opencard_get_preferite(opencard_lista *out, opencard_errore *errore);

/* Accende o spegne la stella di una carta, lasciando tutto il resto com'è.
 * Sta a sé e non dentro opencard_update() perché la stella si tocca da un
 * punto solo, la carta aperta, dove non c'è niente altro da riscrivere. */
opencard_esito opencard_set_favorite(int id, int preferita, opencard_errore *errore);

/* Una carta sola. OPENCARD_ERR_NON_TROVATA se l'id non c'è. */
opencard_esito opencard_get(int id, opencard_card *out, opencard_errore *errore);

/* Id che avrà la prossima carta inserita: serve al form di aggiunta, che
 * mostra in anticipo il colore che la carta prenderebbe da sola. */
int opencard_next_id(void);

/* Inserisce e restituisce il nuovo id in *nuovo_id.
 * `color` può essere NULL o "": si scrive solo se diverso da quello dell'id. */
opencard_esito opencard_insert(const char *label, const char *code, int is_qrcode,
                               const char *color, int disposable,
                               int *nuovo_id, opencard_errore *errore);

opencard_esito opencard_update(int id, const char *label, const char *code,
                               int is_qrcode, const char *color, int disposable,
                               opencard_errore *errore);

opencard_esito opencard_delete(int id, opencard_errore *errore);

/* Quale simbologia sta bene a un codice: EAN-13, EAN-8 o UPC-A quando le
 * cifre tornano, QR quando lo dice il tipo, Code 128 per tutto il resto.
 *
 * La usa il form, che la propone e lascia cambiare, e la usa la lettura dei
 * file: una carta salvata prima della 1.0.3 non ha la simbologia scritta, e
 * senza questa tornerebbe un Code 128, cioe' un codice a barre senza le
 * guardie che i lettori da cassa si aspettano.
 */
opencard_simbologia opencard_simbologia_indovinata(const char *code, int is_qrcode);

/* Il nome con cui una simbologia viaggia nel JSON ("code128", "qr", ...).
 * Torna NULL se il numero non è una simbologia. */
const char *opencard_simbologia_nome(opencard_simbologia simbologia);

/* Il contrario: da nome a numero. Torna OPENCARD_SIM_QUANTE se il nome non
 * si riconosce, così chi legge un file scritto da una versione più nuova può
 * decidere da sé cosa fare invece di prendersi un valore a caso. */
opencard_simbologia opencard_simbologia_da_nome(const char *nome);

/* Il nome da mostrare all'utente ("Code 128", "QR code", ...), NULL se il
 * numero non è una simbologia. Non è quello del JSON. */
const char *opencard_simbologia_etichetta(opencard_simbologia simbologia);

/* Vero per QR e Micro QR, che si disegnano come quadrato. */
int opencard_simbologia_quadrata(opencard_simbologia simbologia);

/* Vero per i codici a barre di una riga sola: la zona bianca la vogliono solo
 * ai lati, e rimpiccioliti con il filtro si leggono lo stesso. Aztec, Data
 * Matrix, PDF417 e i due QR la vogliono tutto intorno, con i moduli uguali. */
int opencard_simbologia_una_riga(opencard_simbologia simbologia);

/* Vero per EAN e UPC, che il core disegna già con la zona bianca ai lati: agli
 * altri il margine lo lascia chi li mostra. */
int opencard_simbologia_quiete_propria(opencard_simbologia simbologia);

/* I colori fra cui l'id sceglie quello di una carta, gli stessi che il modulo
 * offre per la scelta a mano. opencard_colore() torna NULL fuori elenco. */
size_t opencard_colori_n(void);
const char *opencard_colore(size_t i);

/* Cambia la simbologia di una carta e basta. Aggiorna anche is_qrcode. */
opencard_esito opencard_set_simbologia(int id, opencard_simbologia simbologia,
                                       opencard_errore *errore);

/* Note, scadenza e saldo di una carta. NULL vuol dire "lascia com'è", ""
 * vuol dire "svuota". La scadenza vuole "AAAA-MM-GG": qualsiasi altra cosa
 * torna OPENCARD_ERR_ARGOMENTI e non scrive niente. */
opencard_esito opencard_set_dettagli(int id, const char *note,
                                     const char *scadenza, const char *saldo,
                                     opencard_errore *errore);

/* I nomi dei file delle due foto, con le stesse regole di NULL e "".
 * I file li scrive la piattaforma, in <directory dei dati>/foto. Il core li
 * cancella quando nessuna carta li nomina più: dopo opencard_delete(),
 * opencard_replace_all() e opencard_pulisci_foto(). */
opencard_esito opencard_set_foto(int id, const char *fronte, const char *retro,
                                 opencard_errore *errore);

/* Una carta dal modulo, tutta insieme, in una scrittura sola: etichetta,
 * codice, simbologia, colore, gruppo, stella, note, scadenza, saldo e foto.
 * Prima erano cinque chiamate, ognuna con la sua lettura e la sua scrittura
 * del file: se una falliva a metà la carta restava salvata a pezzi.
 *
 * Con `nuova` la carta va in fondo con il suo id, che non deve esserci già:
 * chi ha foto da salvare chiede prima opencard_next_id(), perché il nome dei
 * file lo contiene. Senza, prende il posto della carta con lo stesso id, dove
 * sta nell'ordine; OPENCARD_ERR_NON_TROVATA se non c'è.
 *
 * Il colore si tiene solo se è diverso da quello che l'id assegna da sé, come
 * in opencard_insert(). Una simbologia fuori elenco o una scadenza che non è
 * "AAAA-MM-GG" tornano OPENCARD_ERR_ARGOMENTI senza scrivere niente. */
opencard_esito opencard_salva(const opencard_card *carta, int nuova,
                              opencard_errore *errore);

/* Vero se la scadenza si può salvare: vuota, oppure "AAAA-MM-GG" di un giorno
 * che esiste. Le interfacce la chiedono prima di salvare, per dirlo con parole
 * loro. */
int opencard_data_valida(const char *testo);

/* Riscrive l'ordine di un gruppo lasciando l'altro dov'è.
 * Se gli id non sono esattamente quelli del gruppo non tocca niente: meglio un
 * riordino perso che una carta persa. */
opencard_esito opencard_reorder(int disposable, const int *ids, size_t n,
                                opencard_errore *errore);

/* Sostituisce tutte le carte: la usa il ripristino di un backup, e con una
 * lista vuota l'azzeramento. Le foto che la lista non nomina vengono tolte:
 * chi ripristina un archivio scrive prima le foto e poi chiama questa. */
opencard_esito opencard_replace_all(const opencard_lista *lista,
                                    opencard_errore *errore);

/* Toglie le foto che nessuna carta nomina. Le app la chiamano all'avvio, per
 * i file rimasti dalle versioni che eliminando una carta non li cancellavano.
 * Se il file delle carte non si legge non tocca niente. */
opencard_esito opencard_pulisci_foto(opencard_errore *errore);

/* Mette le carte in fondo a quelle che ci sono, con id nuovi: la usa il
 * passaggio delle carte fra due telefoni, dove gli id di chi cede non
 * significano niente per chi riceve.
 *
 * Non guarda i doppioni: se una tessera c'è già ci finisce due volte.
 * Una lettura e una scrittura sole, non una per carta. */
opencard_esito opencard_append_all(const opencard_lista *lista,
                                   opencard_errore *errore);

/* Colore di sfondo stabile a partire dall'id. `out` almeno OPENCARD_COLOR_MAX. */
void opencard_color_for_id(int id, char *out, size_t out_size);

/* Colore di una carta: quello scelto a mano, altrimenti quello dell'id. */
void opencard_card_color(const opencard_card *card, char *out, size_t out_size);

/* Il messaggio di un errore, a pezzi, perché lo scriva ogni app nella sua
 * lingua: la chiave del testo nei file di src/lingue ("core_formato", o
 * "errore_imprevisto" per un codice che non ha un testo suo) e fino a due
 * argomenti già scritti, per i segnaposto {1:testo} e {2:testo}. Quelli che
 * non servono restano vuoti.
 *
 * Fino alla 1.0.6 le tabelle erano tre: una per app e una in italiano qui.
 * lingue/genera.py --controlla verifica che ogni chiave di questa funzione
 * esista nei JSON delle lingue. */
typedef struct {
    const char *chiave;
    char primo[OPENCARD_LABEL_MAX];
    char secondo[OPENCARD_LABEL_MAX];
} opencard_errore_parti;

void opencard_errore_scomponi(const opencard_errore *errore, opencard_errore_parti *out);

/* Ripara una stringa in posto perché diventi UTF-8 valido.
 *
 * Serve sui dati che entrano da fuori (backup, QR) e su quelli scritti dalle
 * versioni Android precedenti, che salvavano le emoji nel modified UTF-8 di
 * Java: quelle coppie si ricodificano in UTF-8 vero, così il nome non si
 * perde. I byte che non tornano diventano '?', e una sequenza tagliata in
 * fondo si toglie. Il risultato non è mai più lungo dell'originale.
 *
 * Senza questa pulizia una stringa non valida arriva ai ponti verso Java e
 * verso NSString, dove il comportamento non è definito: è lì che un backup
 * costruito apposta può far cadere l'app. */
void opencard_utf8_ripara(char *s);

/* Vero se il nome di una foto resta dentro la cartella delle foto: non vuoto,
 * niente barre, niente "..", niente file nascosti. La lettura delle carte
 * toglie i nomi che non lo sono, e l'archivio non scrive altro. */
int opencard_foto_nome_sicuro(const char *nome);

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
