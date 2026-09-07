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
// I nomi sono gli stessi di Android, `card_<id>_<lato>.jpg`, così un archivio
// scritto da un telefono si rilegge sull'altro senza conversioni.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCFoto : NSObject

/// Il nome da scrivere nella carta.
+ (NSString *)nomePerId:(NSInteger)identificativo fronte:(BOOL)fronte;

/// Il percorso di una foto, dal nome che sta scritto nella carta.
+ (NSString *)percorsoPerNome:(NSString *)nome;

/// Salva una foto rimpicciolita e torna il nome, `nil` se non si riesce.
+ (nullable NSString *)salva:(UIImage *)immagine
                          id:(NSInteger)identificativo
                      fronte:(BOOL)fronte;

/// La foto, o `nil` se il file non c'è più.
+ (nullable UIImage *)leggi:(NSString *)nome;

/// Toglie il file di una foto. Un nome vuoto non fa niente.
+ (void)cancella:(nullable NSString *)nome;

@end

NS_ASSUME_NONNULL_END
