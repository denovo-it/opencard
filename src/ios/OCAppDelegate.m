// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCAppDelegate.h"

#import "OCCore.h"
#import "OCTema.h"

@implementation OCAppDelegate

- (BOOL)application:(UIApplication *)applicazione
    didFinishLaunchingWithOptions:(NSDictionary *)opzioni
{
    // Il file dei dati si apre prima di qualunque schermata: un problema qui
    // non deve chiudere l'app senza dire niente. Il messaggio lo mostra la
    // scena, in OCSceneDelegate, perché la finestra adesso è sua.
    NSError *errore = nil;
    if (![OCCore apriConErrore:&errore]) {
        self.erroreApertura = errore.localizedDescription;
    }

    [self applicaAspettoBarra];
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

@end
