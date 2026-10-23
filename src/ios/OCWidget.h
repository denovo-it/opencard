// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Le carte con la stella per il widget della schermata iniziale.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCWidget : NSObject

/// Riscrive widget.json nel contenitore condiviso e chiede a iOS di rifare il
/// widget. La chiama OCCore dopo ogni scrittura del file delle carte.
///
/// Nel file vanno id, nome e colore delle carte con la stella, mai codici o
/// numeri: sono i dati che il widget mostra comunque sulla schermata iniziale.
/// Senza il contenitore (un profilo senza App Group) non fa niente.
+ (void)aggiorna;

@end

NS_ASSUME_NONNULL_END
