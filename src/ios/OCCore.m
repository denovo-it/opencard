// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCCore.h"

#import "OCChiaveDati.h"

#include <stdlib.h>
#include <string.h>

#include "backup.h"
#include "codegen.h"
#include "cripto.h"
#include "store.h"
#include "transfer.h"

static NSString *const OCDominioErrore = @"srl.denovo.opencard";

/// Libera i pixel quando CoreGraphics ha finito con l'immagine.
/// Deve essere una funzione, non un blocco: CGDataProviderCreateWithData vuole
/// un puntatore a funzione.
static void OCLiberaPixel(void *info, const void *dati, size_t dimensione)
{
    (void)info;
    (void)dimensione;
    opencard_free_bitmap((unsigned char *)dati);
}

@implementation OCCarta
@end

@implementation OCCore

#pragma mark - Errori

/// Trasforma un errore del core in un NSError col messaggio già pronto.
/// Il messaggio da mostrare, nella lingua in cui sta parlando l'app.
///
/// Il core dà la chiave del testo e gli argomenti già scritti
/// (`opencard_errore_scomponi()`); la frase sta nei file di lingua insieme a
/// tutte le altre. Un errore nuovo si aggiunge nel core e nei JSON delle
/// lingue, non qui.
+ (NSString *)testoDi:(const opencard_errore *)errore
{
    opencard_errore_parti parti;

    opencard_errore_scomponi(errore, &parti);
    NSString *formato = NSLocalizedString(@(parti.chiave), nil);
    return [NSString stringWithFormat:formato,
            [NSString stringWithUTF8String:parti.primo] ?: @"",
            [NSString stringWithUTF8String:parti.secondo] ?: @""];
}

+ (NSError *)erroreDa:(const opencard_errore *)errore
{
    return [NSError errorWithDomain:OCDominioErrore
                               code:(errore ? errore->codice : -1)
                           userInfo:@{NSLocalizedDescriptionKey: [self testoDi:errore]}];
}

+ (void)riporta:(NSError **)destinazione da:(const opencard_errore *)errore
{
    if (destinazione != NULL) {
        *destinazione = [self erroreDa:errore];
    }
}

#pragma mark - Apertura

