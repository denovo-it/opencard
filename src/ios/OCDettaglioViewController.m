// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCDettaglioViewController.h"

#import "OCCore.h"
#import "OCFoto.h"
#import "OCFotoViewController.h"
#import "OCFormViewController.h"
#import "OCTema.h"

/// Sotto questa altezza il codice non si stringe: 100 pt, che per un QR da
/// tessera sono ancora 4 pt per modulo.
static const CGFloat OCAltezzaMinimaCodice = 100;

@interface OCDettaglioViewController () <UIScrollViewDelegate>
@property (nonatomic, assign) NSInteger identificativo;
@property (nonatomic, strong) UIImageView *immagine;
/// L'altezza del codice: la costante la muove il pinch.
@property (nonatomic, strong) NSLayoutConstraint *altezzaCodice;
@property (nonatomic, assign) CGFloat altezzaAlPizzico;
@property (nonatomic, strong) UILabel *codice;
/// Nota, scadenza e saldo, uno per riga e solo se ci sono.
@property (nonatomic, strong) UILabel *dettagli;
/// Il nome della carta in cima: una vista propria e non il titolo della barra,
/// che sta su una riga sola.
@property (nonatomic, strong) UILabel *titolo;
/// Luminosita' da rimettere uscendo: si tocca quella dello schermo, non
/// un'impostazione di sistema, quindi va restituita com'era.
@property (nonatomic, assign) CGFloat luminositaPrecedente;
/// Se la carta aperta ha la stella accesa. Serve a disegnare il pulsante.
@property (nonatomic, assign) BOOL preferita;
@property (nonatomic, strong) UIBarButtonItem *stella;

/// Le foto: fronte e retro, una per pagina.
@property (nonatomic, strong) UIView *bloccoFoto;
@property (nonatomic, strong) UIScrollView *pagineFoto;
@property (nonatomic, strong) UIStackView *facce;
@property (nonatomic, strong) UILabel *etichettaFaccia;
@property (nonatomic, strong) UIButton *indietro;
@property (nonatomic, strong) UIButton *avanti;
@property (nonatomic, strong) NSArray<UIImage *> *immaginiFoto;
@property (nonatomic, strong) NSArray<NSString *> *nomiFacce;
/// Quale faccia si sta guardando: tornando dallo zoom si rimette questa, se no
/// chi ingrandiva il retro si ritroverebbe davanti al fronte.
@property (nonatomic, assign) NSInteger facciaMostrata;
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
        initWithTitle:NSLocalizedString(@"modifica_codice", nil)
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

    [self costruisci];
}

#pragma mark - Costruzione

/// Tutto dentro una vista che scorre: con due foto e una nota lunga il codice
/// da solo non basta più a riempire lo schermo, e senza scorrimento il fondo
/// resterebbe irraggiungibile.
- (void)costruisci
{
    self.immagine = [UIImageView new];
    self.immagine.contentMode = UIViewContentModeScaleAspectFit;
    self.immagine.userInteractionEnabled = YES;
    [self.immagine addGestureRecognizer:
        [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pizzica:)]];

    // Il numero sta attaccato al codice, non in fondo allo schermo: si leggono
    // insieme, e alla cassa serve confrontarli a colpo d'occhio.
    self.codice = [UILabel new];
    self.codice.font = [UIFont monospacedDigitSystemFontOfSize:20 weight:UIFontWeightRegular];
    self.codice.textColor = [OCTema inchiostro];
    self.codice.textAlignment = NSTextAlignmentCenter;
    self.codice.numberOfLines = 0;

    self.dettagli = [UILabel new];
    self.dettagli.font = [UIFont systemFontOfSize:15];
    self.dettagli.textColor = [OCTema inchiostro];
    self.dettagli.textAlignment = NSTextAlignmentCenter;
    self.dettagli.numberOfLines = 0;
    self.dettagli.hidden = YES;

    UIStackView *colonna = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.immagine, self.codice, self.dettagli, [self costruisciBloccoFoto],
    ]];
    colonna.axis = UILayoutConstraintAxisVertical;
    colonna.spacing = 12;
    colonna.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scorrevole = [UIScrollView new];
    scorrevole.translatesAutoresizingMaskIntoConstraints = NO;
    [scorrevole addSubview:colonna];
    [self.view addSubview:scorrevole];

    UILayoutGuide *area = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scorrevole.topAnchor constraintEqualToAnchor:area.topAnchor],
        [scorrevole.bottomAnchor constraintEqualToAnchor:area.bottomAnchor],
        [scorrevole.leadingAnchor constraintEqualToAnchor:area.leadingAnchor],
        [scorrevole.trailingAnchor constraintEqualToAnchor:area.trailingAnchor],

        [colonna.topAnchor constraintEqualToAnchor:scorrevole.topAnchor constant:20],
        [colonna.bottomAnchor constraintEqualToAnchor:scorrevole.bottomAnchor constant:-20],
        [colonna.leadingAnchor constraintEqualToAnchor:scorrevole.leadingAnchor constant:24],
        [colonna.trailingAnchor constraintEqualToAnchor:scorrevole.trailingAnchor constant:-24],
        [colonna.widthAnchor constraintEqualToAnchor:scorrevole.widthAnchor constant:-48],

        // Il codice si prende quasi metà schermo e non di più: sotto ci sono
        // il numero, i dettagli e le foto, e devono restare in vista.
        [self.immagine.heightAnchor constraintLessThanOrEqualToAnchor:area.heightAnchor
                                                           multiplier:0.45],
        self.altezzaCodice,
    ]];
}

