// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Il backup in archivio: l'elenco delle carte e le foto in un file solo.
//
// Il JSON da solo non basta più da quando le carte hanno le foto: dentro ci
// finiscono i nomi dei file, non i byte, e un backup ripristinato su un altro
// telefono tornerebbe senza immagini.
//
// Dentro l'archivio ci sono `opencard.json` e le foto con il nome che hanno
// nella carta, `card_<id>_front.jpg` e `card_<id>_back.jpg`. È lo stesso
// schema di Catima, e lo stesso che scrive Android.
//
// La password non la mette lo ZIP, che sa cifrare male: si chiude tutto
// l'archivio con la cassaforte del core, la stessa del backup semplice.

#import <Foundation/Foundation.h>

#import "OCCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface OCArchivio : NSObject

/// Vero se i byte cominciano come uno ZIP.
+ (BOOL)eArchivio:(NSData *)dati;

/// L'archivio con dentro l'elenco e le foto che esistono davvero.
///
/// Le foto nominate da una carta ma sparite dal disco si saltano: meglio un
/// archivio con una foto in meno che nessun archivio.
+ (nullable NSData *)scriviConElenco:(NSData *)elenco carte:(NSArray<OCCarta *> *)carte;

/// L'elenco dentro l'archivio, dopo aver rimesso le foto al loro posto.
/// `nil` se dentro non c'è `opencard.json`.
+ (nullable NSData *)leggiElencoDa:(NSData *)archivio;

@end

NS_ASSUME_NONNULL_END
