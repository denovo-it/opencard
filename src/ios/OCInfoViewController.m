// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCInfoViewController.h"

#import "OCMarkdown.h"
#import "OCSplashViewController.h"
#import "OCTema.h"

static NSString *const OCSitoDenovo = @"https://denovo.srl";

static NSString *const OCSorgente = @"https://github.com/denovo-it/opencard";

static NSString *const OCIntroSorgente =
    @"Il codice di OpenCard è pubblico. È disponibile su GitHub con licenza AGPL v3: si legge, si "
     "compila e si controlla che l'app faccia solo quello che dice.";

static NSString *const OCPrivacy = @"https://denovo.srl/opencard-privacy/";

static NSString *const OCIntroPrivacy =
    @"OpenCard non raccoglie niente e non esce dal telefono: le carte restano nella memoria "
     "privata dell'app. La pagina qui sotto lo dice per esteso, ed è quella dichiarata a "
     "Google e ad Apple.";

static NSString *const OCPercheEsiste =
    @"OpenCard è un gesto di solidarietà nei confronti delle persone che tengono alla "
     "loro privacy e hanno bisogno di strumenti semplici.\n\n"
     "Strumenti che fanno esattamente quello che ti aspetti, senza proporti di continuo "
     "servizi che non ti interessano.";

static NSString *const OCLicenzaUso =
    @"OpenCard è un regalo di Denovo srl.\n\n"
     "Uso personale: libero.\n"
     "Uso commerciale: scrivi a info@denovo.srl.\n\n"
     "Il programma è distribuito sotto licenza AGPL v3, in alternativa a una licenza "
     "commerciale. Il testo integrale della AGPL v3 è qui sotto.";

static NSString *const OCMarchi =
    @"Denovo e OpenCard sono marchi di Denovo srl. Il nome Denovo, il nome OpenCard, i "
     "loghi e i segni distintivi che li accompagnano sono di proprietà riservata di "
     "Denovo srl.\n\n"
     "La licenza AGPL v3 riguarda il codice sorgente e non concede alcun diritto sui "
     "marchi. Chi distribuisce una versione modificata deve rimuovere i marchi e i loghi "
     "di Denovo srl e darle un nome proprio.";

static NSString *const OCIntroOpenSource =
    @"OpenCard sta in piedi grazie al lavoro di altri. Queste sono le librerie che "
     "contiene, con la licenza di ciascuna. Tocca un nome per aprirne la pagina.";

@interface OCInfoViewController () <UIPageViewControllerDataSource, UIPageViewControllerDelegate>
@property (nonatomic, strong) UISegmentedControl *schede;
@property (nonatomic, strong) UIPageViewController *pagine;
@property (nonatomic, strong) NSArray<UIViewController *> *fogli;
@end

/// Una scheda: una colonna dentro una vista scorrevole.
@interface OCFoglioViewController : UIViewController
@property (nonatomic, strong) UIStackView *colonna;
@end

@implementation OCFoglioViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.colonna = [UIStackView new];
    self.colonna.axis = UILayoutConstraintAxisVertical;
    self.colonna.spacing = 4;
    self.colonna.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scorrevole = [UIScrollView new];
    scorrevole.translatesAutoresizingMaskIntoConstraints = NO;
    [scorrevole addSubview:self.colonna];
    [self.view addSubview:scorrevole];

    [NSLayoutConstraint activateConstraints:@[
        [scorrevole.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scorrevole.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scorrevole.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scorrevole.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.colonna.topAnchor constraintEqualToAnchor:scorrevole.topAnchor constant:16],
        [self.colonna.bottomAnchor constraintEqualToAnchor:scorrevole.bottomAnchor constant:-24],
        [self.colonna.leadingAnchor constraintEqualToAnchor:scorrevole.leadingAnchor constant:20],
        [self.colonna.trailingAnchor constraintEqualToAnchor:scorrevole.trailingAnchor constant:-20],
        [self.colonna.widthAnchor constraintEqualToAnchor:scorrevole.widthAnchor constant:-40],
    ]];
}

@end