/// L'altezza del codice parte dalla misura naturale dell'immagine e la cambia
/// il pinch, fra il minimo e il tetto di quasi metà schermo. Priorità sotto
/// il tetto, così il tetto vince.
- (NSLayoutConstraint *)altezzaCodice
{
    if (_altezzaCodice == nil) {
        _altezzaCodice = [self.immagine.heightAnchor constraintEqualToConstant:OCAltezzaMinimaCodice];
        _altezzaCodice.priority = UILayoutPriorityDefaultHigh;
    }
    return _altezzaCodice;
}

- (void)pizzica:(UIPinchGestureRecognizer *)gesto
{
    if (gesto.state == UIGestureRecognizerStateBegan) {
        self.altezzaAlPizzico = self.altezzaCodice.constant;
    } else if (gesto.state == UIGestureRecognizerStateChanged) {
        CGFloat tetto = self.view.safeAreaLayoutGuide.layoutFrame.size.height * 0.45;
        CGFloat nuova = self.altezzaAlPizzico * gesto.scale;
        self.altezzaCodice.constant = MIN(tetto, MAX(OCAltezzaMinimaCodice, nuova));
    }
}

/// Le foto, una per pagina, con l'etichetta del lato e due frecce.
- (UIView *)costruisciBloccoFoto
{
    self.bloccoFoto = [UIView new];
    self.bloccoFoto.hidden = YES;

    self.facce = [UIStackView new];
    self.facce.axis = UILayoutConstraintAxisHorizontal;
    self.facce.translatesAutoresizingMaskIntoConstraints = NO;

    self.pagineFoto = [UIScrollView new];
    self.pagineFoto.pagingEnabled = YES;
    self.pagineFoto.showsHorizontalScrollIndicator = NO;
    self.pagineFoto.delegate = self;
    self.pagineFoto.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pagineFoto addSubview:self.facce];
    [self.bloccoFoto addSubview:self.pagineFoto];

    self.etichettaFaccia = [UILabel new];
    self.etichettaFaccia.font = [UIFont systemFontOfSize:13];
    self.etichettaFaccia.textColor = [OCTema attenuato];
    self.etichettaFaccia.textAlignment = NSTextAlignmentCenter;
    self.etichettaFaccia.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bloccoFoto addSubview:self.etichettaFaccia];

    self.indietro = [self freccia:@"chevron.left" azione:@selector(facciaPrecedente)];
    self.avanti = [self freccia:@"chevron.right" azione:@selector(facciaSuccessiva)];
    [self.bloccoFoto addSubview:self.indietro];
    [self.bloccoFoto addSubview:self.avanti];

    [NSLayoutConstraint activateConstraints:@[
        [self.pagineFoto.topAnchor constraintEqualToAnchor:self.bloccoFoto.topAnchor],
        [self.pagineFoto.leadingAnchor constraintEqualToAnchor:self.bloccoFoto.leadingAnchor],
        [self.pagineFoto.trailingAnchor constraintEqualToAnchor:self.bloccoFoto.trailingAnchor],
        [self.pagineFoto.heightAnchor constraintEqualToConstant:200],

        [self.facce.topAnchor constraintEqualToAnchor:self.pagineFoto.topAnchor],
        [self.facce.bottomAnchor constraintEqualToAnchor:self.pagineFoto.bottomAnchor],
        [self.facce.leadingAnchor constraintEqualToAnchor:self.pagineFoto.leadingAnchor],
        [self.facce.trailingAnchor constraintEqualToAnchor:self.pagineFoto.trailingAnchor],
        [self.facce.heightAnchor constraintEqualToAnchor:self.pagineFoto.heightAnchor],

        [self.etichettaFaccia.topAnchor constraintEqualToAnchor:self.pagineFoto.bottomAnchor
                                                       constant:6],
        [self.etichettaFaccia.leadingAnchor constraintEqualToAnchor:self.bloccoFoto.leadingAnchor],
        [self.etichettaFaccia.trailingAnchor constraintEqualToAnchor:self.bloccoFoto.trailingAnchor],
        [self.etichettaFaccia.bottomAnchor constraintEqualToAnchor:self.bloccoFoto.bottomAnchor],

        [self.indietro.centerYAnchor constraintEqualToAnchor:self.pagineFoto.centerYAnchor],
        [self.indietro.leadingAnchor constraintEqualToAnchor:self.bloccoFoto.leadingAnchor],
        [self.avanti.centerYAnchor constraintEqualToAnchor:self.pagineFoto.centerYAnchor],
        [self.avanti.trailingAnchor constraintEqualToAnchor:self.bloccoFoto.trailingAnchor],
    ]];
    return self.bloccoFoto;
}

