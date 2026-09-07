// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCArchivio.h"

#import "OCFoto.h"

#include <stdlib.h>
#include <string.h>

#include "archivio.h"

static NSString *const OCNomeElenco = @"opencard.json";

@implementation OCArchivio

+ (BOOL)eArchivio:(NSData *)dati
{
    return opencard_zip_e_archivio(dati.bytes, dati.length) != 0;
}

+ (NSData *)scriviConElenco:(NSData *)elenco carte:(NSArray<OCCarta *> *)carte
{
    NSMutableArray<NSString *> *nomi = [NSMutableArray array];
    NSMutableArray<NSData *> *contenuti = [NSMutableArray array];

    [nomi addObject:OCNomeElenco];
    [contenuti addObject:elenco];

    for (OCCarta *carta in carte) {
        for (NSString *nome in @[carta.fotoFronte ?: @"", carta.fotoRetro ?: @""]) {
            if (nome.length == 0 || [nomi containsObject:nome]) {
                continue;
            }
            NSData *byte = [NSData dataWithContentsOfFile:[OCFoto percorsoPerNome:nome]];
            if (byte == nil) {
                continue;
            }
            [nomi addObject:nome];
            [contenuti addObject:byte];
        }
    }

    opencard_zip_voce *voci = calloc(nomi.count, sizeof(opencard_zip_voce));
    if (voci == NULL) {
        return nil;
    }
    for (NSUInteger i = 0; i < nomi.count; i++) {
        snprintf(voci[i].nome, sizeof(voci[i].nome), "%s", nomi[i].UTF8String);
        voci[i].dati = (unsigned char *)contenuti[i].bytes;
        voci[i].quanti = contenuti[i].length;
    }

    unsigned char *fuori = NULL;
    size_t quanti = 0;
    opencard_errore errore;
    NSData *archivio = nil;

    if (opencard_zip_scrivi(voci, nomi.count, &fuori, &quanti, &errore) == OPENCARD_OK) {
        archivio = [NSData dataWithBytes:fuori length:quanti];
        opencard_zip_free(fuori);
    }
    free(voci);
    return archivio;
}

+ (NSData *)leggiElencoDa:(NSData *)archivio
{
    opencard_zip_lettura lettura;
    opencard_errore errore;

    if (opencard_zip_leggi(archivio.bytes, archivio.length, &lettura, &errore) != OPENCARD_OK) {
        return nil;
    }

    NSData *elenco = nil;
    for (size_t i = 0; i < lettura.n; i++) {
        NSString *nome = [NSString stringWithUTF8String:lettura.voci[i].nome];
        NSData *contenuto = [NSData dataWithBytes:lettura.voci[i].dati
                                           length:lettura.voci[i].quanti];

        if ([nome isEqualToString:OCNomeElenco]) {
            elenco = contenuto;
            continue;
        }
        // Le foto tornano al loro posto con il nome che avevano: nella carta
        // sta scritto quello, e il file lo ritrova senza conversioni.
        // Un nome con una barra dentro si scarta: dentro un archivio può
        // esserci un percorso, e un percorso può uscire dalla cartella.
        if ([nome containsString:@"/"] || [nome containsString:@".."]) {
            continue;
        }
        [contenuto writeToFile:[OCFoto percorsoPerNome:nome] atomically:YES];
    }
    opencard_zip_libera(&lettura);
    return elenco;
}

@end
