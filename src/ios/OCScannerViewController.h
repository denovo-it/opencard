// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Lettura di un codice con la fotocamera.
//
// Usa AVFoundation, che è di sistema: niente librerie esterne, e quindi niente
// dei problemi che danno i binari precompilati quando cambia l'architettura.

#import <UIKit/UIKit.h>
#import <Vision/Vision.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCScannerViewController : UIViewController

/// Chiamato una volta sola, al primo codice riconosciuto. `simbologia` è quella
/// che il lettore ha riconosciuto, oppure `OCSimbologiaAuto` per un formato che
/// non sappiamo disegnare: in quel caso la sceglie l'app. Con `binario` il
/// codice è il base64 dei byte, come in `OCCarta.binario`.
@property (nonatomic, copy, nullable) void (^suLettura)(NSString *codice, NSInteger simbologia,
                                                         BOOL binario);

/// Acceso, la schermata non si chiude al primo codice: mette insieme i pezzi
/// di un passaggio di carte, che possono essere più d'uno e arrivare in
/// qualsiasi ordine. Chiude quando il core dice che ci sono tutti.
@property (nonatomic, assign) BOOL raccolta;

/// Chiamato a passaggio completo, con i testi dei QR raccolti.
@property (nonatomic, copy, nullable) void (^suRaccolta)(NSArray<NSString *> *pezzi);

@end

/// La simbologia del core di un formato di Vision. Sta qui perché la usano
/// tutti e due i lettori: questo dal vivo e il modulo sulle immagini.
FOUNDATION_EXPORT NSInteger OCSimbologiaDiVision(VNBarcodeSymbology simbologia);

/// Vero se il testo letto è testo davvero: non vuoto, senza caratteri di
/// controllo (a parte tabulazione, a capo, GS, RS ed EOT, che i codici GS1
/// usano) e senza il carattere di sostituzione che compare quando i byte non
/// erano UTF-8.
FOUNDATION_EXPORT BOOL OCTestoLeggibile(NSString *_Nullable testo);

/// Il base64 dei byte di un codice binario, come quelli dei biglietti
/// Trenitalia, dal testo che danno AVFoundation e Vision; nil se è testo vero.
///
/// I due lettori di Apple consegnano un codice binario come testo Latin-1, un
/// carattere per byte e zeri compresi: riconvertito, dà i byte esatti. Non
/// `payloadData` di Vision, che sono i dati grezzi del simbolo e non il
/// contenuto (provato su macOS il 25 ottobre 2026 con un biglietto vero).
FOUNDATION_EXPORT NSString *_Nullable OCCodiceBinario(NSString *_Nullable testo);

NS_ASSUME_NONNULL_END
