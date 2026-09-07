// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCChiaveDati.h"

#import <Security/Security.h>

/// Il conto nel portachiavi: nome fisso, una chiave sola.
static NSString *const OCEtichettaChiave = @"opencard-dati";
static const NSUInteger OCByteChiave = 32;

@implementation OCChiaveDati

+ (NSMutableDictionary *)ricerca
{
    return [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"srl.denovo.opencard",
        (__bridge id)kSecAttrAccount: OCEtichettaChiave,
    } mutableCopy];
}

+ (NSData *)chiave
{
    NSData *esistente = [self leggi];
    return esistente != nil ? esistente : [self crea];
}

+ (NSData *)leggi
{
    NSMutableDictionary *domanda = [self ricerca];
    domanda[(__bridge id)kSecReturnData] = @YES;
    domanda[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef trovato = NULL;
    OSStatus esito = SecItemCopyMatching((__bridge CFDictionaryRef)domanda, &trovato);

    if (esito != errSecSuccess || trovato == NULL) {
        return nil;
    }
    NSData *chiave = (__bridge_transfer NSData *)trovato;
    return chiave.length == OCByteChiave ? chiave : nil;
}

+ (NSData *)crea
{
    NSMutableData *chiave = [NSMutableData dataWithLength:OCByteChiave];
    if (SecRandomCopyBytes(kSecRandomDefault, OCByteChiave, chiave.mutableBytes) != errSecSuccess) {
        return nil;
    }

    NSMutableDictionary *nuova = [self ricerca];
    nuova[(__bridge id)kSecValueData] = chiave;
    // AfterFirstUnlock, non ThisDeviceOnly, ed è una scelta: la chiave rientra
    // nel backup cifrato del telefono, quindi chi cambia iPhone ritrova le
    // carte. Con ThisDeviceOnly il file delle carte arriverebbe sul telefono
    // nuovo senza la chiave per aprirlo, e sarebbero perse senza un errore.
    // Il backup di iCloud è sempre cifrato; quello sul computer solo se si
    // spunta «Cifra backup locale», e senza quella spunta il portachiavi non
    // viene salvato.
    nuova[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;

    // Fuori dal portachiavi iCloud: la chiave segue il telefono, non l'account.
    nuova[(__bridge id)kSecAttrSynchronizable] = @NO;

    if (SecItemAdd((__bridge CFDictionaryRef)nuova, NULL) != errSecSuccess) {
        return nil;
    }
    return chiave;
}

@end
