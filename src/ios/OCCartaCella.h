// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Una carta come scheda colorata, uguale a quella Android.

#import <UIKit/UIKit.h>

@class OCCarta;

NS_ASSUME_NONNULL_BEGIN

@interface OCCartaCella : UICollectionViewCell

/// Il cestino compare solo sulle usa e getta.
- (void)mostra:(OCCarta *)carta conCestino:(BOOL)conCestino;

@property (nonatomic, copy, nullable) void (^suCestino)(OCCarta *carta);

@end

NS_ASSUME_NONNULL_END
