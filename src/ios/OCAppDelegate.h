// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import <UIKit/UIKit.h>

@interface OCAppDelegate : UIResponder <UIApplicationDelegate>
/// Il messaggio dell'errore di apertura dei dati, se c'è stato. Lo mostra la
/// scena, che ha la finestra.
@property (nonatomic, copy) NSString *erroreApertura;
@end
