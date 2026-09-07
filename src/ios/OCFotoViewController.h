// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// La foto di una carta a schermo pieno, da ingrandire con due dita.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCFotoViewController : UIViewController

- (instancetype)initConImmagine:(UIImage *)immagine titolo:(NSString *)titolo;

@end

NS_ASSUME_NONNULL_END
