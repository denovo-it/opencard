// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCTema.h"

NSString *const OCCanale = @"";

@implementation OCTema

+ (UIColor *)coloreConRosso:(int)r verde:(int)g blu:(int)b
{
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1.0];
}

+ (UIColor *)marca       { return [self coloreConRosso:0xE6 verde:0x64 blu:0x2B]; }
+ (UIColor *)sopraMarca  { return [UIColor whiteColor]; }
+ (UIColor *)pericolo    { return [self coloreConRosso:0xE5 verde:0x39 blu:0x35]; }
+ (UIColor *)inchiostro  { return [self coloreConRosso:0x20 verde:0x21 blu:0x24]; }
+ (UIColor *)attenuato   { return [self coloreConRosso:0x6B verde:0x72 blu:0x80]; }
+ (UIColor *)tenue       { return [self coloreConRosso:0x9A verde:0xA0 blu:0xA6]; }
+ (UIColor *)superficie  { return [UIColor whiteColor]; }

+ (UIColor *)coloreDaEsadecimale:(NSString *)esadecimale
{
    NSString *pulita = [esadecimale stringByReplacingOccurrencesOfString:@"#" withString:@""];

    if (pulita.length != 6) {
        return [self coloreConRosso:0x1E verde:0x88 blu:0xE5];
    }

    unsigned int valore = 0;
    NSScanner *lettore = [NSScanner scannerWithString:pulita];
    if (![lettore scanHexInt:&valore]) {
        return [self coloreConRosso:0x1E verde:0x88 blu:0xE5];
    }

    return [self coloreConRosso:(valore >> 16) & 0xFF
                          verde:(valore >> 8) & 0xFF
                            blu:valore & 0xFF];
}

+ (NSString *)versioneEstesa
{
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    NSString *versione = info[@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = info[@"CFBundleVersion"] ?: @"?";

    if (OCCanale.length > 0) {
        return [NSString stringWithFormat:@"%@ (build %@) · %@",
                versione, build, OCCanale.uppercaseString];
    }
    return [NSString stringWithFormat:@"%@ (build %@)", versione, build];
}

+ (NSString *)versioneSemplice
{
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    NSString *versione = info[@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = info[@"CFBundleVersion"] ?: @"?";

    return [NSString stringWithFormat:@"%@ (build %@)", versione, build];
}

@end