/// Dove stanno i dati: Application Support, che il sistema non svuota e che
/// non compare fra i documenti dell'utente.
///
/// Da qui il file rientra nel backup del telefono, iCloud compreso, ed è la
/// scelta di partenza: chi cambia iPhone ritrova le carte senza esportarle a
/// mano. Da Impostazioni si può spegnere, e allora sulla cartella finisce
/// NSURLIsExcludedFromBackupKey. Su Android la scelta di partenza è l'opposta.
/// La privacy policy su denovo.srl dichiara tutte e due le cose.
+ (NSString *)directoryDati
{
    NSArray<NSString *> *percorsi = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *directory = percorsi.firstObject;

    if (directory == nil) {
        directory = NSTemporaryDirectory();
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return directory;
}

+ (BOOL)apriConErrore:(NSError **)errore
{
    NSString *directory = [self directoryDati];

    opencard_errore guasto = {OPENCARD_ERR_IO, 0, {0}, 0};

    if (opencard_store_init(directory.UTF8String) != OPENCARD_OK) {
        guasto.codice = OPENCARD_ERR_ARGOMENTI;
        [self riporta:errore da:&guasto];
        return NO;
    }
    // La chiave prima di qualsiasi lettura e prima che il file venga creato:
    // un file cifrato senza chiave non si apre, e l'app direbbe che è rotto.
    // Se il portachiavi non risponde si va avanti in chiaro, come prima.
    [self impostaChiaveDati:[OCChiaveDati chiave]];

    if (opencard_init_db() != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return NO;
    }
    // Le foto rimaste dalle versioni che eliminando una carta non le
    // cancellavano. Se il file non si legge restano dove sono.
    opencard_pulisci_foto(NULL);
    return YES;
}

+ (BOOL)primoAvvio
{
    return opencard_is_first_run() != 0;
}

+ (void)segnaPrimoAvvioFatto
{
    opencard_mark_first_run_done();
}

#pragma mark - Lettura

+ (OCCarta *)cartaDa:(const opencard_card *)card
{
    char colore[OPENCARD_COLOR_MAX];
    opencard_card_color(card, colore, sizeof(colore));

    OCCarta *carta = [OCCarta new];
    carta.identificativo = card->id;
    carta.etichetta = [NSString stringWithUTF8String:card->label];
    carta.codice = [NSString stringWithUTF8String:card->code];
    carta.qrcode = opencard_simbologia_quadrata(card->simbologia) != 0;
    carta.colore = [NSString stringWithUTF8String:colore];
    carta.coloreScelto = card->color[0] != '\0';
    carta.usaEGetta = card->disposable != 0;
    carta.preferita = card->favorite != 0;
    carta.simbologia = (NSInteger)card->simbologia;
    carta.note = [NSString stringWithUTF8String:card->note];
    carta.scadenza = [NSString stringWithUTF8String:card->scadenza];
    carta.saldo = [NSString stringWithUTF8String:card->saldo];
    carta.fotoFronte = [NSString stringWithUTF8String:card->foto_fronte];
    carta.fotoRetro = [NSString stringWithUTF8String:card->foto_retro];
    return carta;
}

+ (NSArray<OCCarta *> *)carteDaLista:(const opencard_lista *)lista
{
    NSMutableArray<OCCarta *> *carte = [NSMutableArray arrayWithCapacity:lista->n];
    for (size_t i = 0; i < lista->n; i++) {
        [carte addObject:[self cartaDa:&lista->carte[i]]];
    }
    return carte;
}

+ (NSArray<OCCarta *> *)tutteLeCarte:(NSError **)errore
{
    opencard_lista lista;
    opencard_errore guasto;

    if (opencard_get_all(&lista, &guasto) != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return nil;
    }
    NSArray<OCCarta *> *carte = [self carteDaLista:&lista];
    opencard_lista_free(&lista);
    return carte;
}

+ (NSArray<OCCarta *> *)carteDelGruppo:(BOOL)usaEGetta errore:(NSError **)errore
{
    opencard_lista lista;
    opencard_errore guasto;

    if (opencard_get_gruppo(usaEGetta ? 1 : 0, &lista, &guasto) != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return nil;
    }
    NSArray<OCCarta *> *carte = [self carteDaLista:&lista];
    opencard_lista_free(&lista);
    return carte;
}

+ (NSArray<OCCarta *> *)cartePreferite:(NSError **)errore
{
    opencard_lista lista;
    opencard_errore guasto;

    if (opencard_get_preferite(&lista, &guasto) != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return nil;
    }
    NSArray<OCCarta *> *carte = [self carteDaLista:&lista];
    opencard_lista_free(&lista);
    return carte;
}

+ (BOOL)impostaPreferita:(NSInteger)identificativo
                 accesa:(BOOL)accesa
                 errore:(NSError **)errore
{
    opencard_errore guasto;

    if (opencard_set_favorite((int)identificativo, accesa ? 1 : 0, &guasto) != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return NO;
    }
    return YES;
}

+ (OCCarta *)cartaConId:(NSInteger)identificativo errore:(NSError **)errore
{
    opencard_card card;
    opencard_errore guasto;

    if (opencard_get((int)identificativo, &card, &guasto) != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return nil;
    }
    return [self cartaDa:&card];
}

+ (NSInteger)prossimoId
{
    return opencard_next_id();
}

+ (NSString *)salvaFoto:(NSData *)jpeg
                   id:(NSInteger)identificativo
               fronte:(BOOL)fronte
               errore:(NSError **)errore
{
    char nome[OPENCARD_FOTO_MAX];
    opencard_errore guasto;

    if (opencard_foto_salva((int)identificativo, fronte ? 1 : 0, jpeg.bytes, jpeg.length,
                            nome, sizeof(nome), &guasto) != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return nil;
    }
    return [NSString stringWithUTF8String:nome];
}

+ (NSString *)dataDaMostrare:(NSString *)scadenza
{
    char mostrata[OPENCARD_DATA_MAX];

    opencard_data_da_mostrare(scadenza.UTF8String, mostrata, sizeof(mostrata));
    return [NSString stringWithUTF8String:mostrata] ?: @"";
}

#pragma mark - Scrittura

+ (BOOL)salva:(NSInteger)identificativo
       nuova:(BOOL)nuova
   etichetta:(NSString *)etichetta
      codice:(NSString *)codice
  simbologia:(NSInteger)simbologia
      colore:(NSString *)colore
   usaEGetta:(BOOL)usaEGetta
   preferita:(BOOL)preferita
        note:(NSString *)note
    scadenza:(NSString *)scadenza
       saldo:(NSString *)saldo
  fotoFronte:(NSString *)fotoFronte
   fotoRetro:(NSString *)fotoRetro
      errore:(NSError **)errore
{
    opencard_card carta;
    opencard_errore guasto;

    memset(&carta, 0, sizeof(carta));
    carta.id = (int)identificativo;
    snprintf(carta.label, sizeof(carta.label), "%s", etichetta.UTF8String ?: "");
    snprintf(carta.code, sizeof(carta.code), "%s", codice.UTF8String ?: "");
    snprintf(carta.color, sizeof(carta.color), "%s", colore.UTF8String ?: "");
    snprintf(carta.note, sizeof(carta.note), "%s", note.UTF8String ?: "");
    snprintf(carta.scadenza, sizeof(carta.scadenza), "%s", scadenza.UTF8String ?: "");
    snprintf(carta.saldo, sizeof(carta.saldo), "%s", saldo.UTF8String ?: "");
    snprintf(carta.foto_fronte, sizeof(carta.foto_fronte), "%s", fotoFronte.UTF8String ?: "");
    snprintf(carta.foto_retro, sizeof(carta.foto_retro), "%s", fotoRetro.UTF8String ?: "");
    /* Un taglio può cadere a metà di una lettera accentata. */
    opencard_utf8_ripara(carta.label);
    opencard_utf8_ripara(carta.code);
    opencard_utf8_ripara(carta.note);
    opencard_utf8_ripara(carta.saldo);
    carta.simbologia = (opencard_simbologia)simbologia;
    carta.disposable = usaEGetta ? 1 : 0;
    carta.favorite = preferita ? 1 : 0;

    if (opencard_salva(&carta, nuova ? 1 : 0, &guasto) != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return NO;
    }
    return YES;
}

+ (BOOL)elimina:(NSInteger)identificativo errore:(NSError **)errore
{
    opencard_errore guasto;

    if (opencard_delete((int)identificativo, &guasto) != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return NO;
    }
    return YES;
}

+ (BOOL)riordina:(BOOL)usaEGetta identificativi:(NSArray<NSNumber *> *)ids errore:(NSError **)errore
{
    opencard_errore guasto;
    size_t quanti = ids.count;
    int *elenco = malloc((quanti > 0 ? quanti : 1) * sizeof(int));

    if (elenco == NULL) {
        return NO;
    }
    for (size_t i = 0; i < quanti; i++) {
        elenco[i] = ids[i].intValue;
    }

    BOOL esito = opencard_reorder(usaEGetta ? 1 : 0, elenco, quanti, &guasto) == OPENCARD_OK;
    free(elenco);

    if (!esito) {
        [self riporta:errore da:&guasto];
    }
    return esito;
}

#pragma mark - Codici

+ (NSString *)colorePerId:(NSInteger)identificativo
{
    char colore[OPENCARD_COLOR_MAX];
    opencard_color_for_id((int)identificativo, colore, sizeof(colore));
    return [NSString stringWithUTF8String:colore];
}

+ (NSString *)codiceRaggruppato:(NSString *)codice
{
    char uscita[OPENCARD_CODE_MAX * 2];

    if (opencard_grouped_code(codice.UTF8String, uscita, sizeof(uscita)) < 0) {
        return codice;
    }
    return [NSString stringWithUTF8String:uscita];
}

/// I pixel del core, tre byte l'uno, diventano un'immagine senza passare da un
/// file. La memoria la libera CoreGraphics quando ha finito.
+ (UIImage *)immagineDaPixel:(unsigned char *)pixel
                   larghezza:(int)larghezza
                     altezza:(int)altezza
{
    size_t byte = (size_t)larghezza * (size_t)altezza * 3;
    CGDataProviderRef fornitore = CGDataProviderCreateWithData(NULL, pixel, byte,
                                                               OCLiberaPixel);

    CGColorSpaceRef spazio = CGColorSpaceCreateDeviceRGB();
    CGImageRef immagine = CGImageCreate(larghezza, altezza, 8, 24, larghezza * 3,
                                        spazio, kCGBitmapByteOrderDefault,
                                        fornitore, NULL, NO, kCGRenderingIntentDefault);
    CGColorSpaceRelease(spazio);
    CGDataProviderRelease(fornitore);

    if (immagine == NULL) {
        return nil;
    }
    UIImage *risultato = [UIImage imageWithCGImage:immagine];
    CGImageRelease(immagine);
    return risultato;
}

#pragma mark - Backup

+ (NSString *)nomeBackup
{
    NSDateFormatter *formato = [NSDateFormatter new];
    formato.dateFormat = @"yyyyMMdd";
    formato.locale = [NSLocale localeWithLocaleIdentifier:@"it_IT"];

    char nome[64];
    opencard_backup_nome([formato stringFromDate:[NSDate date]].UTF8String,
                         nome, sizeof(nome));
    return [NSString stringWithUTF8String:nome];
}

+ (OCTipoFile)tipoFile:(NSData *)dati
{
    return (OCTipoFile)opencard_file_tipo((const unsigned char *)dati.bytes, dati.length);
}

+ (long long)fileMassimo
{
    return OPENCARD_FILE_MAX;
}

+ (NSString *)testoFileTroppoGrande
{
    opencard_errore errore = {OPENCARD_ERR_TROPPO_GRANDE, 0, {0}, 0};
    return [self testoDi:&errore];
}

+ (NSData *)esportaCsv:(BOOL)csv password:(NSString *)password errore:(NSError **)errore
{
    NSDateFormatter *formato = [NSDateFormatter new];
    formato.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssXXX";
    formato.locale = [NSLocale localeWithLocaleIdentifier:@"it_IT"];

    unsigned char *byte = NULL;
    size_t quanti = 0;
    opencard_errore guasto;

    if (opencard_esporta(csv ? OPENCARD_FORMATO_CSV : OPENCARD_FORMATO_ARCHIVIO,
                         [formato stringFromDate:[NSDate date]].UTF8String,
                         password.UTF8String ?: "", &byte, &quanti,
                         &guasto) != OPENCARD_OK || byte == NULL) {
        [self riporta:errore da:&guasto];
        return nil;
    }
    NSData *fuori = [NSData dataWithBytes:byte length:quanti];
    opencard_cripto_free(byte);
    return fuori;
}

+ (NSInteger)importa:(NSData *)dati
            password:(NSString *)password
         sostituisci:(BOOL)sostituisci
              errore:(NSError **)errore
{
    opencard_errore guasto;
    int quante = 0;

    /* Un file vuoto ha bytes a NULL: lo ferma il core, con lo stesso
     * messaggio di un file che non è un backup. */
    if (opencard_importa((const unsigned char *)dati.bytes ?: (const unsigned char *)"",
                         dati.length, password.UTF8String ?: "", sostituisci ? 1 : 0,
                         &quante, &guasto) != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return -1;
    }
    return quante;
}


#pragma mark - Simbologia

/// I nomi da mostrare, da `opencard_simbologia_etichetta()`: non le sigle con
/// cui la simbologia si scrive nel file, `code128` e `ean13`, che servono al
/// formato e non si fanno leggere. L'ordine è quello dell'enum, quindi l'indice
/// qui dentro è il numero da salvare nella carta.
+ (NSArray<NSString *> *)nomiSimbologie
{
    static NSArray<NSString *> *nomi = nil;
    static dispatch_once_t unaVolta;
    dispatch_once(&unaVolta, ^{
        NSMutableArray<NSString *> *dalCore = [NSMutableArray array];
        for (int s = 0; s < OPENCARD_SIM_QUANTE; s++) {
            [dalCore addObject:@(opencard_simbologia_etichetta((opencard_simbologia)s))];
        }
        nomi = [dalCore copy];
    });
    return nomi;
}

/// Vero per le due che si disegnano come quadrato e non come barre.
+ (NSInteger)simbologiaAutomatica:(NSString *)codice
{
    return (NSInteger)opencard_simbologia_automatica(codice.UTF8String ?: "");
}

+ (NSInteger)simbologiaIndovinata:(NSString *)codice qrcode:(BOOL)qrcode
{
    return (NSInteger)opencard_simbologia_indovinata(codice.UTF8String, qrcode ? 1 : 0);
}

+ (BOOL)codiceSta:(NSString *)codice simbologia:(NSInteger)simbologia
{
    return opencard_codice_sta(codice.UTF8String,
                               (opencard_simbologia)simbologia) != 0;
}

/// Il core restituisce i pixel in memoria, tre byte per pixel: qui diventano
/// un'immagine, senza passare da un file. Il tipo lo dice la simbologia.
+ (UIImage *)immaginePerCodice:(NSString *)codice
                    simbologia:(NSInteger)simbologia
                        errore:(NSError **)errore
{
    unsigned char *pixel = NULL;
    char messaggio[128] = {0};
    int larghezza = 0, altezza = 0;

    int esito = opencard_render_bitmap_simbologia(codice.UTF8String,
                                                  (opencard_simbologia)simbologia,
                                                  &pixel, &larghezza, &altezza,
                                                  messaggio, sizeof(messaggio));
    if (esito != 0 || pixel == NULL) {
        if (errore != NULL) {
            NSString *testo = messaggio[0] != '\0'
                ? [NSString stringWithUTF8String:messaggio]
                : NSLocalizedString(@"codice_non_generabile", nil);
            *errore = [NSError errorWithDomain:OCDominioErrore
                                          code:esito
                                      userInfo:@{NSLocalizedDescriptionKey: testo}];
        }
        return nil;
    }
    return [self immagineDaPixel:pixel larghezza:larghezza altezza:altezza];
}

#pragma mark - Cifratura

+ (void)impostaChiaveDati:(NSData *)chiave
{
    if (chiave.length == OPENCARD_CRIPTO_CHIAVE_N) {
        opencard_store_chiave((const unsigned char *)chiave.bytes);
    } else {
        opencard_store_chiave(NULL);
    }
}

+ (BOOL)carteNelBackup
{
    NSURL *dove = [NSURL fileURLWithPath:[self directoryDati]];
    NSNumber *fuori = nil;

    if (![dove getResourceValue:&fuori forKey:NSURLIsExcludedFromBackupKey error:NULL]) {
        return YES;
    }
    return !fuori.boolValue;
}

+ (void)metticiLeCarteNelBackup:(BOOL)dentro
{
    NSURL *dove = [NSURL fileURLWithPath:[self directoryDati]];

    // Il segno sta sulla cartella e vale per quello che c'è dentro: il file
    // delle carte e le foto, che sono file a parte.
    [dove setResourceValue:@(!dentro) forKey:NSURLIsExcludedFromBackupKey error:NULL];
}

+ (BOOL)azzeraTutto:(NSError **)errore
{
    opencard_lista vuota;
    opencard_errore guasto;

    /* Una scrittura sola: cancellare carta per carta riscriverebbe il file
     * tante volte quante sono le carte, e ognuna è un momento in cui il
     * telefono può spegnersi lasciando metà lavoro fatto. */
    memset(&vuota, 0, sizeof(vuota));
    if (opencard_replace_all(&vuota, &guasto) != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return NO;
    }
    return YES;
}

#pragma mark - Passaggio delle carte con i QR

/// Gli array di stringhe come li vuole il core: puntatori a C string.
/// Chi chiama libera con OCLiberaPezzi().
static const char **OCPezziDaArray(NSArray<NSString *> *letti, size_t *quanti)
{
    *quanti = letti.count;
    if (letti.count == 0) {
        return NULL;
    }
    const char **pezzi = calloc(letti.count, sizeof(char *));
    if (pezzi == NULL) {
        *quanti = 0;
        return NULL;
    }
    for (NSUInteger i = 0; i < letti.count; i++) {
        pezzi[i] = strdup(letti[i].UTF8String);
    }
    return pezzi;
}

static void OCLiberaPezzi(const char **pezzi, size_t quanti)
{
    if (pezzi == NULL) {
        return;
    }
    for (size_t i = 0; i < quanti; i++) {
        free((void *)pezzi[i]);
    }
    free((void *)pezzi);
}

+ (NSArray<NSString *> *)codiciDaMostrare:(NSError **)errore
{
    opencard_trasf_pezzi pezzi;
    opencard_errore guasto;

    if (opencard_trasf_prepara(&pezzi, &guasto) != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return nil;
    }

    NSMutableArray<NSString *> *codici = [NSMutableArray arrayWithCapacity:pezzi.n];
    for (size_t i = 0; i < pezzi.n; i++) {
        [codici addObject:[NSString stringWithUTF8String:pezzi.pezzi[i]]];
    }
    opencard_trasf_pezzi_free(&pezzi);
    return codici;
}

+ (BOOL)statoRaccolta:(NSArray<NSString *> *)letti
             ricevuti:(NSInteger *)ricevuti
               totale:(NSInteger *)totale
               errore:(NSError **)errore
{
    opencard_errore guasto;
    size_t quanti = 0;
    int presi = 0, quanti_totali = 0;

    const char **pezzi = OCPezziDaArray(letti, &quanti);
    opencard_esito esito = opencard_trasf_stato(pezzi, quanti, &presi, &quanti_totali, &guasto);
    OCLiberaPezzi(pezzi, quanti);

    if (esito != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return NO;
    }
    if (ricevuti != NULL) {
        *ricevuti = presi;
    }
    if (totale != NULL) {
        *totale = quanti_totali;
    }
    return YES;
}

+ (NSArray<OCCarta *> *)carteRicevute:(NSArray<NSString *> *)letti errore:(NSError **)errore
{
    opencard_lista lista;
    opencard_errore guasto;
    size_t quanti = 0;

    const char **pezzi = OCPezziDaArray(letti, &quanti);
    opencard_esito esito = opencard_trasf_leggi(pezzi, quanti, &lista, &guasto);
    OCLiberaPezzi(pezzi, quanti);

    if (esito != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return nil;
    }
    NSArray<OCCarta *> *carte = [self carteDaLista:&lista];
    opencard_lista_free(&lista);
    return carte;
}

+ (NSInteger)applicaRicevute:(NSArray<NSString *> *)letti
                      azzera:(BOOL)azzera
                      errore:(NSError **)errore
{
    opencard_errore guasto;
    size_t quanti = 0;
    int quante = 0;

    const char **pezzi = OCPezziDaArray(letti, &quanti);
    opencard_esito esito = opencard_trasf_applica(pezzi, quanti, azzera ? 1 : 0,
                                                  &quante, &guasto);
    OCLiberaPezzi(pezzi, quanti);

    if (esito != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return -1;
    }
    return quante;
}

@end
