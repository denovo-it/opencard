// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Le carte, divise in due schede: quelle di tutti i giorni e le usa e getta.
// Si passa dall'una all'altra toccando la scheda o scorrendo con il dito.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCListaViewController : UIViewController

/// Rilegge tutte e due le schede: una modifica può spostare una carta di gruppo.
- (void)ricaricaTutto;

@end

NS_ASSUME_NONNULL_END
