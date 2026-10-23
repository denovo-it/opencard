// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCSceneDelegate.h"

#import "OCAppDelegate.h"
#import "OCCore.h"
#import "OCListaViewController.h"
#import "OCSplashViewController.h"

@implementation OCSceneDelegate

// Dall'SDK di iOS 27 UIKit non avvia un'app senza scene: la finestra nasce qui
// e non più nell'app delegate. I dati invece si aprono una volta sola per
// processo, in OCAppDelegate, perché il sistema può staccare la scena e
// riattaccarla senza chiudere l'app.
- (void)scene:(UIScene *)scena
    willConnectToSession:(UISceneSession *)sessione
                 options:(UISceneConnectionOptions *)opzioni
{
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scena];

    if ([OCCore primoAvvio]) {
        OCSplashViewController *benvenuto = [[OCSplashViewController alloc] initSoloMostra:NO];
        benvenuto.suFine = ^{ [self mostraCarte]; };
        self.window.rootViewController = benvenuto;
    } else {
        self.window.rootViewController = [self contenitoreCarte];
    }

    [self.window makeKeyAndVisible];

    // Aperta da un tocco sul widget: la carta si apre quando l'elenco c'è.
    NSURL *indirizzo = opzioni.URLContexts.anyObject.URL;
    if (indirizzo != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self apri:indirizzo]; });
    }

    OCAppDelegate *app = (OCAppDelegate *)[UIApplication sharedApplication].delegate;
    if (app.erroreApertura != nil) {
        [self avvisa:app.erroreApertura];
    }
}

/// Un tocco sul widget con l'app già aperta.
- (void)scene:(UIScene *)scena openURLContexts:(NSSet<UIOpenURLContext *> *)contesti
{
    NSURL *indirizzo = contesti.anyObject.URL;
    if (indirizzo != nil) {
        [self apri:indirizzo];
    }
}

/// opencard://carta/<id>, l'indirizzo che il widget dà a ogni carta.
- (void)apri:(NSURL *)indirizzo
{
    if (![indirizzo.scheme isEqualToString:@"opencard"] || ![indirizzo.host isEqualToString:@"carta"]) {
        return;
    }
    NSInteger identificativo = indirizzo.lastPathComponent.integerValue;
    UIViewController *radice = self.window.rootViewController;
    if (identificativo <= 0 || ![radice isKindOfClass:[UINavigationController class]]) {
        return;
    }
    UIViewController *elenco = ((UINavigationController *)radice).viewControllers.firstObject;
    if ([elenco isKindOfClass:[OCListaViewController class]]) {
        [(OCListaViewController *)elenco apriCartaConId:identificativo];
    }
}

- (UINavigationController *)contenitoreCarte
{
    return [[UINavigationController alloc]
            initWithRootViewController:[OCListaViewController new]];
}

- (void)mostraCarte
{
    self.window.rootViewController = [self contenitoreCarte];
}

- (void)rifaiInterfacciaSulleImpostazioni
{
    // Prima si chiude il foglio aperto: cambiando la radice sotto un foglio,
    // il foglio vecchio può restare nella finestra.
    [self.window.rootViewController dismissViewControllerAnimated:NO completion:^{
        UINavigationController *carte = [self contenitoreCarte];
        self.window.rootViewController = carte;
        // Il foglio si apre al giro dopo, quando l'elenco è già nella finestra.
        dispatch_async(dispatch_get_main_queue(), ^{
            [(OCListaViewController *)carte.viewControllers.firstObject apriImpostazioniAnimate:NO];
        });
    }];
}

- (void)avvisa:(NSString *)messaggio
{
    UIAlertController *avviso = [UIAlertController alertControllerWithTitle:nil
                                                                   message:messaggio
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [avviso addAction:[UIAlertAction actionWithTitle:@"OK"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
    [self.window.rootViewController presentViewController:avviso animated:YES completion:nil];
}

@end
