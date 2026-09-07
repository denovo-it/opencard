// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCFoto.h"

/// Il lato lungo a cui si riducono le foto prima di salvarle.
static const CGFloat OCLatoMassimo = 1600;

/// Qualità del JPEG: sopra il 90 il file cresce e l'occhio non se ne accorge.
static const CGFloat OCQualita = 0.85;

@implementation OCFoto

/// La cartella delle foto, dentro Application Support come il file dei dati.
+ (NSString *)cartella
{
    NSArray<NSString *> *percorsi = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *dove = [percorsi.firstObject stringByAppendingPathComponent:@"foto"];

    [[NSFileManager defaultManager] createDirectoryAtPath:dove
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return dove;
}

+ (NSString *)nomePerId:(NSInteger)identificativo fronte:(BOOL)fronte
{
    return [NSString stringWithFormat:@"card_%ld_%@.jpg",
            (long)identificativo, fronte ? @"front" : @"back"];
}

+ (NSString *)percorsoPerNome:(NSString *)nome
{
    return [[self cartella] stringByAppendingPathComponent:nome];
}

/// Rimpicciolisce tenendo le proporzioni. Una foto da 12 megapixel tenuta
/// intera sono quattro MB per faccia, e sullo schermo se ne vedono 400 punti.
+ (UIImage *)rimpicciolita:(UIImage *)immagine
{
    CGFloat lato = MAX(immagine.size.width, immagine.size.height);
    if (lato <= OCLatoMassimo) {
        return immagine;
    }

    CGFloat fattore = OCLatoMassimo / lato;
    CGSize misura = CGSizeMake(round(immagine.size.width * fattore),
                               round(immagine.size.height * fattore));

    UIGraphicsImageRendererFormat *formato = [UIGraphicsImageRendererFormat defaultFormat];
    formato.scale = 1;
    UIGraphicsImageRenderer *disegnatore =
        [[UIGraphicsImageRenderer alloc] initWithSize:misura format:formato];

    return [disegnatore imageWithActions:^(UIGraphicsImageRendererContext *contesto) {
        (void)contesto;
        [immagine drawInRect:CGRectMake(0, 0, misura.width, misura.height)];
    }];
}

+ (NSString *)salva:(UIImage *)immagine id:(NSInteger)identificativo fronte:(BOOL)fronte
{
    NSString *nome = [self nomePerId:identificativo fronte:fronte];
    NSData *byte = UIImageJPEGRepresentation([self rimpicciolita:immagine], OCQualita);

    if (byte == nil) {
        return nil;
    }
    if (![byte writeToFile:[self percorsoPerNome:nome] atomically:YES]) {
        return nil;
    }
    return nome;
}

+ (UIImage *)leggi:(NSString *)nome
{
    if (nome.length == 0) {
        return nil;
    }
    return [UIImage imageWithContentsOfFile:[self percorsoPerNome:nome]];
}

+ (void)cancella:(NSString *)nome
{
    if (nome.length == 0) {
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:[self percorsoPerNome:nome] error:NULL];
}

@end