@implementation OCInfoViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"Informazioni";

    UIView *intestazione = [self costruisciIntestazione];

    self.schede = [[UISegmentedControl alloc] initWithItems:@[@"Informazioni", @"Legale"]];
    self.schede.selectedSegmentIndex = 0;
    self.schede.selectedSegmentTintColor = [OCTema marca];
    [self.schede setTitleTextAttributes:@{NSForegroundColorAttributeName: [OCTema sopraMarca]}
                               forState:UIControlStateSelected];
    [self.schede addTarget:self action:@selector(schedaCambiata)
          forControlEvents:UIControlEventValueChanged];
    self.schede.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.schede];

    self.fogli = @[[self foglioInformazioni], [self foglioLegale]];

    self.pagine = [[UIPageViewController alloc]
        initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll
          navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
                        options:nil];
    self.pagine.dataSource = self;
    self.pagine.delegate = self;
    [self.pagine setViewControllers:@[self.fogli.firstObject]
                          direction:UIPageViewControllerNavigationDirectionForward
                           animated:NO
                         completion:nil];

    [self addChildViewController:self.pagine];
    self.pagine.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.pagine.view];
    [self.pagine didMoveToParentViewController:self];

    UILayoutGuide *area = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [intestazione.topAnchor constraintEqualToAnchor:area.topAnchor constant:16],
        [intestazione.leadingAnchor constraintEqualToAnchor:area.leadingAnchor],
        [intestazione.trailingAnchor constraintEqualToAnchor:area.trailingAnchor],

        [self.schede.topAnchor constraintEqualToAnchor:intestazione.bottomAnchor constant:12],
        [self.schede.leadingAnchor constraintEqualToAnchor:area.leadingAnchor constant:20],
        [self.schede.trailingAnchor constraintEqualToAnchor:area.trailingAnchor constant:-20],

        [self.pagine.view.topAnchor constraintEqualToAnchor:self.schede.bottomAnchor constant:8],
        [self.pagine.view.bottomAnchor constraintEqualToAnchor:area.bottomAnchor],
        [self.pagine.view.leadingAnchor constraintEqualToAnchor:area.leadingAnchor],
        [self.pagine.view.trailingAnchor constraintEqualToAnchor:area.trailingAnchor],
    ]];
}

/// Logo dell'editore, sito, nome e versione. Toccando il logo si rivede il
/// benvenuto.
- (UIView *)costruisciIntestazione
{
    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"logo_denovo"]];
    logo.contentMode = UIViewContentModeScaleAspectFit;
    logo.userInteractionEnabled = YES;
    [logo addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(rivediBenvenuto)]];

    UIButton *sito = [UIButton buttonWithType:UIButtonTypeSystem];
    [sito setTitle:@"denovo.srl" forState:UIControlStateNormal];
    [sito setTitleColor:[OCTema marca] forState:UIControlStateNormal];
    [sito addTarget:self action:@selector(apriSito) forControlEvents:UIControlEventTouchUpInside];

    UILabel *nome = [UILabel new];
    nome.text = @"OpenCard";
    nome.font = [UIFont boldSystemFontOfSize:24];

    UILabel *versione = [UILabel new];
    versione.text = [OCTema versioneSemplice];
    versione.font = [UIFont systemFontOfSize:13];
    versione.textColor = [OCTema tenue];

    UIStackView *colonna = [[UIStackView alloc]
        initWithArrangedSubviews:@[logo, sito, nome, versione]];
    colonna.axis = UILayoutConstraintAxisVertical;
    colonna.alignment = UIStackViewAlignmentCenter;
    colonna.spacing = 2;
    colonna.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:colonna];

    [NSLayoutConstraint activateConstraints:@[
        [logo.widthAnchor constraintEqualToConstant:96],
        [logo.heightAnchor constraintEqualToConstant:96],
    ]];
    return colonna;
}

#pragma mark - Contenuto delle schede

- (UIViewController *)foglioInformazioni
{
    OCFoglioViewController *foglio = [OCFoglioViewController new];
    [foglio loadViewIfNeeded];

    [foglio.colonna addArrangedSubview:[self paragrafo:OCPercheEsiste dimensione:15]];
    [foglio.colonna addArrangedSubview:[self riga]];

    [foglio.colonna addArrangedSubview:[self titolo:@"Codice sorgente"]];
    [foglio.colonna addArrangedSubview:[self paragrafo:OCIntroSorgente dimensione:13]];
    [self aggiungiCollegamenti:@[
        @[@"github.com/denovo-it/opencard", @"AGPL v3", OCSorgente],
    ] a:foglio.colonna];
    [foglio.colonna addArrangedSubview:[self riga]];

    [foglio.colonna addArrangedSubview:[self titolo:@"Revisioni"]];
    for (OCBlocco *blocco in [OCMarkdown analizza:[self leggiRisorsa:@"CHANGELOG" tipo:@"md"]]) {
        [foglio.colonna addArrangedSubview:[self vistaPerBlocco:blocco]];
    }
    [foglio.colonna addArrangedSubview:[self riga]];

    [foglio.colonna addArrangedSubview:[self titolo:@"Software open source"]];
    [foglio.colonna addArrangedSubview:[self paragrafo:OCIntroOpenSource dimensione:13]];

    [foglio.colonna addArrangedSubview:[self sottotitolo:@"Componenti native"]];
    [self aggiungiCollegamenti:@[
        @[@"zint", @"BSD 3-Clause", @"https://www.zint.org.uk"],
        @[@"cJSON", @"MIT", @"https://github.com/DaveGamble/cJSON"],
    ] a:foglio.colonna];

    [foglio.colonna addArrangedSubview:[self sottotitolo:@"Componenti di sistema"]];
    [self aggiungiCollegamenti:@[
        @[@"UIKit", @"Apple", @"https://developer.apple.com/documentation/uikit"],
        @[@"AVFoundation", @"Apple", @"https://developer.apple.com/documentation/avfoundation"],
        @[@"Vision", @"Apple", @"https://developer.apple.com/documentation/vision"],
    ] a:foglio.colonna];

    return foglio;
}

