// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// La lingua scelta in Impostazioni, subito, senza riaprire l'app.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCLingua : NSObject

/// Da qui in poi i testi dell'app escono nella lingua di AppleLanguages.
///
/// iPhone legge AppleLanguages solo all'avvio: dopo una scelta i testi
/// resterebbero quelli di prima fino alla riapertura. Così NSLocalizedString
/// li prende dalla .lproj giusta già da adesso; le schermate già aperte
/// vanno rifatte da chi chiama.
+ (void)applica;

@end

NS_ASSUME_NONNULL_END
