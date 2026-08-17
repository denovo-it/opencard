// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCMarkdown.h"

#import "OCTema.h"

@implementation OCBlocco
@end

@implementation OCMarkdown

+ (NSArray<OCBlocco *> *)analizza:(NSString *)documento
{
    NSMutableArray<OCBlocco *> *blocchi = [NSMutableArray array];
    NSCharacterSet *spazi = [NSCharacterSet whitespaceCharacterSet];

    for (NSString *riga in [documento componentsSeparatedByString:@"\n"]) {
        NSString *pulita = [riga stringByTrimmingCharactersInSet:spazi];
        if (pulita.length == 0) {
            continue;
        }

        OCBlocco *blocco = [OCBlocco new];

        if ([pulita hasPrefix:@"## "]) {
            blocco.genere = OCGenereTitolo;
            blocco.testo = [self inline:[pulita substringFromIndex:3]];
        } else if ([pulita hasPrefix:@"# "]) {
            blocco.genere = OCGenereTitolo;
            blocco.testo = [self inline:[pulita substringFromIndex:2]];
        } else if ([pulita hasPrefix:@"- "]) {
            blocco.genere = OCGenerePunto;
            blocco.testo = [self inline:[pulita substringFromIndex:2]];
        } else if ([pulita hasPrefix:@"> "]) {
            blocco.genere = OCGenereNota;
            blocco.testo = [self inline:[pulita substringFromIndex:2]];
        } else {
            blocco.genere = OCGenereParagrafo;
            blocco.testo = [self inline:pulita];
        }

        [blocchi addObject:blocco];
    }
    return blocchi;
}

/// Grassetto fra doppi asterischi e codice fra apici inversi.
///
/// Si scorre una volta sola: cosi' non serve nessuna espressione regolare e le
/// marcature spaiate restano testo, invece di far sparire meta' riga.
+ (NSAttributedString *)inline:(NSString *)testo
{
    NSMutableAttributedString *uscita = [NSMutableAttributedString new];
    NSUInteger i = 0;

    UIFont *normale = [UIFont systemFontOfSize:14];
    UIFont *grassetto = [UIFont boldSystemFontOfSize:14];
    UIFont *monospazio = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];

    while (i < testo.length) {
        if (i + 1 < testo.length && [[testo substringWithRange:NSMakeRange(i, 2)] isEqualToString:@"**"]) {
            NSRange resto = NSMakeRange(i + 2, testo.length - i - 2);
            NSRange fine = [testo rangeOfString:@"**" options:0 range:resto];

            if (fine.location == NSNotFound) {
                [uscita appendAttributedString:[[NSAttributedString alloc]
                    initWithString:[testo substringFromIndex:i]
                        attributes:@{NSFontAttributeName: normale}]];
                break;
            }

            NSString *dentro = [testo substringWithRange:
                                NSMakeRange(i + 2, fine.location - i - 2)];
            [uscita appendAttributedString:[[NSAttributedString alloc]
                initWithString:dentro attributes:@{NSFontAttributeName: grassetto}]];
            i = fine.location + 2;
            continue;
        }

        if ([testo characterAtIndex:i] == '`') {
            NSRange resto = NSMakeRange(i + 1, testo.length - i - 1);
            NSRange fine = [testo rangeOfString:@"`" options:0 range:resto];

            if (fine.location == NSNotFound) {
                [uscita appendAttributedString:[[NSAttributedString alloc]
                    initWithString:[testo substringFromIndex:i]
                        attributes:@{NSFontAttributeName: normale}]];
                break;
            }

            NSString *dentro = [testo substringWithRange:
                                NSMakeRange(i + 1, fine.location - i - 1)];
            [uscita appendAttributedString:[[NSAttributedString alloc]
                initWithString:dentro attributes:@{NSFontAttributeName: monospazio}]];
            i = fine.location + 1;
            continue;
        }

        [uscita appendAttributedString:[[NSAttributedString alloc]
            initWithString:[testo substringWithRange:NSMakeRange(i, 1)]
                attributes:@{NSFontAttributeName: normale}]];
        i++;
    }

    return uscita;
}

@end
