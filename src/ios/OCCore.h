// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Ponte fra il core in C e Objective-C.
//
// Qui dentro non c'è logica: si traducono soltanto stringhe, array e strutture.
// Il formato dei dati e dei backup è deciso dal core, quindi un backup fatto su
// Android si rilegge qui senza conversioni, e viceversa.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Una carta come la tiene il core.
@interface OCCarta : NSObject
@property (nonatomic, assign) NSInteger identificativo;
@property (nonatomic, copy) NSString *etichetta;
@property (nonatomic, copy) NSString *codice;
@property (nonatomic, assign) BOOL qrcode;
/// Colore da usare: quello scelto a mano, oppure quello che spetta all'id.
@property (nonatomic, copy) NSString *colore;
/// Vero se il colore l'ha scelto l'utente, non l'id.
@property (nonatomic, assign) BOOL coloreScelto;
@property (nonatomic, assign) BOOL usaEGetta;
/// Preferita: compare anche nella scheda con la stella.
@property (nonatomic, assign) BOOL preferita;
@end

@interface OCCore : NSObject

/// Va chiamata una volta all'avvio, prima di tutto il resto.
+ (BOOL)apriConErrore:(NSError **)errore;

+ (BOOL)primoAvvio;
+ (void)segnaPrimoAvvioFatto;

+ (nullable NSArray<OCCarta *> *)tutteLeCarte:(NSError **)errore;
+ (nullable NSArray<OCCarta *> *)carteDelGruppo:(BOOL)usaEGetta errore:(NSError **)errore;
+ (nullable OCCarta *)cartaConId:(NSInteger)identificativo errore:(NSError **)errore;

/// Le carte con la stella, dei due gruppi insieme. Vuota se non ce ne sono, e
/// allora la scheda con la stella non si mostra.
+ (nullable NSArray<OCCarta *> *)cartePreferite:(NSError **)errore;

/// Accende o spegne la stella, lasciando il resto della carta com'è.
+ (BOOL)impostaPreferita:(NSInteger)identificativo
                 accesa:(BOOL)accesa
                 errore:(NSError **)errore;
+ (NSInteger)prossimoId;

+ (NSInteger)inserisci:(NSString *)etichetta
                codice:(NSString *)codice
                qrcode:(BOOL)qrcode
                colore:(nullable NSString *)colore
             usaEGetta:(BOOL)usaEGetta
                errore:(NSError **)errore;

+ (BOOL)aggiorna:(NSInteger)identificativo
       etichetta:(NSString *)etichetta
          codice:(NSString *)codice
          qrcode:(BOOL)qrcode
          colore:(nullable NSString *)colore
       usaEGetta:(BOOL)usaEGetta
          errore:(NSError **)errore;

+ (BOOL)elimina:(NSInteger)identificativo errore:(NSError **)errore;

/// Riscrive l'ordine di un gruppo lasciando l'altro dov'è.
+ (BOOL)riordina:(BOOL)usaEGetta identificativi:(NSArray<NSNumber *> *)ids errore:(NSError **)errore;

/// Colore che spetta a un id, quando l'utente non ne sceglie uno.
+ (NSString *)colorePerId:(NSInteger)identificativo;

/// Il codice spezzato in blocchi di tre, per leggerlo e confrontarlo.
+ (NSString *)codiceRaggruppato:(NSString *)codice;

/// Immagine del codice, disegnata dal core.
+ (nullable UIImage *)immaginePerCodice:(NSString *)codice
                                 qrcode:(BOOL)qrcode
                                 errore:(NSError **)errore;

/// Nome proposto per il file di backup.
+ (NSString *)nomeBackup;

/// Contenuto del backup, pronto da scrivere.
+ (nullable NSData *)esportaBackup:(NSError **)errore;

/// Legge un backup e lo applica. Restituisce quante carte sono entrate, -1 se fallisce.
+ (NSInteger)ripristinaBackup:(NSData *)dati errore:(NSError **)errore;

#pragma mark - Passaggio delle carte con i QR

/// I testi dei QR da mostrare, in ordine, con dentro tutte le carte.
/// Come sono fatti sta in src/transfer.h.
+ (nullable NSArray<NSString *> *)codiciDaMostrare:(NSError **)errore;

/// A che punto è la raccolta, dati i QR letti finora: `ricevuti` e `totale`.
/// Totale a 0 vuol dire che fra i codici letti non ce n'è ancora uno di
/// OpenCard, e non è un errore: la fotocamera inquadra di tutto.
+ (BOOL)statoRaccolta:(NSArray<NSString *> *)letti
             ricevuti:(NSInteger *)ricevuti
               totale:(NSInteger *)totale
               errore:(NSError **)errore;

/// Le carte contenute nei QR letti, senza scrivere niente.
+ (nullable NSArray<OCCarta *> *)carteRicevute:(NSArray<NSString *> *)letti
                                        errore:(NSError **)errore;

/// Scrive le carte ricevute e dice quante ne ha scritte, -1 se fallisce.
/// `azzera` acceso butta via quelle che c'erano.
+ (NSInteger)applicaRicevute:(NSArray<NSString *> *)letti
                      azzera:(BOOL)azzera
                      errore:(NSError **)errore;

@end

NS_ASSUME_NONNULL_END
