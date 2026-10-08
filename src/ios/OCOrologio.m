// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCOrologio.h"

#import <WatchConnectivity/WatchConnectivity.h>

#import "OCCore.h"

/// Le chiavi dei messaggi, uguali in DalTelefono.swift sull'orologio.
/// Telefono -> orologio: il backup in chiaro, come byte UTF-8.
static NSString *const OCChiaveCarte = @"carte";
/// Orologio -> telefono: vuol dire «mandamele».
static NSString *const OCChiaveRichiesta = @"richiesta";

@interface OCOrologio () <WCSessionDelegate>
@end

@implementation OCOrologio

+ (OCOrologio *)delegato
{
    static OCOrologio *unico = nil;
    static dispatch_once_t unaVolta;
    dispatch_once(&unaVolta, ^{
        unico = [OCOrologio new];
    });
    return unico;
}

+ (void)avvia
{
    if (![WCSession isSupported]) {
        return;
    }
    WCSession *sessione = [WCSession defaultSession];
    sessione.delegate = [self delegato];
    [sessione activateSession];
}

+ (void)manda
{
    if (![WCSession isSupported]) {
        return;
    }
    WCSession *sessione = [WCSession defaultSession];
    if (sessione.activationState != WCSessionActivationStateActivated
        || !sessione.isPaired || !sessione.isWatchAppInstalled) {
        return;
    }
    NSData *carte = [self carte];
    if (carte == nil) {
        return;
    }
    // Il contesto porta l'ultimo stato e basta: l'orologio lo trova anche se
    // era spento, e un invio sopra l'altro lascia solo l'ultimo. Il limite
    // del sistema è sui 64 KB, qualche centinaio di carte, come i 100 KB di
    // un messaggio su Wear OS: oltre, l'invio fallisce e finisce nel log.
    NSError *errore = nil;
    if (![sessione updateApplicationContext:@{OCChiaveCarte: carte} error:&errore]) {
        NSLog(@"OpenCard: carte non mandate all'orologio: %@", errore);
    }
}

/// Il backup, letto sul thread principale: il core non ne regge due, e
/// l'app lo usa da lì. Chi chiama da un altro thread aspetta.
+ (NSData *)carte
{
    __block NSData *carte = nil;
    void (^leggi)(void) = ^{
        NSError *errore = nil;
        carte = [OCCore backupPerOrologio:&errore];
        if (carte == nil) {
            NSLog(@"OpenCard: backup per l'orologio non fatto: %@", errore);
        }
    };
    if ([NSThread isMainThread]) {
        leggi();
    } else {
        dispatch_sync(dispatch_get_main_queue(), leggi);
    }
    return carte;
}

#pragma mark - WCSessionDelegate

- (void)session:(WCSession *)sessione
    activationDidCompleteWithState:(WCSessionActivationState)stato
                             error:(NSError *)errore
{
    if (stato == WCSessionActivationStateActivated) {
        // L'orologio riceve le carte senza aspettare una scrittura.
        [OCOrologio manda];
    } else if (errore != nil) {
        NSLog(@"OpenCard: sessione con l'orologio non attiva: %@", errore);
    }
}

- (void)sessionWatchStateDidChange:(WCSession *)sessione
{
    // L'app appena installata sull'orologio parte con le carte.
    [OCOrologio manda];
}

- (void)sessionDidBecomeInactive:(WCSession *)sessione
{
}

- (void)sessionDidDeactivate:(WCSession *)sessione
{
    // L'utente è passato a un altro orologio: si riparte con quello.
    [sessione activateSession];
}

- (void)session:(WCSession *)sessione
    didReceiveMessage:(NSDictionary<NSString *, id> *)messaggio
         replyHandler:(void (^)(NSDictionary<NSString *, id> *))rispondi
{
    if (messaggio[OCChiaveRichiesta] == nil) {
        rispondi(@{});
        return;
    }
    NSData *carte = [OCOrologio carte];
    rispondi(carte != nil ? @{OCChiaveCarte: carte} : @{});
}

@end
