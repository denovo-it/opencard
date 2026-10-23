// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCLingua.h"

#import <objc/runtime.h>

/// La .lproj da cui escono i testi; nil finché non si sceglie una lingua.
static NSBundle *linguaScelta = nil;

/// Il bundle dell'app prende questa classe alla prima scelta: chiede i testi
/// alla .lproj scelta invece che a quella fissata all'avvio.
@interface OCBundleLingua : NSBundle
@end

@implementation OCBundleLingua

- (NSString *)localizedStringForKey:(NSString *)chiave
                              value:(NSString *)valore
                              table:(NSString *)tabella
{
    if (linguaScelta != nil) {
        return [linguaScelta localizedStringForKey:chiave value:valore table:tabella];
    }
    return [super localizedStringForKey:chiave value:valore table:tabella];
}

@end

@implementation OCLingua

+ (void)applica
{
    NSBundle *app = [NSBundle mainBundle];
    if (![app isKindOfClass:[OCBundleLingua class]]) {
        object_setClass(app, [OCBundleLingua class]);
    }

    // Con una lingua scelta AppleLanguages è quella; senza, sono le lingue del
    // telefono: tutte e due le strade passano dalla stessa scelta del sistema.
    NSArray<NSString *> *preferite =
        [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"];
    NSString *lingua = [NSBundle preferredLocalizationsFromArray:app.localizations
                                                  forPreferences:preferite].firstObject;
    NSString *percorso = lingua != nil ? [app pathForResource:lingua ofType:@"lproj"] : nil;
    linguaScelta = percorso != nil ? [NSBundle bundleWithPath:percorso] : nil;
}

@end
