// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// La chiave con cui il file delle carte sta cifrato sul telefono.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCChiaveDati : NSObject

/// I 32 byte della chiave, creandola al primo avvio.
///
/// `nil` se il portachiavi non risponde: in quel caso il file resta in chiaro,
/// che è come si comportava l'app fino alla 1.0.2. Meglio un file leggibile che
/// un'app che non si apre.
+ (nullable NSData *)chiave;

@end

NS_ASSUME_NONNULL_END
