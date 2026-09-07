// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Il CSV, nel formato di Catima.
//
// Serve per uscire e per entrare: chi lascia OpenCard deve potersi portare via
// le carte in un formato che un'altra app legge, e chi arriva da Catima deve
// poter entrare senza ribattere venti tessere a mano. Il formato è documentato
// in `docs/EXPORT_FORMAT.md` del loro repository.
//
// Quello che si perde passando di qui, ed è il motivo per cui l'archivio resta
// il modo consigliato: le foto, che nel CSV non ci stanno, e la distinzione fra
// carta normale e usa e getta, che nel loro formato non esiste.
//
// Su Android lo stesso formato lo scrive `Csv.kt`: le due copie devono restare
// allineate, e un file scritto da una si legge con l'altra.

#import <Foundation/Foundation.h>

#import "OCCore.h"

NS_ASSUME_NONNULL_BEGIN

/// Una carta letta dal CSV: quello che ci sta dentro, non di più.
@interface OCCartaCsv : NSObject
@property (nonatomic, copy) NSString *etichetta;
@property (nonatomic, copy) NSString *codice;
@property (nonatomic, assign) NSInteger simbologia;
@property (nonatomic, copy) NSString *colore;
@property (nonatomic, assign) BOOL preferita;
@property (nonatomic, copy) NSString *note;
@property (nonatomic, copy) NSString *scadenza;
@property (nonatomic, copy) NSString *saldo;
@end

@interface OCCsv : NSObject

+ (BOOL)eCsv:(NSData *)dati;
+ (NSData *)scrivi:(NSArray<OCCarta *> *)carte;
+ (NSArray<OCCartaCsv *> *)leggi:(NSData *)dati;

@end

NS_ASSUME_NONNULL_END