- (UIViewController *)foglioLegale
{
    OCFoglioViewController *foglio = [OCFoglioViewController new];
    [foglio loadViewIfNeeded];

    [foglio.colonna addArrangedSubview:[self titolo:@"Privacy"]];
    [foglio.colonna addArrangedSubview:[self paragrafo:OCIntroPrivacy dimensione:14]];
    [self aggiungiCollegamenti:@[
        @[@"denovo.srl/opencard-privacy", @"Apri", OCPrivacy],
    ] a:foglio.colonna];
    [foglio.colonna addArrangedSubview:[self riga]];

    [foglio.colonna addArrangedSubview:[self titolo:@"Licenza d'uso"]];
    [foglio.colonna addArrangedSubview:[self paragrafo:OCLicenzaUso dimensione:15]];
    [foglio.colonna addArrangedSubview:[self riga]];

    [foglio.colonna addArrangedSubview:[self titolo:@"Marchi"]];
    [foglio.colonna addArrangedSubview:[self paragrafo:OCMarchi dimensione:14]];
    [foglio.colonna addArrangedSubview:[self riga]];

    [foglio.colonna addArrangedSubview:[self titolo:@"Licenza completa (AGPL v3)"]];

    UILabel *licenza = [UILabel new];
    licenza.text = [self leggiRisorsa:@"LICENSE" tipo:@"txt"];
    licenza.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    licenza.textColor = [OCTema attenuato];
    licenza.numberOfLines = 0;
    [foglio.colonna addArrangedSubview:licenza];

    return foglio;
}

- (NSString *)leggiRisorsa:(NSString *)nome tipo:(NSString *)tipo
{
    NSString *percorso = [[NSBundle mainBundle] pathForResource:nome ofType:tipo];
    NSString *contenuto = percorso != nil
        ? [NSString stringWithContentsOfFile:percorso encoding:NSUTF8StringEncoding error:NULL]
        : nil;
    return contenuto ?: @"Contenuto non disponibile.";
}

- (UIView *)vistaPerBlocco:(OCBlocco *)blocco
{
    switch (blocco.genere) {
        case OCGenereTitolo: {
            UILabel *etichetta = [UILabel new];
            etichetta.attributedText = blocco.testo;
            etichetta.font = [UIFont boldSystemFontOfSize:15];
            etichetta.textColor = [OCTema marca];
            etichetta.numberOfLines = 0;
            return etichetta;
        }
        case OCGenerePunto: {
            UILabel *pallino = [UILabel new];
            pallino.text = @"•";
            pallino.font = [UIFont systemFontOfSize:14];
            // Senza resistenza alla compressione, con un testo lungo la riga
            // schiaccia il pallino fino a larghezza zero: la voce perde il
            // rientro e si allarga oltre il margine delle altre.
            [pallino setContentHuggingPriority:UILayoutPriorityRequired
                                       forAxis:UILayoutConstraintAxisHorizontal];
            [pallino setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                     forAxis:UILayoutConstraintAxisHorizontal];

            UILabel *testo = [UILabel new];
            testo.attributedText = blocco.testo;
            testo.numberOfLines = 0;

            UIStackView *riga = [[UIStackView alloc] initWithArrangedSubviews:@[pallino, testo]];
            riga.axis = UILayoutConstraintAxisHorizontal;
            riga.alignment = UIStackViewAlignmentTop;
            riga.spacing = 8;
            return riga;
        }
        case OCGenereNota: {
            UILabel *etichetta = [UILabel new];
            etichetta.attributedText = blocco.testo;
            etichetta.font = [UIFont italicSystemFontOfSize:13];
            etichetta.textColor = [OCTema attenuato];
            etichetta.numberOfLines = 0;
            return etichetta;
        }
        default: {
            UILabel *etichetta = [UILabel new];
            etichetta.attributedText = blocco.testo;
            etichetta.numberOfLines = 0;
            return etichetta;
        }
    }
}

