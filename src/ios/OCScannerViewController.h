// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Lettura di un codice con la fotocamera.
//
// Usa AVFoundation, che e' di sistema: niente librerie esterne, e quindi niente
// dei problemi che danno i binari precompilati quando cambia l'architettura.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCScannerViewController : UIViewController

/// Chiamato una volta sola, al primo codice riconosciuto.
@property (nonatomic, copy, nullable) void (^suLettura)(NSString *codice, BOOL qrcode);

/// Acceso, la schermata non si chiude al primo codice: mette insieme i pezzi
/// di un passaggio di carte, che possono essere piu' d'uno e arrivare in
/// qualsiasi ordine. Chiude quando il core dice che ci sono tutti.
@property (nonatomic, assign) BOOL raccolta;

/// Chiamato a passaggio completo, con i testi dei QR raccolti.
@property (nonatomic, copy, nullable) void (^suRaccolta)(NSArray<NSString *> *pezzi);

@end

NS_ASSUME_NONNULL_END
