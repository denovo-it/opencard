// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Le impostazioni: il backup del telefono, la lingua e l'azzeramento.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCImpostazioniViewController : UIViewController

/// Chiamato quando da qui le carte sono state azzerate.
///
/// Questa schermata si apre come foglio, e chiudendo un foglio non si passa da
/// viewWillAppear: senza questo avviso l'elenco dietro resterebbe pieno di
/// carte che non ci sono più.
@property (nonatomic, copy, nullable) void (^suCarteAzzerate)(void);

@end

NS_ASSUME_NONNULL_END
