// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCCore.h"

#include <stdlib.h>
#include <string.h>

#include "backup.h"
#include "codegen.h"
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
+ (NSError *)erroreDa:(const opencard_errore *)errore
{
    char messaggio[512];
    opencard_errore_testo(errore, messaggio, sizeof(messaggio));

    NSString *testo = messaggio[0] != '\0'
        ? [NSString stringWithUTF8String:messaggio]
        : @"Errore imprevisto.";

    return [NSError errorWithDomain:OCDominioErrore
                               code:(errore ? errore->codice : -1)
                           userInfo:@{NSLocalizedDescriptionKey: testo}];
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

/// Recupera il file delle carte se è rimasto in una posizione usata da
/// un'installazione precedente: aggiornando l'app il sistema conserva i dati,
/// ma sotto un'altra directory, e senza questo l'app partirebbe vuota.
+ (void)recuperaDatiEsistentiIn:(NSString *)directory
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *attuale = [directory stringByAppendingPathComponent:@"opencard.json"];

    if ([fm fileExistsAtPath:attuale]) {
        return;
    }

    NSArray<NSString *> *possibili = @[
        [directory stringByAppendingPathComponent:@"flet/opencard.json"],
        [directory stringByAppendingPathComponent:@"flet/app/opencard.json"],
    ];

    for (NSString *candidato in possibili) {
        if ([fm fileExistsAtPath:candidato]) {
            // Si copia, non si sposta: se qualcosa va storto l'originale resta.
            [fm copyItemAtPath:candidato toPath:attuale error:NULL];
            return;
        }
    }
}

+ (BOOL)apriConErrore:(NSError **)errore
{
    NSString *directory = [self directoryDati];
    [self recuperaDatiEsistentiIn:directory];

    opencard_errore guasto = {OPENCARD_ERR_IO, 0, {0}, 0};

    if (opencard_store_init(directory.UTF8String) != OPENCARD_OK) {
        guasto.codice = OPENCARD_ERR_ARGOMENTI;
        [self riporta:errore da:&guasto];
        return NO;
    }
    if (opencard_init_db() != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return NO;
    }
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
    carta.qrcode = card->is_qrcode != 0;
    carta.colore = [NSString stringWithUTF8String:colore];
    carta.coloreScelto = card->color[0] != '\0';
    carta.usaEGetta = card->disposable != 0;
    carta.preferita = card->favorite != 0;
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

#pragma mark - Scrittura

+ (NSInteger)inserisci:(NSString *)etichetta
                codice:(NSString *)codice
                qrcode:(BOOL)qrcode
                colore:(NSString *)colore
             usaEGetta:(BOOL)usaEGetta
                errore:(NSError **)errore
{
    opencard_errore guasto;
    int nuovo = 0;

    if (opencard_insert(etichetta.UTF8String, codice.UTF8String, qrcode ? 1 : 0,
                        colore.length > 0 ? colore.UTF8String : "",
                        usaEGetta ? 1 : 0, &nuovo, &guasto) != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return -1;
    }
    return nuovo;
}

+ (BOOL)aggiorna:(NSInteger)identificativo
       etichetta:(NSString *)etichetta
          codice:(NSString *)codice
          qrcode:(BOOL)qrcode
          colore:(NSString *)colore
       usaEGetta:(BOOL)usaEGetta
          errore:(NSError **)errore
{
    opencard_errore guasto;

    if (opencard_update((int)identificativo, etichetta.UTF8String, codice.UTF8String,
                        qrcode ? 1 : 0, colore.length > 0 ? colore.UTF8String : "",
                        usaEGetta ? 1 : 0, &guasto) != OPENCARD_OK) {
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

/// Il core restituisce i pixel in memoria, tre byte per pixel: qui diventano
/// un'immagine, senza passare da un file.
+ (UIImage *)immaginePerCodice:(NSString *)codice qrcode:(BOOL)qrcode errore:(NSError **)errore
{
    unsigned char *pixel = NULL;
    char messaggio[128] = {0};
    int larghezza = 0, altezza = 0;

    int esito = opencard_render_bitmap(codice.UTF8String,
                                       qrcode ? OPENCARD_QRCODE : OPENCARD_BARCODE,
                                       &pixel, &larghezza, &altezza,
                                       messaggio, sizeof(messaggio));
    if (esito != 0 || pixel == NULL) {
        if (errore != NULL) {
            NSString *testo = messaggio[0] != '\0'
                ? [NSString stringWithUTF8String:messaggio]
                : @"Codice non generabile.";
            *errore = [NSError errorWithDomain:OCDominioErrore
                                          code:esito
                                      userInfo:@{NSLocalizedDescriptionKey: testo}];
        }
        return nil;
    }

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

+ (NSData *)esportaBackup:(NSError **)errore
{
    NSDateFormatter *formato = [NSDateFormatter new];
    formato.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssXXX";
    formato.locale = [NSLocale localeWithLocaleIdentifier:@"it_IT"];

    char *testo = NULL;
    opencard_errore guasto;

    if (opencard_backup_esporta([formato stringFromDate:[NSDate date]].UTF8String,
                                &testo, &guasto) != OPENCARD_OK || testo == NULL) {
        [self riporta:errore da:&guasto];
        return nil;
    }

    NSData *dati = [NSData dataWithBytes:testo length:strlen(testo)];
    opencard_backup_free(testo);
    return dati;
}

+ (NSInteger)ripristinaBackup:(NSData *)dati errore:(NSError **)errore
{
    opencard_lista lista;
    opencard_errore guasto;

    /* Un file vuoto ha bytes a NULL e lunghezza zero: al core arriverebbe il
     * segnale "conta col terminatore" su un buffer che non ce l'ha. Si ferma
     * qui, con lo stesso messaggio di un file che non è un backup. */
    if (dati.length == 0 || dati.bytes == NULL) {
        opencard_errore vuoto = {OPENCARD_ERR_JSON, 0, {0}, 0};
        [self riporta:errore da:&vuoto];
        return -1;
    }
    if (opencard_backup_leggi((const char *)dati.bytes, dati.length, &lista, &guasto) != OPENCARD_OK) {
        [self riporta:errore da:&guasto];
        return -1;
    }
    if (opencard_replace_all(&lista, &guasto) != OPENCARD_OK) {
        opencard_lista_free(&lista);
        [self riporta:errore da:&guasto];
        return -1;
    }

    NSInteger quante = (NSInteger)lista.n;
    opencard_lista_free(&lista);
    return quante;
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
