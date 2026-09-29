/* Generazione dei codici per OpenCard: primo pezzo del core condiviso.
 *
 * Compila con zint, senza niente di specifico per iOS o Android.
 */

#ifndef OPENCARD_CODEGEN_H
#define OPENCARD_CODEGEN_H

#include <stddef.h>

#include "store.h"      /* opencard_simbologia */

#ifdef __cplusplus
extern "C" {
#endif

/* Spezza il codice in blocchi di tre, per leggerlo e confrontarlo a occhio.
 *
 * Da che parte si conta dipende da cosa si legge:
 *   - tutto cifre: da destra, come le migliaia.  "8001234567897" -> "9 998 601 028 602"
 *   - alfanumerico: da sinistra, perché si legge in avanti.  "A1B2C3D4" -> "YKS 4W4 9Q"
 * Chi ha già una sua punteggiatura (trattini, spazi, URL) resta com'è.
 *
 * Scrive in out, terminato da NUL. Ritorna la lunghezza scritta, oppure -1 se
 * out è troppo piccolo. Serve al massimo len + len/3 + 2 byte.
 */
int opencard_grouped_code(const char *code, char *out, size_t out_size);

/* La costante zint di una simbologia, oppure -1 se il numero non è una
 * simbologia. Le simbologie sono quelle di store.h: qui c'è solo la tabella
 * che le lega a zint, perché è l'unico posto che conosce zint. */
int opencard_zint_da_simbologia(opencard_simbologia simbologia);

/* Se un codice si può disegnare in una simbologia, senza disegnarlo.
 *
 * Serve al modulo di inserimento: una scelta che non porta da nessuna parte va
 * detta mentre si salva, non scoperta più tardi aprendo la carta e trovando il
 * posto del codice vuoto. Un contenuto da QR, per esempio, in Code 128 non ci
 * sta: quella simbologia arriva a 99 caratteri di simbolo e basta.
 *
 * Ritorna 1 se ci sta, 0 se no. Il messaggio da mostrare lo compone la UI, che
 * sa in che lingua sta parlando.
 */
int opencard_codice_sta(const char *code, opencard_simbologia simbologia);

/* La simbologia che sceglie l'app quando il modulo è su Automatico: quella che
 * si ricava dal codice, e se il codice non ci sta il QR, che tiene tutto.
 * Automatico non deve mai finire in un errore, perché è la voce di chi non
 * vuole scegliere. */
opencard_simbologia opencard_simbologia_automatica(const char *code);

/* Genera il codice nella simbologia data e restituisce il bitmap in memoria,
 * tre byte per pixel (RGB): su Android il buffer va in un
 * android.graphics.Bitmap, su iOS in un CGImage, senza passare da un PNG
 * (libpng non esiste nell'NDK). Chi chiama libera con opencard_free_bitmap().
 * Ritorna 0 se è andata, altrimenti il codice di errore di zint.
 *
 * Un codice che non sta in quella simbologia (un EAN-13 di dodici cifre, un
 * Codabar senza le lettere agli estremi) torna un errore di zint con il testo
 * in `errore`: la scelta di cosa dire all'utente resta alla UI. */
int opencard_render_bitmap_simbologia(const char *code, opencard_simbologia simbologia,
                                      unsigned char **pixel, int *larghezza,
                                      int *altezza, char *errore, size_t errore_len);

void opencard_free_bitmap(unsigned char *pixel);

/* Genera il codice nella simbologia data e scrive un PNG nel percorso indicato.
 *
 * Serve al banco di prova su host, dove il PNG si rilegge con zxing-cpp.
 * Richiede uno zint compilato con libpng, quindi non è disponibile nelle
 * build per Android.
 * Ritorna 0 se è andata, altrimenti il codice di errore di zint.
 * In caso di errore, se errore_len > 0, ci mette il messaggio di zint.
 */
int opencard_write_png(const char *code, opencard_simbologia simbologia, const char *percorso,
                       char *errore, size_t errore_len);

#ifdef __cplusplus
}
#endif

#endif /* OPENCARD_CODEGEN_H */
