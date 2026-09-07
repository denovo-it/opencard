// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCTrasferimentoViewController.h"

#import "OCCore.h"
#import "OCScannerViewController.h"
#import "OCTema.h"

@interface OCTrasferimentoViewController ()
@property (nonatomic, strong) UIStackView *scelta;
@property (nonatomic, strong) UIStackView *vetrina;
@property (nonatomic, strong) UIImageView *codice;
@property (nonatomic, strong) UILabel *contatore;

@property (nonatomic, strong) NSArray<UIImage *> *immagini;
@property (nonatomic, assign) NSUInteger mostrato;
@property (nonatomic, strong, nullable) NSTimer *giostra;

/// Quante carte ci sono su questo telefono, per la domanda di chi riceve.
@property (nonatomic, assign) NSInteger mie;
@property (nonatomic, assign) CGFloat luminositaPrecedente;
@end

@implementation OCTrasferimentoViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = NSLocalizedString(@"trasferisci", nil);

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                             target:self
                             action:@selector(chiudi)];

    self.luminositaPrecedente = [UIScreen mainScreen].brightness;

    [self preparaScelta];
    [self preparaVetrina];

    // Serve solo per la domanda da fare a chi riceve, quindi un errore qui non
    // blocca niente: al massimo la domanda dice "ne hai 0".
    NSArray<OCCarta *> *tutte = [OCCore tutteLeCarte:NULL];
    self.mie = (NSInteger)tutte.count;
}

#pragma mark - Le due strade

- (void)preparaScelta
{
    UILabel *spiega = [UILabel new];
    spiega.text = NSLocalizedString(@"trasferimento_spiega", nil);
    spiega.numberOfLines = 0;
    spiega.font = [UIFont systemFontOfSize:16];
    spiega.textColor = [OCTema inchiostro];

    UIButton *mostra = [self pulsante:NSLocalizedString(@"trasferimento_mostra", nil) pieno:YES azione:@selector(preparaCodici)];
    UIButton *ricevi = [self pulsante:NSLocalizedString(@"trasferimento_ricevi", nil) pieno:NO azione:@selector(apriLettore)];

    self.scelta = [[UIStackView alloc] initWithArrangedSubviews:@[spiega, mostra, ricevi]];
    self.scelta.axis = UILayoutConstraintAxisVertical;
    self.scelta.spacing = 16;
    self.scelta.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scelta];

    [NSLayoutConstraint activateConstraints:@[
        [self.scelta.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.scelta.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.scelta.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [mostra.heightAnchor constraintEqualToConstant:50],
        [ricevi.heightAnchor constraintEqualToConstant:50],
    ]];
}

- (UIButton *)pulsante:(NSString *)titolo pieno:(BOOL)pieno azione:(SEL)azione
{
    UIButton *pulsante = [UIButton buttonWithType:UIButtonTypeSystem];
    [pulsante setTitle:titolo forState:UIControlStateNormal];
    pulsante.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    pulsante.layer.cornerRadius = 12;

    if (pieno) {
        pulsante.backgroundColor = [OCTema marca];
        [pulsante setTitleColor:[OCTema sopraMarca] forState:UIControlStateNormal];
    } else {
        pulsante.layer.borderWidth = 1.5;
        pulsante.layer.borderColor = [OCTema marca].CGColor;
        [pulsante setTitleColor:[OCTema marca] forState:UIControlStateNormal];
    }
    [pulsante addTarget:self action:azione forControlEvents:UIControlEventTouchUpInside];
    return pulsante;
}

#pragma mark - Chi mostra

- (void)preparaVetrina
{
    self.codice = [UIImageView new];
    self.codice.contentMode = UIViewContentModeScaleAspectFit;

    self.contatore = [UILabel new];
    self.contatore.textAlignment = NSTextAlignmentCenter;
    self.contatore.font = [UIFont boldSystemFontOfSize:18];
    self.contatore.textColor = [OCTema inchiostro];

    UILabel *avviso = [UILabel new];
    avviso.text = NSLocalizedString(@"trasferimento_mostra_avviso", nil);
    avviso.numberOfLines = 0;
    avviso.textAlignment = NSTextAlignmentCenter;
    avviso.font = [UIFont systemFontOfSize:14];
    avviso.textColor = [OCTema attenuato];

    UILabel *privacy = [UILabel new];
    privacy.text = NSLocalizedString(@"trasferimento_privacy", nil);
    privacy.numberOfLines = 0;
    privacy.textAlignment = NSTextAlignmentCenter;
    privacy.font = [UIFont systemFontOfSize:13];
    privacy.textColor = [OCTema tenue];

    self.vetrina = [[UIStackView alloc]
        initWithArrangedSubviews:@[self.codice, self.contatore, avviso, privacy]];
    self.vetrina.axis = UILayoutConstraintAxisVertical;
    self.vetrina.spacing = 12;
    self.vetrina.hidden = YES;
    self.vetrina.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.vetrina];

    [NSLayoutConstraint activateConstraints:@[
        [self.vetrina.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                                               constant:16],
        [self.vetrina.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor
                                                  constant:-16],
        [self.vetrina.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.vetrina.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    ]];
}

