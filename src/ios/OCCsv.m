// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCCsv.h"

#import <UIKit/UIKit.h>

static NSString *const OCVersioneCsv = @"2";

@implementation OCCartaCsv
@end

@implementation OCCsv

+ (NSArray<NSString *> *)colonne
{
    return @[@"_id", @"store", @"note", @"validfrom", @"expiry", @"balance",
             @"balancetype", @"cardid", @"barcodeid", @"barcodetype",
             @"barcodeencoding", @"headercolor", @"starstatus", @"lastused",
             @"archive"];
}

/// I nomi delle simbologie come li scrive Catima, per le nostre diciotto.
/// Le cinque che loro non hanno cadono sulla più vicina che sanno disegnare.
+ (NSArray<NSString *> *)nomiCatima
{
    return @[@"CODE_128", @"QR_CODE", @"AZTEC", @"CODABAR", @"CODE_39",
             @"CODE_93", @"DATA_MATRIX", @"EAN_8", @"EAN_13", @"ITF",
             @"PDF_417", @"UPC_A", @"UPC_E", @"QR_CODE", @"CODE_128",
             @"RSS_14", @"RSS_EXPANDED", @"CODE_128"];
}

+ (BOOL)eCsv:(NSData *)dati
{
    if (dati.length < 4) {
        return NO;
    }
    NSData *testa = [dati subdataWithRange:NSMakeRange(0, MIN((NSUInteger)200, dati.length))];
    NSString *testo = [[NSString alloc] initWithData:testa encoding:NSUTF8StringEncoding];
    if (testo == nil) {
        return NO;
    }
    NSString *pulito = [testo stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [pulito hasPrefix:OCVersioneCsv] && [testo containsString:@"_id"];
}

#pragma mark - In uscita

+ (NSString *)campo:(NSString *)testo
{
    NSCharacterSet *scomodi = [NSCharacterSet characterSetWithCharactersInString:@",\"\n\r"];

    if ([testo rangeOfCharacterFromSet:scomodi].location == NSNotFound) {
        return testo;
    }
    return [NSString stringWithFormat:@"\"%@\"",
            [testo stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

/// "AAAA-MM-GG" nei millisecondi che vuole Catima, o vuoto.
+ (NSString *)millisDaData:(NSString *)data
{
    if (data.length != 10) {
        return @"";
    }
    NSDateFormatter *formato = [NSDateFormatter new];
    formato.dateFormat = @"yyyy-MM-dd";
    formato.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formato.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];

    NSDate *quando = [formato dateFromString:data];
    if (quando == nil) {
        return @"";
    }
    return [NSString stringWithFormat:@"%lld", (long long)(quando.timeIntervalSince1970 * 1000)];
}

/// Il colore come numero intero, che è come lo scrive Android.
+ (NSString *)coloreIntero:(NSString *)colore
{
    if (![colore hasPrefix:@"#"] || colore.length != 7) {
        return @"";
    }
    unsigned int valore = 0;
    NSScanner *lettore = [NSScanner scannerWithString:[colore substringFromIndex:1]];
    if (![lettore scanHexInt:&valore]) {
        return @"";
    }
    // Con l'alfa piena davanti, come Color.parseColor su Android: lo stesso
    // numero, così i due file sono identici.
    return [NSString stringWithFormat:@"%d", (int)(valore | 0xFF000000u)];
}

+ (NSData *)scrivi:(NSArray<OCCarta *> *)carte
{
    NSMutableString *righe = [NSMutableString string];
    NSArray<NSString *> *nomi = [self nomiCatima];

    [righe appendFormat:@"%@\n\n", OCVersioneCsv];
    [righe appendString:@"_id\n\n"];                    // nessun gruppo
    [righe appendFormat:@"%@\n", [[self colonne] componentsJoinedByString:@","]];

    for (OCCarta *carta in carte) {
        NSString *tipo = (carta.simbologia >= 0 && carta.simbologia < (NSInteger)nomi.count)
            ? nomi[carta.simbologia] : @"CODE_128";

        NSArray<NSString *> *valori = @[
            [NSString stringWithFormat:@"%ld", (long)carta.identificativo],
            carta.etichetta ?: @"",
            carta.note ?: @"",
            @"",                                        // validfrom, non ce l'abbiamo
            [self millisDaData:carta.scadenza ?: @""],
            carta.saldo ?: @"",
            @"",                                        // balancetype
            carta.codice ?: @"",
            @"",                                        // barcodeid
            tipo,
            @"UTF-8",
            [self coloreIntero:carta.colore ?: @""],
            carta.preferita ? @"1" : @"0",
            @"",                                        // lastused
            @"0",                                       // archive
        ];

        NSMutableArray<NSString *> *protetti = [NSMutableArray arrayWithCapacity:valori.count];
        for (NSString *valore in valori) {
            [protetti addObject:[self campo:valore]];
        }
        [righe appendFormat:@"%@\n", [protetti componentsJoinedByString:@","]];
    }
    [righe appendString:@"\ncardId,groupId\n"];
    return [righe dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - In entrata

/// Le righe di un CSV, tenendo conto delle virgolette.
///
/// Una nota può contenere virgole e andare a capo: spezzare per righe e per
/// virgole senza guardare le virgolette spaccherebbe proprio le carte con una
/// nota lunga, che sono quelle a cui chi le ha scritte tiene di più.
+ (NSArray<NSArray<NSString *> *> *)spezza:(NSString *)testo
{
    NSMutableArray<NSArray<NSString *> *> *righe = [NSMutableArray array];
    NSMutableArray<NSString *> *riga = [NSMutableArray array];
    NSMutableString *campo = [NSMutableString string];
    BOOL fraVirgolette = NO;
    NSUInteger i = 0;
    NSUInteger quanti = testo.length;

    while (i < quanti) {
        unichar c = [testo characterAtIndex:i];

        if (fraVirgolette && c == '"' && i + 1 < quanti && [testo characterAtIndex:i + 1] == '"') {
            [campo appendString:@"\""];
            i++;
        } else if (c == '"') {
            fraVirgolette = !fraVirgolette;
        } else if (!fraVirgolette && c == ',') {
            [riga addObject:[campo copy]];
            [campo setString:@""];
        } else if (!fraVirgolette && (c == '\n' || c == '\r')) {
            if (c == '\r' && i + 1 < quanti && [testo characterAtIndex:i + 1] == '\n') {
                i++;
            }
            [riga addObject:[campo copy]];
            [campo setString:@""];
            [righe addObject:[riga copy]];
            [riga removeAllObjects];
        } else {
            [campo appendFormat:@"%C", c];
        }
        i++;
    }
    [riga addObject:[campo copy]];

    BOOL qualcosa = NO;
    for (NSString *pezzo in riga) {
        if (pezzo.length > 0) {
            qualcosa = YES;
        }
    }
    if (qualcosa) {
        [righe addObject:[riga copy]];
    }
    return righe;
}

+ (NSString *)valore:(NSString *)nome
             colonne:(NSArray<NSString *> *)colonne
                riga:(NSArray<NSString *> *)riga
{
    NSUInteger dove = [colonne indexOfObject:nome];
    if (dove == NSNotFound || dove >= riga.count) {
        return @"";
    }
    return riga[dove];
}

+ (NSInteger)simbologiaDaCatima:(NSString *)nome codice:(NSString *)codice
{
    NSUInteger dove = [[self nomiCatima] indexOfObject:nome.uppercaseString];
    if (dove != NSNotFound) {
        return (NSInteger)dove;
    }
    // Un tipo che non conosciamo, o assente, si indovina dal codice come fa il
    // core: meglio un EAN riconosciuto che un Code 128 a caso.
    return [OCCore simbologiaIndovinata:codice qrcode:NO];
}

+ (NSString *)coloreDaIntero:(NSString *)testo
{
    if (testo.length == 0) {
        return @"";
    }
    long long valore = testo.longLongValue;
    return [NSString stringWithFormat:@"#%06X", (unsigned)(valore & 0xFFFFFF)];
}

+ (NSString *)dataDaMillis:(NSString *)testo
{
    if (testo.length == 0 || [testo isEqualToString:@"0"]) {
        return @"";
    }
    long long millis = testo.longLongValue;
    if (millis == 0) {
        return @"";
    }
    NSDateFormatter *formato = [NSDateFormatter new];
    formato.dateFormat = @"yyyy-MM-dd";
    formato.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formato.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];

    return [formato stringFromDate:[NSDate dateWithTimeIntervalSince1970:millis / 1000.0]];
}

/// Il saldo di Catima è un numero con accanto il tipo, il nostro è testo
/// libero: si uniscono. Zero senza tipo vuol dire "non compilato", ed è il
/// valore che mettono a tutte le carte che non hanno un saldo.
+ (NSString *)saldoLeggibile:(NSString *)quanto tipo:(NSString *)tipo
{
    NSString *pulito = [quanto stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (pulito.length == 0) {
        return @"";
    }
    NSString *numero = pulito;
    while ([numero hasSuffix:@"0"]) {
        numero = [numero substringToIndex:numero.length - 1];
    }
    if ([numero hasSuffix:@"."] || [numero hasSuffix:@","]) {
        numero = [numero substringToIndex:numero.length - 1];
    }
    if (numero.length == 0 || [numero isEqualToString:@"0"]) {
        return @"";
    }
    NSString *unita = [tipo stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return unita.length == 0 ? pulito : [NSString stringWithFormat:@"%@ %@", pulito, unita];
}

+ (NSArray<OCCartaCsv *> *)leggi:(NSData *)dati
{
    NSString *testo = [[NSString alloc] initWithData:dati encoding:NSUTF8StringEncoding];
    if (testo == nil) {
        return @[];
    }
    NSArray<NSArray<NSString *> *> *righe = [self spezza:testo];

    NSInteger intestazione = -1;
    for (NSUInteger i = 0; i < righe.count; i++) {
        if (righe[i].count > 5 && [righe[i].firstObject isEqualToString:@"_id"]) {
            intestazione = (NSInteger)i;
            break;
        }
    }
    if (intestazione < 0) {
        return @[];
    }

    NSArray<NSString *> *colonne = righe[intestazione];
    NSMutableArray<OCCartaCsv *> *carte = [NSMutableArray array];

    for (NSUInteger i = (NSUInteger)intestazione + 1; i < righe.count; i++) {
        NSArray<NSString *> *riga = righe[i];

        BOOL vuota = YES;
        for (NSString *pezzo in riga) {
            if (pezzo.length > 0) {
                vuota = NO;
            }
        }
        // La tabella finisce dove finiscono le colonne: dopo c'è la riga vuota
        // e poi i collegamenti ai gruppi.
        if (riga.count < colonne.count || vuota) {
            break;
        }

        NSString *nome = [self valore:@"store" colonne:colonne riga:riga];
        NSString *codice = [self valore:@"cardid" colonne:colonne riga:riga];
        if (nome.length == 0 || codice.length == 0) {
            continue;
        }

        OCCartaCsv *letta = [OCCartaCsv new];
        letta.etichetta = nome;
        letta.codice = codice;
        letta.simbologia = [self simbologiaDaCatima:[self valore:@"barcodetype" colonne:colonne riga:riga]
                                             codice:codice];
        letta.colore = [self coloreDaIntero:[self valore:@"headercolor" colonne:colonne riga:riga]];
        letta.preferita = [[self valore:@"starstatus" colonne:colonne riga:riga] isEqualToString:@"1"];
        letta.note = [self valore:@"note" colonne:colonne riga:riga];
        letta.scadenza = [self dataDaMillis:[self valore:@"expiry" colonne:colonne riga:riga]];
        letta.saldo = [self saldoLeggibile:[self valore:@"balance" colonne:colonne riga:riga]
                                      tipo:[self valore:@"balancetype" colonne:colonne riga:riga]];
        [carte addObject:letta];
    }
    return carte;
}

@end
