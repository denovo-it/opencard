// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// La carta a schermo intero, davanti al lettore della cassa.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCDettaglioViewController : UIViewController
- (instancetype)initConId:(NSInteger)identificativo;
@end

NS_ASSUME_NONNULL_END
