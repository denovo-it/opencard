// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Colori dell'interfaccia, in un posto solo.
//
// Sono gli stessi della versione Android: l'arancione del marchio Denovo, lo
// stesso del logo e dell'icona. Le due app devono somigliarsi, non assomigliare
// ciascuna alle abitudini del proprio sistema.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Canale di rilascio: finche' e' valorizzato l'app lo dichiara.
extern NSString *_Nullable const OCCanale;

@interface OCTema : NSObject

+ (UIColor *)marca;        // accent: barra, pulsante di aggiunta, azioni
+ (UIColor *)sopraMarca;   // testo e icone sopra il marchio
+ (UIColor *)pericolo;     // eliminazione, errori
+ (UIColor *)inchiostro;   // testo principale
+ (UIColor *)attenuato;    // testo secondario
+ (UIColor *)tenue;        // stati vuoti, testo di servizio
+ (UIColor *)superficie;   // riquadro bianco del codice, sfondo

/// Colore da una stringa "#RRGGBB". Un colore illeggibile non deve far cadere
/// la lista: si ripiega su un blu neutro.
+ (UIColor *)coloreDaEsadecimale:(NSString *)esadecimale;

/// Versione e canale, come vanno mostrati nella schermata di avvio.
+ (NSString *)versioneEstesa;

/// Solo versione e build, senza la sigla del canale.
+ (NSString *)versioneSemplice;

@end

NS_ASSUME_NONNULL_END
