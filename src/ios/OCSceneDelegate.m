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

    OCAppDelegate *app = (OCAppDelegate *)[UIApplication sharedApplication].delegate;
    if (app.erroreApertura != nil) {
        [self avvisa:app.erroreApertura];
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
