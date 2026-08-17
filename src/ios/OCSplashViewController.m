// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCSplashViewController.h"

#import "OCCore.h"
#import "OCTema.h"

static const NSTimeInterval OCDurataBenvenuto = 3.0;

@interface OCSplashViewController ()
@property (nonatomic, assign) BOOL soloMostra;
@property (nonatomic, strong) NSTimer *conteggio;
@end

@implementation OCSplashViewController

- (instancetype)initSoloMostra:(BOOL)soloMostra
{
    self = [super initWithNibName:nil bundle:nil];
    if (self != nil) {
        _soloMostra = soloMostra;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [OCTema superficie];

    UIImageView *marca = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"opencard_mark"]];
    marca.contentMode = UIViewContentModeScaleAspectFit;
    marca.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *nome = [UILabel new];
    nome.text = @"OpenCard";
    nome.font = [UIFont boldSystemFontOfSize:34];
    nome.textColor = [OCTema inchiostro];

    UILabel *regalo = [UILabel new];
    regalo.text = @"Un regalo di Denovo";
    regalo.font = [UIFont systemFontOfSize:18];
    regalo.textColor = [OCTema attenuato];

    UILabel *versione = [UILabel new];
    versione.text = [OCTema versioneEstesa];
    versione.font = [UIFont systemFontOfSize:13];
    versione.textColor = [OCTema tenue];

    UIStackView *colonna = [[UIStackView alloc]
        initWithArrangedSubviews:@[marca, nome, regalo, versione]];
    colonna.axis = UILayoutConstraintAxisVertical;
    colonna.alignment = UIStackViewAlignmentCenter;
    colonna.spacing = 16;
    colonna.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:colonna];

    [NSLayoutConstraint activateConstraints:@[
        [colonna.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [colonna.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [marca.widthAnchor constraintEqualToConstant:220],
        [marca.heightAnchor constraintEqualToConstant:220],
    ]];
}

- (void)viewDidAppear:(BOOL)animato
{
    [super viewDidAppear:animato];

    // Il conteggio parte quando la schermata e' davvero a video: partendo dalla
    // costruzione, il tempo di disegno finirebbe dentro i tre secondi.
    self.conteggio = [NSTimer scheduledTimerWithTimeInterval:OCDurataBenvenuto
                                                     repeats:NO
                                                       block:^(NSTimer *timer) {
        [self prosegui];
    }];
}

- (void)viewWillDisappear:(BOOL)animato
{
    [super viewWillDisappear:animato];
    [self.conteggio invalidate];
    self.conteggio = nil;
}

- (void)prosegui
{
    if (self.soloMostra) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }

    [OCCore segnaPrimoAvvioFatto];
    if (self.suFine != nil) {
        self.suFine();
    }
}

@end