- (void)aggiungiCollegamenti:(NSArray<NSArray<NSString *> *> *)collegamenti a:(UIStackView *)colonna
{
    for (NSArray<NSString *> *collegamento in collegamenti) {
        UILabel *nome = [UILabel new];
        nome.text = collegamento[0];
        nome.font = [UIFont systemFontOfSize:14];

        UILabel *etichetta = [UILabel new];
        etichetta.text = collegamento[1];
        etichetta.font = [UIFont systemFontOfSize:12];
        etichetta.textColor = [OCTema attenuato];

        UIStackView *riga = [[UIStackView alloc] initWithArrangedSubviews:@[nome, etichetta]];
        riga.axis = UILayoutConstraintAxisHorizontal;
        riga.distribution = UIStackViewDistributionEqualSpacing;
        riga.accessibilityHint = collegamento[2];
        riga.userInteractionEnabled = YES;
        [riga addGestureRecognizer:[[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(apriCollegamento:)]];

        [colonna addArrangedSubview:riga];
    }
}

- (UILabel *)titolo:(NSString *)testo
{
    UILabel *etichetta = [UILabel new];
    etichetta.text = testo;
    etichetta.font = [UIFont boldSystemFontOfSize:16];
    etichetta.numberOfLines = 0;
    return etichetta;
}

- (UILabel *)sottotitolo:(NSString *)testo
{
    UILabel *etichetta = [UILabel new];
    etichetta.text = testo;
    etichetta.font = [UIFont boldSystemFontOfSize:13];
    etichetta.textColor = [OCTema attenuato];
    return etichetta;
}

- (UILabel *)paragrafo:(NSString *)testo dimensione:(CGFloat)dimensione
{
    UILabel *etichetta = [UILabel new];
    etichetta.text = testo;
    etichetta.font = [UIFont systemFontOfSize:dimensione];
    etichetta.numberOfLines = 0;
    return etichetta;
}

- (UIView *)riga
{
    UIView *linea = [UIView new];
    linea.backgroundColor = [[OCTema tenue] colorWithAlphaComponent:0.4];
    [linea.heightAnchor constraintEqualToConstant:1].active = YES;
    return linea;
}

#pragma mark - Azioni

- (void)schedaCambiata
{
    NSInteger destinazione = self.schede.selectedSegmentIndex;
    NSInteger corrente = [self.fogli indexOfObject:self.pagine.viewControllers.firstObject];

    if (destinazione == corrente) {
        return;
    }
    [self.pagine setViewControllers:@[self.fogli[destinazione]]
                          direction:(destinazione > corrente
                                     ? UIPageViewControllerNavigationDirectionForward
                                     : UIPageViewControllerNavigationDirectionReverse)
                           animated:YES
                         completion:nil];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pagine
      viewControllerBeforeViewController:(UIViewController *)vista
{
    NSInteger indice = [self.fogli indexOfObject:vista];
    return indice > 0 ? self.fogli[indice - 1] : nil;
}

- (UIViewController *)pageViewController:(UIPageViewController *)pagine
       viewControllerAfterViewController:(UIViewController *)vista
{
    NSInteger indice = [self.fogli indexOfObject:vista];
    return indice + 1 < (NSInteger)self.fogli.count ? self.fogli[indice + 1] : nil;
}

- (void)pageViewController:(UIPageViewController *)pagine
        didFinishAnimating:(BOOL)finita
   previousViewControllers:(NSArray<UIViewController *> *)precedenti
       transitionCompleted:(BOOL)completata
{
    if (completata) {
        self.schede.selectedSegmentIndex =
            [self.fogli indexOfObject:self.pagine.viewControllers.firstObject];
    }
}

- (void)apriSito
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:OCSitoDenovo]
                                       options:@{}
                             completionHandler:nil];
}

- (void)apriCollegamento:(UITapGestureRecognizer *)tocco
{
    NSString *indirizzo = tocco.view.accessibilityHint;
    if (indirizzo.length > 0) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:indirizzo]
                                           options:@{}
                                 completionHandler:nil];
    }
}

- (void)rivediBenvenuto
{
    OCSplashViewController *benvenuto = [[OCSplashViewController alloc] initSoloMostra:YES];
    benvenuto.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:benvenuto animated:YES completion:nil];
}

@end
