// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Il poco Markdown che serve allo storico delle revisioni.
//
// Non e' un interprete completo e non deve diventarlo: il changelog usa titoli,
// punti elenco, grassetto e qualche nota, e basta riconoscere quelli.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OCGenere) {
    OCGenereTitolo,
    OCGenerePunto,
    OCGenereNota,
    OCGenereParagrafo,
};

@interface OCBlocco : NSObject
@property (nonatomic, assign) OCGenere genere;
@property (nonatomic, strong) NSAttributedString *testo;
@end

@interface OCMarkdown : NSObject
+ (NSArray<OCBlocco *> *)analizza:(NSString *)documento;
@end

NS_ASSUME_NONNULL_END