- (void)preparaCodici
{
    NSError *errore = nil;
    NSArray<NSString *> *codici = [OCCore codiciDaMostrare:&errore];

    if (codici == nil) {
        [self avvisa:errore.localizedDescription];
        return;
    }
    if (codici.count == 0) {
        [self avvisa:NSLocalizedString(@"trasferimento_niente_carte", nil)];
        return;
    }

    NSMutableArray<UIImage *> *immagini = [NSMutableArray arrayWithCapacity:codici.count];
    for (NSString *testo in codici) {
        UIImage *immagine = [OCCore immaginePerCodice:testo qrcode:YES errore:&errore];
        if (immagine == nil) {
            [self avvisa:errore.localizedDescription];
            return;
        }
        [immagini addObject:immagine];
    }

    self.immagini = immagini;
    self.mostrato = 0;
    self.scelta.hidden = YES;
    self.vetrina.hidden = NO;

    // Lo schermo al massimo mentre i codici girano: come per una carta davanti
    // al lettore della cassa, la fotocamera dell'altro telefono legge male uno
    // schermo scuro, e qui i codici sono fitti.
    [UIScreen mainScreen].brightness = 1.0;
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    [self disegnaCodice];

    // Un codice ogni 400 ms: più in fretta e la fotocamera dell'altro telefono
    // ne perde la metà, più piano e stare fermi diventa lungo.
    if (self.immagini.count > 1) {
        self.giostra = [NSTimer scheduledTimerWithTimeInterval:0.4
                                                        target:self
                                                      selector:@selector(avanza)
                                                      userInfo:nil
                                                       repeats:YES];
    }
}

- (void)avanza
{
    if (self.immagini.count == 0) {
        return;
    }
    self.mostrato = (self.mostrato + 1) % self.immagini.count;
    [self disegnaCodice];
}

- (void)disegnaCodice
{
    self.codice.image = self.immagini[self.mostrato];
    self.contatore.text = self.immagini.count == 1
        ? NSLocalizedString(@"trasferimento_pezzo_unico", nil)
        : [NSString stringWithFormat:NSLocalizedString(@"trasferimento_pezzo", nil),
                                     (unsigned long)(self.mostrato + 1),
                                     (unsigned long)self.immagini.count];
}

#pragma mark - Chi riceve

- (void)apriLettore
{
    OCScannerViewController *lettore = [OCScannerViewController new];
    lettore.raccolta = YES;

    __weak typeof(self) debole = self;
    lettore.suRaccolta = ^(NSArray<NSString *> *pezzi) {
        [debole dismissViewControllerAnimated:YES completion:^{
            [debole chiediComeMetterle:pezzi];
        }];
    };

    UINavigationController *contenitore =
        [[UINavigationController alloc] initWithRootViewController:lettore];
    [self presentViewController:contenitore animated:YES completion:nil];
}

/// Le due strade, chieste prima di scrivere qualsiasi cosa.
///
/// Il conteggio si fa leggendo i pezzi senza toccare il file: se la domanda
/// dicesse un numero sbagliato, chi risponde "azzera e sostituisci"
/// perderebbe le sue carte per niente.
- (void)chiediComeMetterle:(NSArray<NSString *> *)pezzi
{
    NSError *errore = nil;
    NSArray<OCCarta *> *arrivate = [OCCore carteRicevute:pezzi errore:&errore];

    if (arrivate == nil) {
        [self avvisa:errore.localizedDescription];
        return;
    }
    if (arrivate.count == 0) {
        [self avvisa:NSLocalizedString(@"trasferimento_niente_ricevuto", nil)];
        return;
    }

    NSInteger quante = (NSInteger)arrivate.count;
    NSString *domanda = [NSString stringWithFormat:
        NSLocalizedString(@"trasferimento_scelta_domanda", nil), (long)quante, (long)self.mie];

    UIAlertController *scelta = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"trasferimento_scelta_titolo", nil)
                         message:domanda
                  preferredStyle:UIAlertControllerStyleAlert];

    [scelta addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"aggiungi", nil)
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *azione) {
        [self applica:pezzi azzera:NO];
    }]];
    [scelta addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"trasferimento_sostituisci", nil)
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *azione) {
        [self confermaSostituzione:pezzi quante:quante];
    }]];
    [scelta addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"annulla", nil)
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];

    [self presentViewController:scelta animated:YES completion:nil];
}

/// L'unica delle due strade da cui non si torna indietro: si chiede due volte.
- (void)confermaSostituzione:(NSArray<NSString *> *)pezzi quante:(NSInteger)quante
{
    NSString *avviso = [NSString stringWithFormat:
        NSLocalizedString(@"trasferimento_sostituisci_avviso", nil), (long)self.mie, (long)quante];

    UIAlertController *domanda = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"trasferimento_sostituisci_titolo", nil)
                         message:avviso
                  preferredStyle:UIAlertControllerStyleAlert];

    [domanda addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"annulla", nil)
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [domanda addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"trasferimento_sostituisci", nil)
                                                style:UIAlertActionStyleDestructive
                                              handler:^(UIAlertAction *azione) {
        [self applica:pezzi azzera:YES];
    }]];

    [self presentViewController:domanda animated:YES completion:nil];
}

- (void)applica:(NSArray<NSString *> *)pezzi azzera:(BOOL)azzera
{
    NSError *errore = nil;
    NSInteger quante = [OCCore applicaRicevute:pezzi azzera:azzera errore:&errore];

    if (quante < 0) {
        [self avvisa:errore.localizedDescription];
        return;
    }
    if (self.suRicevute != nil) {
        self.suRicevute(quante);
    }
    [self chiudi];
}

#pragma mark - Servizio

- (void)avvisa:(NSString *)messaggio
{
    UIAlertController *avviso = [UIAlertController alertControllerWithTitle:nil
                                                                   message:messaggio
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [avviso addAction:[UIAlertAction actionWithTitle:@"OK"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
    [self presentViewController:avviso animated:YES completion:nil];
}

- (void)chiudi
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewWillDisappear:(BOOL)animato
{
    [super viewWillDisappear:animato];
    [self.giostra invalidate];
    self.giostra = nil;
    [UIScreen mainScreen].brightness = self.luminositaPrecedente;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
}

@end
