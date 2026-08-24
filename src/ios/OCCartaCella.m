// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCCartaCella.h"
#import "OCCore.h"
#import "OCTema.h"

@interface OCCartaCella ()
@property (nonatomic, strong) UIView *scheda;
@property (nonatomic, strong) UILabel *nome;
@property (nonatomic, strong) UIImageView *glifo;
@property (nonatomic, strong) UIButton *cestino;
@property (nonatomic, strong) OCCarta *carta;
@end

@implementation OCCartaCella

- (instancetype)initWithFrame:(CGRect)cornice
{
    self = [super initWithFrame:cornice];
    if (self == nil) {
        return nil;
    }

    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];

    _scheda = [UIView new];
    _scheda.layer.cornerRadius = 16;
    _scheda.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_scheda];

    // Il glifo dice che tipo di codice si troverà dentro, prima di aprirlo.
    _glifo = [UIImageView new];
    _glifo.contentMode = UIViewContentModeScaleAspectFit;
    _glifo.tintColor = [OCTema sopraMarca];
    _glifo.alpha = 0.85;
    _glifo.translatesAutoresizingMaskIntoConstraints = NO;
    [_scheda addSubview:_glifo];

    // Solo il nome: il numero della carta si legge aprendola, così non resta
    // esposto a chi guarda lo schermo dell'elenco.
    _nome = [UILabel new];
    _nome.font = [UIFont boldSystemFontOfSize:18];
    _nome.textColor = [OCTema sopraMarca];
    _nome.numberOfLines = 0;
    _nome.translatesAutoresizingMaskIntoConstraints = NO;
    [_scheda addSubview:_nome];

    _cestino = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cestino setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal];
    _cestino.tintColor = [OCTema sopraMarca];
    _cestino.hidden = YES;
    _cestino.translatesAutoresizingMaskIntoConstraints = NO;
    [_cestino addTarget:self action:@selector(cestinoPremuto)
       forControlEvents:UIControlEventTouchUpInside];
    [_scheda addSubview:_cestino];

    [NSLayoutConstraint activateConstraints:@[
        [_scheda.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        [_scheda.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [_scheda.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
        [_scheda.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],

        [_glifo.leadingAnchor constraintEqualToAnchor:_scheda.leadingAnchor constant:16],
        [_glifo.centerYAnchor constraintEqualToAnchor:_scheda.centerYAnchor],
        [_glifo.widthAnchor constraintEqualToConstant:28],
        [_glifo.heightAnchor constraintEqualToConstant:28],

        [_nome.leadingAnchor constraintEqualToAnchor:_glifo.trailingAnchor constant:16],
        [_nome.topAnchor constraintEqualToAnchor:_scheda.topAnchor constant:16],
        [_nome.bottomAnchor constraintEqualToAnchor:_scheda.bottomAnchor constant:-16],
        [_nome.trailingAnchor constraintLessThanOrEqualToAnchor:_cestino.leadingAnchor constant:-8],

        [_cestino.trailingAnchor constraintEqualToAnchor:_scheda.trailingAnchor constant:-16],
        [_cestino.centerYAnchor constraintEqualToAnchor:_scheda.centerYAnchor],
        [_cestino.widthAnchor constraintEqualToConstant:28],
        [_cestino.heightAnchor constraintEqualToConstant:28],
    ]];

    return self;
}

- (void)mostra:(OCCarta *)carta conCestino:(BOOL)conCestino
{
    self.carta = carta;
    self.nome.text = carta.etichetta;
    self.scheda.backgroundColor = [OCTema coloreDaEsadecimale:carta.colore];
    self.cestino.hidden = !conCestino;

    NSString *simbolo = carta.qrcode ? @"qrcode" : @"barcode";
    self.glifo.image = [[UIImage systemImageNamed:simbolo]
                        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (void)cestinoPremuto
{
    if (self.suCestino != nil && self.carta != nil) {
        self.suCestino(self.carta);
    }
}

@end
