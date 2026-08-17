// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Le carte di un gruppo: quelle di tutti i giorni, le usa e getta, oppure le
// preferite. Le istanze di questa schermata stanno affiancate nella lista.

#import <UIKit/UIKit.h>

@class OCCarta;

NS_ASSUME_NONNULL_BEGIN

@interface OCGruppoViewController : UIViewController

- (instancetype)initConUsaEGetta:(BOOL)usaEGetta;

/// Le carte con la stella, dei due gruppi insieme. Qui non si riordina e non
/// c'e' il cestino: l'ordine e' quello dei gruppi di provenienza.
- (instancetype)initPreferite;

@property (nonatomic, readonly) BOOL usaEGetta;
@property (nonatomic, readonly) BOOL preferite;

@property (nonatomic, copy, nullable) void (^suTocco)(OCCarta *carta);
@property (nonatomic, copy, nullable) void (^suCestino)(OCCarta *carta);
@property (nonatomic, copy, nullable) void (^suErrore)(NSString *messaggio);

/// Rilegge le carte dal core.
- (void)ricarica;

@end

NS_ASSUME_NONNULL_END
