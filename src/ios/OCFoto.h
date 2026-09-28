// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Le foto delle carte: fronte e retro.
//
// I byte stanno in file dentro la memoria privata dell'app, e nella carta
// viaggia solo il nome. Metterle nel file delle carte le farebbe crescere da
// qualche decina di kB a qualche MB per carta, e il passaggio a QR fra due
// telefoni diventerebbe impossibile.
//
// I nomi, `card_<id>_<lato>.jpg`, e la scrittura li fa il core, uguali su
// Android: qui si comprime e si legge. Le foto che nessuna carta nomina più le
// toglie il core dopo il salvataggio.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCFoto : NSObject


/// Il percorso di una foto, dal nome che sta scritto nella carta.
+ (NSString *)percorsoPerNome:(NSString *)nome;

/// Salva una foto rimpicciolita e torna il nome, `nil` se non si riesce.
+ (nullable NSString *)salva:(UIImage *)immagine
                          id:(NSInteger)identificativo
                      fronte:(BOOL)fronte;

/// La foto, o `nil` se il file non c'è più.
+ (nullable UIImage *)leggi:(NSString *)nome;


@end

NS_ASSUME_NONNULL_END
