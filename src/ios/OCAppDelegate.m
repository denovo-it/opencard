// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCAppDelegate.h"

#import "OCCore.h"
#import "OCListaViewController.h"
#import "OCSplashViewController.h"
#import "OCTema.h"

@implementation OCAppDelegate

- (BOOL)application:(UIApplication *)applicazione
    didFinishLaunchingWithOptions:(NSDictionary *)opzioni
{
    // Il file dei dati si apre prima di qualunque schermata: un problema qui
    // non deve chiudere l'app senza dire niente.
    NSError *errore = nil;
    BOOL aperto = [OCCore apriConErrore:&errore];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    [self applicaAspettoBarra];

    if ([OCCore primoAvvio]) {
        OCSplashViewController *benvenuto = [[OCSplashViewController alloc] initSoloMostra:NO];
        benvenuto.suFine = ^{ [self mostraCarte]; };
        self.window.rootViewController = benvenuto;
    } else {
        self.window.rootViewController = [self contenitoreCarte];
    }

    [self.window makeKeyAndVisible];

    if (!aperto) {
        [self avvisa:errore.localizedDescription];
    }
    return YES;
}

/// Barra arancione con testo bianco su tutte le schermate, come su Android.
- (void)applicaAspettoBarra
{
    UINavigationBarAppearance *aspetto = [UINavigationBarAppearance new];
    [aspetto configureWithOpaqueBackground];
    aspetto.backgroundColor = [OCTema marca];
    aspetto.titleTextAttributes = @{NSForegroundColorAttributeName: [OCTema sopraMarca]};

    UINavigationBar *barra = [UINavigationBar appearance];
    barra.standardAppearance = aspetto;
    barra.scrollEdgeAppearance = aspetto;
    barra.compactAppearance = aspetto;
    barra.tintColor = [OCTema sopraMarca];
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