- (UIButton *)freccia:(NSString *)simbolo azione:(SEL)azione
{
    UIButton *bottone = [UIButton buttonWithType:UIButtonTypeSystem];
    [bottone setImage:[UIImage systemImageNamed:simbolo] forState:UIControlStateNormal];
    bottone.tintColor = [OCTema marca];
    bottone.backgroundColor = [[OCTema superficie] colorWithAlphaComponent:0.8];
    bottone.layer.cornerRadius = 16;
    bottone.translatesAutoresizingMaskIntoConstraints = NO;
    [bottone addTarget:self action:azione forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [bottone.widthAnchor constraintEqualToConstant:32],
        [bottone.heightAnchor constraintEqualToConstant:32],
    ]];
    return bottone;
}

#pragma mark - Ciclo di vita

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

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    // Le pagine sono larghe quanto la vista, e la vista la sua larghezza la sa
    // solo adesso: qui si rimette la faccia che si stava guardando.
    [self vaiAllaFaccia:self.facciaMostrata animato:NO];
}

#pragma mark - Dati

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
    [self mostraDettagliDi:carta];
    [self mostraFotoDi:carta];

    UIImage *disegno = [OCCore immaginePerCodice:carta.codice
                                      simbologia:carta.simbologia
                                          errore:&errore];
    if (disegno == nil) {
        [self avvisa:errore.localizedDescription];
        return;
    }
    // Passo 6: il core disegna 8 px per modulo, e con scala 8/6 l'immagine
    // misura 6 pt per modulo, come un QR stampato sulla tessera (vedi
    // guide/codici-quadrati-piu-piccoli.md). Da lì il pinch la cambia.
    UIImage *aPasso6 = [UIImage imageWithCGImage:disegno.CGImage
                                           scale:8.0 / 6.0
                                     orientation:UIImageOrientationUp];
    self.immagine.image = aPasso6;
    self.altezzaCodice.constant = MAX(OCAltezzaMinimaCodice, aPasso6.size.height);
}

/// Saldo, scadenza e nota, in quest'ordine e solo quelli compilati. Il riquadro
/// sparisce del tutto se non c'è niente: una carta senza dettagli non deve
/// mostrare uno spazio vuoto.
- (void)mostraDettagliDi:(OCCarta *)carta
{
    NSMutableArray<NSString *> *righe = [NSMutableArray array];

    if (carta.saldo.length > 0) {
        [righe addObject:[NSString stringWithFormat:@"%@: %@",
                          NSLocalizedString(@"saldo", nil), carta.saldo]];
    }
    if (carta.scadenza.length > 0) {
        [righe addObject:[NSString stringWithFormat:@"%@: %@",
                          NSLocalizedString(@"scadenza", nil), carta.scadenza]];
    }
    if (carta.note.length > 0) {
        [righe addObject:carta.note];
    }

    self.dettagli.text = [righe componentsJoinedByString:@"\n"];
    self.dettagli.hidden = righe.count == 0;
}

