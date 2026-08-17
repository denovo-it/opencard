// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Schermata di benvenuto: marchio, nome e versione.
//
// Compare al primo avvio e basta. Si rivede toccando il logo nella schermata
// informativa.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCSplashViewController : UIViewController

/// `soloMostra` acceso: al termine si chiude e torna indietro, invece di
/// passare alle carte.
- (instancetype)initSoloMostra:(BOOL)soloMostra;

@property (nonatomic, copy, nullable) void (^suFine)(void);

@end

NS_ASSUME_NONNULL_END
