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

    UIView *linea2 = [UIView new];
    linea2.backgroundColor = [UIColor separatorColor];
    [linea2.heightAnchor constraintEqualToConstant:1].active = YES;

    // Ultima voce, e l'unica che toglie qualcosa: sta in fondo e lontana dalle
    // altre apposta, e la domanda prima di eseguire dice dove si fa il backup.
    UIButton *azzera = [UIButton buttonWithType:UIButtonTypeSystem];
    [azzera setTitle:NSLocalizedString(@"azzera", nil) forState:UIControlStateNormal];
    [azzera setTitleColor:[OCTema pericolo] forState:UIControlStateNormal];
    azzera.titleLabel.font = [UIFont systemFontOfSize:16];
    azzera.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [azzera addTarget:self action:@selector(azzera)
     forControlEvents:UIControlEventTouchUpInside];

    UILabel *cosaFa = [UILabel new];
    cosaFa.text = NSLocalizedString(@"azzera_sottotitolo", nil);
    cosaFa.font = [UIFont systemFontOfSize:13];
    cosaFa.textColor = [OCTema attenuato];
    cosaFa.numberOfLines = 0;

    UIStackView *colonna = [[UIStackView alloc] initWithArrangedSubviews:@[
        titoloBackup, riga, self.spiegazione, linea, lingua, comeSiCambia,
        linea2, azzera, cosaFa,
    ]];
    colonna.axis = UILayoutConstraintAxisVertical;
    colonna.spacing = 12;
    colonna.translatesAutoresizingMaskIntoConstraints = NO;
    [colonna setCustomSpacing:24 afterView:self.spiegazione];
    [colonna setCustomSpacing:24 afterView:linea];
    [colonna setCustomSpacing:4 afterView:lingua];
    [colonna setCustomSpacing:24 afterView:comeSiCambia];
    [colonna setCustomSpacing:24 afterView:linea2];
    [colonna setCustomSpacing:4 afterView:azzera];
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

/// Butta via tutte le carte, con una domanda prima.
///
/// La domanda dice due cose: che non si torna indietro, e che il backup si fa
/// dal menu dell'elenco. Chi arriva a questa voce per sbaglio deve trovare la
/// strada per non perdere niente.
- (void)azzera
{
    UIAlertController *domanda = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"azzera_titolo", nil)
                         message:NSLocalizedString(@"azzera_avviso", nil)
                  preferredStyle:UIAlertControllerStyleAlert];

    [domanda addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"annulla", nil)
                                                style:UIAlertActionStyleCancel handler:nil]];
    [domanda addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"azzera_conferma", nil)
                                                style:UIAlertActionStyleDestructive
                                              handler:^(UIAlertAction *azione) {
        NSError *errore = nil;
        if (![OCCore azzeraTutto:&errore]) {
            [self avvisa:errore.localizedDescription];
            return;
        }
        [self svuotaTemporanei];
        if (self.suCarteAzzerate != nil) {
            self.suCarteAzzerate();
        }
        [self avvisa:NSLocalizedString(@"azzerate", nil)];
    }]];

    [self presentViewController:domanda animated:YES completion:nil];
}

/// I file temporanei.
///
/// Il backup appena esportato passa di qui prima di finire dove lo mette
/// l'utente, e se qualcosa si è interrotto può restare. Le carte non ci sono
/// mai state, ma chi chiede di cancellare tutto intende anche questi.
///
/// La guardia serve al caso limite in cui la cartella dei dati sia proprio
/// questa: succede solo se il sistema non dà Application Support, e allora
/// svuotare qui vorrebbe dire cancellare il file delle carte due volte, la
/// seconda senza che il core lo sappia.
- (void)svuotaTemporanei
{
    NSString *temporanei = NSTemporaryDirectory();
    if (temporanei.length == 0 || [[OCCore directoryDati] hasPrefix:temporanei]) {
        return;
    }
    NSFileManager *schedario = [NSFileManager defaultManager];
    for (NSString *nome in [schedario contentsOfDirectoryAtPath:temporanei error:NULL]) {
        [schedario removeItemAtPath:[temporanei stringByAppendingPathComponent:nome]
                              error:NULL];
    }
}

/// Un messaggio che resta il tempo di leggerlo, senza pulsanti da premere.
- (void)avvisa:(NSString *)messaggio
{
    UIAlertController *avviso = [UIAlertController alertControllerWithTitle:nil
                                                                   message:messaggio
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:avviso animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [avviso dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

- (void)chiudi
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
