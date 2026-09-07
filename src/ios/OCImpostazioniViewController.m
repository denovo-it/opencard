// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCImpostazioniViewController.h"

#import "OCCore.h"
#import "OCTema.h"

@interface OCImpostazioniViewController ()
@property (nonatomic, strong) UISwitch *interruttore;
@property (nonatomic, strong) UILabel *spiegazione;
@end

@implementation OCImpostazioniViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = NSLocalizedString(@"impostazioni", nil);

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                             target:self
                             action:@selector(chiudi)];

    UILabel *titoloBackup = [self titoletto:NSLocalizedString(@"backup", nil)];

    UILabel *voce = [UILabel new];
    voce.text = NSLocalizedString(@"backup_cloud", nil);
    voce.font = [UIFont systemFontOfSize:16];
    voce.numberOfLines = 0;

    self.interruttore = [UISwitch new];
    self.interruttore.onTintColor = [OCTema marca];
    self.interruttore.on = [OCCore carteNelBackup];
    [self.interruttore addTarget:self action:@selector(cambiato)
                forControlEvents:UIControlEventValueChanged];

    UIStackView *riga = [[UIStackView alloc] initWithArrangedSubviews:@[voce, self.interruttore]];
    riga.axis = UILayoutConstraintAxisHorizontal;
    riga.spacing = 12;
    riga.alignment = UIStackViewAlignmentCenter;

    // La riga sotto l'interruttore cambia con la scelta invece di stare ferma:
    // quello che succede acceso e quello che succede spento sono due cose
    // diverse, e scriverle tutte e due insieme obbligherebbe a leggerle
    // entrambe per capire in quale dei due casi si è.
    self.spiegazione = [UILabel new];
    self.spiegazione.font = [UIFont systemFontOfSize:13];
    self.spiegazione.textColor = [OCTema attenuato];
    self.spiegazione.numberOfLines = 0;
    [self mostraSpiegazione];

    UIView *linea = [UIView new];
    linea.backgroundColor = [UIColor separatorColor];
    [linea.heightAnchor constraintEqualToConstant:1].active = YES;

    // La lingua su iPhone la sceglie il sistema, app per app: qui c'è la strada
    // per arrivarci, non una seconda impostazione che direbbe il contrario.
    UIButton *lingua = [UIButton buttonWithType:UIButtonTypeSystem];
    [lingua setTitle:NSLocalizedString(@"lingua", nil) forState:UIControlStateNormal];
    lingua.titleLabel.font = [UIFont systemFontOfSize:16];
    lingua.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [lingua addTarget:self action:@selector(apriImpostazioniDiSistema)
     forControlEvents:UIControlEventTouchUpInside];

    UILabel *comeSiCambia = [UILabel new];
    comeSiCambia.text = NSLocalizedString(@"lingua_impostazioni_ios", nil);
    comeSiCambia.font = [UIFont systemFontOfSize:13];
    comeSiCambia.textColor = [OCTema attenuato];
    comeSiCambia.numberOfLines = 0;

    UIStackView *colonna = [[UIStackView alloc] initWithArrangedSubviews:@[
        titoloBackup, riga, self.spiegazione, linea, lingua, comeSiCambia,
    ]];
    colonna.axis = UILayoutConstraintAxisVertical;
    colonna.spacing = 12;
    colonna.translatesAutoresizingMaskIntoConstraints = NO;
    [colonna setCustomSpacing:24 afterView:self.spiegazione];
    [colonna setCustomSpacing:24 afterView:linea];
    [colonna setCustomSpacing:4 afterView:lingua];
    [self.view addSubview:colonna];

    UILayoutGuide *area = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [colonna.topAnchor constraintEqualToAnchor:area.topAnchor constant:24],
        [colonna.leadingAnchor constraintEqualToAnchor:area.leadingAnchor constant:20],
        [colonna.trailingAnchor constraintEqualToAnchor:area.trailingAnchor constant:-20],
    ]];
}

- (UILabel *)titoletto:(NSString *)testo
{
    UILabel *etichetta = [UILabel new];
    etichetta.text = testo;
    etichetta.font = [UIFont boldSystemFontOfSize:13];
    etichetta.textColor = [OCTema marca];
    return etichetta;
}

- (void)mostraSpiegazione
{
    self.spiegazione.text = self.interruttore.isOn
        ? NSLocalizedString(@"backup_cloud_acceso_ios", nil)
        : NSLocalizedString(@"backup_cloud_spento_ios", nil);
}

- (void)cambiato
{
    [OCCore metticiLeCarteNelBackup:self.interruttore.isOn];
    [self mostraSpiegazione];
}

- (void)apriImpostazioniDiSistema
{
    NSURL *dove = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if (dove != nil) {
        [[UIApplication sharedApplication] openURL:dove options:@{} completionHandler:nil];
    }
}

- (void)chiudi
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
