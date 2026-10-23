// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCWidget.h"

#import "OCCore.h"
#import "store.h"

/// Lo stesso nome nei due profili e in src/widget/OpenCardWidget.swift.
static NSString *const OCGruppo = @"group.srl.denovo.opencard";

/// OCWidgetCentro sta in OCWidgetCentro.swift, perché WidgetCenter da
/// Objective-C non si vede. Si cerca per nome: una build senza lo Swift
/// (gli script vecchi del Mac) scrive il file e basta.
@protocol OCRicaricaWidget
+ (void)ricarica;
@end

@implementation OCWidget

+ (void)aggiorna
{
    NSURL *cartella = [[NSFileManager defaultManager]
                       containerURLForSecurityApplicationGroupIdentifier:OCGruppo];
    if (cartella == nil) {
        return;
    }

    NSArray<OCCarta *> *preferite = [OCCore cartePreferite:NULL] ?: @[];
    NSMutableArray *carte = [NSMutableArray arrayWithCapacity:preferite.count];
    for (OCCarta *carta in preferite) {
        [carte addObject:@{
            @"id": @(carta.identificativo),
            @"nome": carta.etichetta ?: @"",
            @"colore": carta.colore ?: @"",
            @"chiaro": opencard_colore_chiaro(carta.colore.UTF8String) ? @YES : @NO,
            @"bordo": opencard_colore_con_bordo(carta.colore.UTF8String) ? @YES : @NO,
        }];
    }
    // @YES e @NO, non 1 e 0: nel JSON diventano true e false, che il widget
    // legge come Bool.
    NSData *dati = [NSJSONSerialization dataWithJSONObject:@{@"carte": carte} options:0 error:NULL];
    NSURL *file = [cartella URLByAppendingPathComponent:@"widget.json"];
    if (dati == nil || ![dati writeToURL:file options:NSDataWritingAtomic error:NULL]) {
        return;
    }
    // Il file si rifà dalle carte a ogni modifica: nel backup non serve.
    [file setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:NULL];

    Class<OCRicaricaWidget> centro = NSClassFromString(@"OCWidgetCentro");
    [centro ricarica];
}

@end