- (void)mostraFotoDi:(OCCarta *)carta
{
    NSMutableArray<UIImage *> *immagini = [NSMutableArray array];
    NSMutableArray<NSString *> *nomi = [NSMutableArray array];

    UIImage *fronte = [OCFoto leggi:carta.fotoFronte];
    if (fronte != nil) {
        [immagini addObject:fronte];
        [nomi addObject:NSLocalizedString(@"foto_fronte", nil)];
    }
    UIImage *retro = [OCFoto leggi:carta.fotoRetro];
    if (retro != nil) {
        [immagini addObject:retro];
        [nomi addObject:NSLocalizedString(@"foto_retro", nil)];
    }

    self.immaginiFoto = immagini;
    self.nomiFacce = nomi;
    self.bloccoFoto.hidden = immagini.count == 0;

    for (UIView *vecchia in self.facce.arrangedSubviews) {
        [self.facce removeArrangedSubview:vecchia];
        [vecchia removeFromSuperview];
    }
    for (NSUInteger i = 0; i < immagini.count; i++) {
        UIImageView *vista = [[UIImageView alloc] initWithImage:immagini[i]];
        vista.contentMode = UIViewContentModeScaleAspectFit;
        vista.userInteractionEnabled = YES;
        vista.tag = (NSInteger)i;
        [vista addGestureRecognizer:[[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(apriFoto:)]];
        [self.facce addArrangedSubview:vista];
        [vista.widthAnchor constraintEqualToAnchor:self.pagineFoto.widthAnchor].active = YES;
    }

    // Con una foto sola non c'è niente da girare, e due frecce spente sarebbero
    // solo due cose in più da guardare.
    BOOL una = immagini.count < 2;
    self.indietro.hidden = una;
    self.avanti.hidden = una;

    if (self.facciaMostrata >= (NSInteger)immagini.count) {
        self.facciaMostrata = 0;
    }
    [self aggiornaEtichettaFaccia];
}

#pragma mark - Foto

- (void)aggiornaEtichettaFaccia
{
    if (self.facciaMostrata < (NSInteger)self.nomiFacce.count) {
        self.etichettaFaccia.text = self.nomiFacce[self.facciaMostrata];
    }
    // La freccia che porta fuori dalle pagine si spegne invece di sparire: se
    // sparisse, le altre si sposterebbero a ogni cambio di faccia.
    self.indietro.enabled = self.facciaMostrata > 0;
    self.avanti.enabled = self.facciaMostrata + 1 < (NSInteger)self.immaginiFoto.count;
}

- (void)vaiAllaFaccia:(NSInteger)quale animato:(BOOL)animato
{
    if (quale < 0 || quale >= (NSInteger)self.immaginiFoto.count) {
        return;
    }
    self.facciaMostrata = quale;
    CGFloat larghezza = self.pagineFoto.bounds.size.width;
    [self.pagineFoto setContentOffset:CGPointMake(larghezza * quale, 0) animated:animato];
    [self aggiornaEtichettaFaccia];
}

- (void)facciaPrecedente
{
    [self vaiAllaFaccia:self.facciaMostrata - 1 animato:YES];
}

- (void)facciaSuccessiva
{
    [self vaiAllaFaccia:self.facciaMostrata + 1 animato:YES];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scorrevole
{
    if (scorrevole != self.pagineFoto || scorrevole.bounds.size.width == 0) {
        return;
    }
    self.facciaMostrata = (NSInteger)round(scorrevole.contentOffset.x / scorrevole.bounds.size.width);
    [self aggiornaEtichettaFaccia];
}

- (void)apriFoto:(UITapGestureRecognizer *)gesto
{
    NSInteger quale = gesto.view.tag;
    if (quale < 0 || quale >= (NSInteger)self.immaginiFoto.count) {
        return;
    }
    OCFotoViewController *schermo = [[OCFotoViewController alloc]
        initConImmagine:self.immaginiFoto[quale] titolo:self.nomiFacce[quale]];

    UINavigationController *contenitore = [[UINavigationController alloc]
                                           initWithRootViewController:schermo];
    [self presentViewController:contenitore animated:YES completion:nil];
}

#pragma mark - Stella e modifica

/// Stella vuota se la carta non è preferita, piena se lo è.
- (void)disegnaStella
{
    NSString *nome = self.preferita ? @"star.fill" : @"star";
    UIImage *immagine = [UIImage systemImageNamed:nome];

    if (immagine != nil) {
        self.stella.image = immagine;
    } else {
        self.stella.title = self.preferita ? NSLocalizedString(@"preferita", nil) : NSLocalizedString(@"preferisci", nil);
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

    // Modificata, va riletta: chiudendo il foglio questa schermata resta dov'era
    // e mostrerebbe ancora il nome e il codice di prima.
    form.suSalvataggio = ^{ [debole carica]; };

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
