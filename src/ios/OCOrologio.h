// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Le carte all'Apple Watch, con WatchConnectivity: da telefono a orologio,
// via Bluetooth o Wi-Fi diretto, nessun server. È quello che fa Orologio.kt
// su Android.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCOrologio : NSObject

/// Da chiamare una volta all'avvio, dopo OCCore. Senza un orologio
/// accoppiato, o su iPad, non fa niente.
+ (void)avvia;

/// Manda tutte le carte all'orologio, nel formato del backup. La chiama OCCore
/// dopo ogni scrittura del file. Torna subito: la consegna la fa il sistema.
+ (void)manda;

@end

NS_ASSUME_NONNULL_END
