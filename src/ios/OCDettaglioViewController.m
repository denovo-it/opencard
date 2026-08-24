// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCDettaglioViewController.h"

#import "OCCore.h"
#import "OCFormViewController.h"
#import "OCTema.h"

@interface OCDettaglioViewController ()
@property (nonatomic, assign) NSInteger identificativo;
@property (nonatomic, strong) UIImageView *immagine;
@property (nonatomic, strong) UILabel *codice;
/// Il nome della carta in cima: una vista propria e non il titolo della barra,
/// che sta su una riga sola.
@property (nonatomic, strong) UILabel *titolo;
/// Luminosita' da rimettere uscendo: si tocca quella dello schermo, non
/// un'impostazione di sistema, quindi va restituita com'era.
@property (nonatomic, assign) CGFloat luminositaPrecedente;
/// Se la carta aperta ha la stella accesa. Serve a disegnare il pulsante.
@property (nonatomic, assign) BOOL preferita;
@property (nonatomic, strong) UIBarButtonItem *stella;
@end

@implementation OCDettaglioViewController

- (instancetype)initConId:(NSInteger)identificativo
{
    self = [super initWithNibName:nil bundle:nil];
    if (self != nil) {
        _identificativo = identificativo;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Fondo bianco: i lettori delle casse leggono male su fondo scuro, e in
    // scuro il codice andrebbe comunque disegnato su bianco.
    self.view.backgroundColor = [OCTema superficie];

    // Il nome della carta divide la barra con "Modifica" e la stella, e il
    // titolo di serie sta su una riga sola: i nomi lunghi si vedevano a metà.
    // Al suo posto una vista con due righe, come su Android. La centratura la
    // decide la barra e resta quella di sistema: su iOS un titolo allineato a
    // sinistra si vede solo coi titoli grandi, che qui non servono.
    self.titolo = [UILabel new];
    self.titolo.font = [UIFont boldSystemFontOfSize:15];
    self.titolo.textColor = [OCTema sopraMarca];
    self.titolo.textAlignment = NSTextAlignmentCenter;
    self.titolo.numberOfLines = 2;
    self.titolo.lineBreakMode = NSLineBreakByTruncatingTail;
    self.navigationItem.titleView = self.titolo;

    UIBarButtonItem *modifica = [[UIBarButtonItem alloc]
        initWithTitle:@"Modifica"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(apriModifica)];

    // La stella sta in alto a destra, vuota o piena a seconda di come sta la
    // carta. Si tocca per accenderla e per spegnerla.
    self.stella = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"star"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(cambiaStella)];

    self.navigationItem.rightBarButtonItems = @[modifica, self.stella];

    self.immagine = [UIImageView new];
    self.immagine.contentMode = UIViewContentModeScaleAspectFit;
    self.immagine.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.immagine];

    // Il numero sta attaccato al codice, non in fondo allo schermo: si leggono
    // insieme, e alla cassa serve confrontarli a colpo d'occhio.
    self.codice = [UILabel new];
    self.codice.font = [UIFont monospacedDigitSystemFontOfSize:20 weight:UIFontWeightRegular];
    self.codice.textColor = [OCTema inchiostro];
    self.codice.textAlignment = NSTextAlignmentCenter;
    self.codice.numberOfLines = 0;
    self.codice.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.codice];

    UILayoutGuide *area = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.immagine.centerYAnchor constraintEqualToAnchor:area.centerYAnchor constant:-20],
        [self.immagine.leadingAnchor constraintEqualToAnchor:area.leadingAnchor constant:24],
        [self.immagine.trailingAnchor constraintEqualToAnchor:area.trailingAnchor constant:-24],
        [self.immagine.heightAnchor constraintLessThanOrEqualToAnchor:area.heightAnchor
                                                          multiplier:0.6],

        [self.codice.topAnchor constraintEqualToAnchor:self.immagine.bottomAnchor constant:8],
        [self.codice.leadingAnchor constraintEqualToAnchor:area.leadingAnchor constant:24],
        [self.codice.trailingAnchor constraintEqualToAnchor:area.trailingAnchor constant:-24],
    ]];
}

- (void)viewWillAppear:(BOOL)animato
{
    [super viewWillAppear:animato];
    [self carica];

    // Lo schermo va al massimo finché la carta è aperta: i lettori laser e le
    // fotocamere delle casse leggono male uno schermo scuro.
    self.luminositaPrecedente = [UIScreen mainScreen].brightness;
    [UIScreen mainScreen].brightness = 1.0;
}

- (void)viewWillDisappear:(BOOL)animato
{
    [super viewWillDisappear:animato];
    [UIScreen mainScreen].brightness = self.luminositaPrecedente;
}

- (void)carica
{
    NSError *errore = nil;
    OCCarta *carta = [OCCore cartaConId:self.identificativo errore:&errore];

    if (carta == nil) {
        [self avvisa:errore.localizedDescription];
        return;
    }

    self.title = carta.etichetta;
    self.titolo.text = carta.etichetta;
    [self.titolo sizeToFit];
    self.codice.text = [OCCore codiceRaggruppato:carta.codice];
    self.preferita = carta.preferita;
    [self disegnaStella];

    UIImage *disegno = [OCCore immaginePerCodice:carta.codice qrcode:carta.qrcode errore:&errore];
    if (disegno == nil) {
        [self avvisa:errore.localizedDescription];
        return;
    }
    self.immagine.image = disegno;
}

/// Stella vuota se la carta non è preferita, piena se lo è.
- (void)disegnaStella
{
    NSString *nome = self.preferita ? @"star.fill" : @"star";
    UIImage *immagine = [UIImage systemImageNamed:nome];

    if (immagine != nil) {
        self.stella.image = immagine;
    } else {
        self.stella.title = self.preferita ? @"Preferita" : @"Preferisci";
    }
}

/// Accende o spegne la stella. La lista si ricarica da sé quando si torna
/// indietro, e lì la scheda con la stella compare o sparisce.
- (void)cambiaStella
{
    NSError *errore = nil;
    BOOL nuova = !self.preferita;

    if (![OCCore impostaPreferita:self.identificativo accesa:nuova errore:&errore]) {
        [self avvisa:errore.localizedDescription];
        return;
    }
    self.preferita = nuova;
    [self disegnaStella];
}

- (void)apriModifica
{
    OCFormViewController *form = [[OCFormViewController alloc]
                                  initPerModificaConId:self.identificativo];

    // Cancellata da lì, questa schermata non ha più niente da mostrare.
    __weak typeof(self) debole = self;
    form.suEliminazione = ^{
        [debole.navigationController popViewControllerAnimated:YES];
    };

    UINavigationController *contenitore = [[UINavigationController alloc]
                                           initWithRootViewController:form];
    [self presentViewController:contenitore animated:YES completion:nil];
}

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

@end
