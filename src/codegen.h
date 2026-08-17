/* Generazione dei codici per OpenCard: primo pezzo del core condiviso.
 *
 * Compila con zint, senza niente di specifico per iOS o Android.
 */

#ifndef OPENCARD_CODEGEN_H
#define OPENCARD_CODEGEN_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Tipo di codice chiesto dall'utente, come lo salva il db. */
typedef enum {
    OPENCARD_BARCODE = 0,
    OPENCARD_QRCODE = 1
} opencard_tipo;

/* Spezza il codice in blocchi di tre, per leggerlo e confrontarlo a occhio.
 *
 * Da che parte si conta dipende da cosa si legge:
 *   - tutto cifre: da destra, come le migliaia.  "8001234567897" -> "9 998 601 028 602"
 *   - alfanumerico: da sinistra, perche' si legge in avanti.  "A1B2C3D4" -> "YKS 4W4 9Q"
 * Chi ha gia' una sua punteggiatura (trattini, spazi, URL) resta com'e'.
 *
 * Scrive in out, terminato da NUL. Ritorna la lunghezza scritta, oppure -1 se
 * out e' troppo piccolo. Serve al massimo len + len/3 + 2 byte.
 */
int opencard_grouped_code(const char *code, char *out, size_t out_size);

/* Simbologia zint adatta al codice: EAN-13, EAN-8 o UPC-A se il numero ha la
 * lunghezza giusta, altrimenti Code128. Per i QR ritorna sempre BARCODE_QRCODE.
 *
 * Le tessere dei supermercati sono quasi sempre EAN/UPC, e renderizzarle con la
 * loro simbologia da' le barre di guardia e i moduli piu' larghi che i lettori
 * laser da cassa leggono meglio.
 *
 * Ritorna una costante BARCODE_* di zint.
 */
int opencard_symbology(const char *code, opencard_tipo tipo);

/* Genera il codice e restituisce il bitmap in memoria, tre byte per pixel (RGB).
 *
 * E' questa la funzione che useranno le due app: su Android il buffer va in un
 * android.graphics.Bitmap, su iOS in un CGImage. Nessuna delle due passa da un
 * file PNG, e libpng non esiste nell'NDK.
 *
 * Chi chiama libera il buffer con opencard_free_bitmap().
 * Ritorna 0 se e' andata, altrimenti il codice di errore di zint.
 */
int opencard_render_bitmap(const char *code, opencard_tipo tipo,
                           unsigned char **pixel, int *larghezza, int *altezza,
                           char *errore, size_t errore_len);

void opencard_free_bitmap(unsigned char *pixel);

/* Genera il codice e scrive un PNG nel percorso indicato.
 *
 * Serve al banco di prova su host, dove il PNG si rilegge con zxing-cpp.
 * Richiede uno zint compilato con libpng, quindi non e' disponibile nelle
 * build per Android.
 * Ritorna 0 se e' andata, altrimenti il codice di errore di zint.
 * In caso di errore, se errore_len > 0, ci mette il messaggio di zint.
 */
int opencard_write_png(const char *code, opencard_tipo tipo, const char *percorso,
                       char *errore, size_t errore_len);

#ifdef __cplusplus
}
#endif

#endif /* OPENCARD_CODEGEN_H */
