// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Aggiunta e modifica di una carta.
//
// Il codice si prende in tre modi, con lo stesso peso: dal vivo con la
// fotocamera, da una foto della galleria, da un file.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCFormViewController : UIViewController

- (instancetype)initPerNuovaConUsaEGetta:(BOOL)usaEGetta;
- (instancetype)initPerModificaConId:(NSInteger)identificativo;

/// Chiamato quando la carta è stata cancellata da qui: chi ha aperto la
/// modifica dalla carta aperta non ha più niente da mostrare e si chiude.
@property (nonatomic, copy, nullable) void (^suEliminazione)(void);

/// Chiamato quando la carta è stata salvata, a foglio già chiuso.
///
/// Il modulo si apre come foglio, e chiudendolo la schermata sotto non passa
/// da `viewWillAppear`: senza avviso resterebbe com'era prima del salvataggio.
@property (nonatomic, copy, nullable) void (^suSalvataggio)(void);

@end

NS_ASSUME_NONNULL_END
