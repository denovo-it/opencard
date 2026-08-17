// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Passaggio delle carte fra due telefoni con dei QR.
//
// Chi cede mostra i codici, chi riceve li inquadra. Non c'e' rete di mezzo, non
// c'e' un file da passare, non serve un account. Come sono fatti i codici sta
// in src/transfer.h.
//
// Non c'e' cifratura: il passaggio e' pensato dentro la famiglia, coi due
// telefoni uno davanti all'altro. Chi legge lo schermo legge le tessere, e su
// questa schermata c'e' scritto.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCTrasferimentoViewController : UIViewController

/// Chiamato quando le carte sono entrate, con quante ne sono entrate: chi ha
/// aperto la schermata ricarica la lista e lo dice all'utente.
@property (nonatomic, copy, nullable) void (^suRicevute)(NSInteger quante);

@end

NS_ASSUME_NONNULL_END
