// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCListaViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "OCCore.h"
#import "OCImpostazioniViewController.h"
#import "OCDettaglioViewController.h"
#import "OCFormViewController.h"
#import "OCGruppoViewController.h"
#import "OCInfoViewController.h"
#import "OCTema.h"
#import "OCTrasferimentoViewController.h"

/// Il campo di ricerca compare solo quando la scheda aperta ha più di questo
/// numero di carte. Con poche carte stanno tutte sullo schermo e si fa prima a
/// toccarle: il campo occuperebbe solo spazio. Lo stesso valore è in
/// MainActivity.kt.
static const NSUInteger OCCartePerLaRicerca = 5;

/// Contenitore del marchio nella barra.
///
/// La barra di sistema misura la vista del titolo dalla sua dimensione
/// naturale, e per una `UIImageView` quella è la dimensione dell'immagine:
/// 440x220 punti, cioè fuori dalla barra e sopra le carte. Il riquadro
/// assegnato a mano non basta, perché la barra può seguire la dimensione
/// naturale e ignorarlo, ed è quello che succede su iPhone e su iPad mentre
/// nel simulatore il riquadro veniva rispettato. Scrivendo qui la dimensione
/// naturale le due strade portano allo stesso posto.
@interface OCMarcaBarra : UIView
@end

@implementation OCMarcaBarra
- (CGSize)intrinsicContentSize
{
    return CGSizeMake(92, 34);
}
@end

@interface OCListaViewController () <UIPageViewControllerDataSource, UIPageViewControllerDelegate,
                                     UIDocumentPickerDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISegmentedControl *schede;
/// Il selettore aperto per importare: il delegato è lo stesso dell'esportazione.
@property (nonatomic, weak) UIDocumentPickerViewController *selettoreImporta;
/// La rotella dell'esportazione e dell'importazione, e la finestra che resta
/// ferma finché lavorano.
@property (nonatomic, strong, nullable) UIActivityIndicatorView *rotella;
@property (nonatomic, weak, nullable) UIWindow *finestraFerma;
@property (nonatomic, strong) UIPageViewController *pagine;
@property (nonatomic, strong) NSArray<OCGruppoViewController *> *gruppi;
@property (nonatomic, strong) UIButton *aggiungi;
@property (nonatomic, strong) UIView *schedeSfondo;
/// La ricerca per etichetta, sopra le carte: vale per tutte le schede insieme.
@property (nonatomic, strong) UISearchBar *ricerca;
/// L'altezza del campo di ricerca: va a zero quando non c'è nessuna carta.
@property (nonatomic, strong) NSLayoutConstraint *altezzaRicerca;
/// Vero quando la scheda con la stella è in mezzo alle altre.
@property (nonatomic, assign) BOOL conPreferite;
/// Lo stesso per la scheda usa e getta: senza carte dentro non si mostra.
@property (nonatomic, assign) BOOL conUsaEGetta;
/// L'altezza della barra delle schede: va a zero quando resta una scheda sola.
@property (nonatomic, strong) NSLayoutConstraint *altezzaSchede;
/// Vero fino alla prima comparsa: serve a distinguere l'apertura dell'app dal
/// ritorno da una carta, dove la scheda aperta va lasciata dov'era.
@property (nonatomic, assign) BOOL primaApertura;
- (void)importa;
- (void)esporta;
- (void)trasferisci;
- (void)apriImpostazioni;
@end

@implementation OCListaViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.primaApertura = YES;

    [self preparaBarra];
    [self preparaSchede];
    [self preparaRicerca];
    [self preparaPagine];
    [self preparaPulsanteAggiungi];

    // Le schede si disegnano quando le pagine ci sono: rifaiLeSchede: guarda
    // quale pagina è aperta per sapere quale segmento accendere.
    [self rifaiLeSchede:[self ordine]];
}

/// Tornando qui da una carta le cose possono essere cambiate: la stella si
/// accende dal dettaglio, e la scheda con la stella deve comparire o sparire
/// di conseguenza.
- (void)viewWillAppear:(BOOL)animato
{
    [super viewWillAppear:animato];
    [self ricaricaTutto];
    [self apriSullaStella];
}

/// All'apertura si parte dalla stella, quando c'è.
///
/// Sono le carte che si usano di più: se la scheda esiste è quella che serve
/// per prima. La scheda compare solo dopo la prima lettura, quando la pagina
/// mostrata è già quella delle carte, quindi va spostata qui.
- (void)apriSullaStella
{
    if (!self.primaApertura) {
        return;
    }
    self.primaApertura = NO;
    if (!self.conPreferite) {
        return;
    }
    [self.pagine setViewControllers:@[self.gruppi[2]]
                          direction:UIPageViewControllerNavigationDirectionReverse
                           animated:NO
                         completion:nil];
    self.schede.selectedSegmentIndex = [self schedaCorrente];
    [self aggiornaRicerca];
}

#pragma mark - Barra

/// Il marchio prende il posto del titolo, come su Android, e sta al centro da
/// solo: la sigla del canale la dicono la schermata di avvio e le note di
/// rilascio.
- (void)preparaBarra
{
    UIImage *marca = [UIImage imageNamed:@"opencard_appbar"];

    if (marca != nil) {
        OCMarcaBarra *contenitore =
            [[OCMarcaBarra alloc] initWithFrame:CGRectMake(0, 0, 92, 34)];
        UIImageView *vista = [[UIImageView alloc] initWithImage:marca];
        vista.contentMode = UIViewContentModeScaleAspectFit;
        vista.frame = contenitore.bounds;
        vista.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [contenitore addSubview:vista];
        self.navigationItem.titleView = contenitore;
    } else {
        self.title = @"OpenCard";
    }

    // A sinistra le informazioni: dalla lista non si torna da nessuna parte,
    // quindi quel posto è libero.
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"info.circle"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(apriInformazioni)];

    // A destra il menu di backup. Niente icona di uscita: Apple non consente a
    // un'app di chiudersi da sola, e un pulsante che non fa niente è peggio di
    // un pulsante assente.
    UIBarButtonItem *backup = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(apriMenuBackup)];

    // Da iOS 14 il menu mostra le icone accanto alle voci, come su Android.
    // Sotto resta il foglio di azioni, che le icone non le fa vedere.
    //
    // Le frecce seguono la versione Android e non l'abitudine di iOS: importa
    // in su, esporta in giù. Chi usa tutte e due le app deve trovare la stessa
    // icona per la stessa cosa.
    if (@available(iOS 14.0, *)) {
        __weak typeof(self) debole = self;
        UIAction *importa = [UIAction actionWithTitle:NSLocalizedString(@"importa", nil)
                                                image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                           identifier:nil
                                              handler:^(UIAction *azione) { [debole importa]; }];
        UIAction *esporta = [UIAction actionWithTitle:NSLocalizedString(@"esporta", nil)
                                                image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                           identifier:nil
                                              handler:^(UIAction *azione) { [debole esporta]; }];
        UIAction *passa = [UIAction actionWithTitle:NSLocalizedString(@"trasferisci", nil)
                                              image:[UIImage systemImageNamed:@"qrcode"]
                                         identifier:nil
                                            handler:^(UIAction *azione) { [debole trasferisci]; }];
        UIAction *impostazioni = [UIAction actionWithTitle:NSLocalizedString(@"impostazioni", nil)
                                                    image:[UIImage systemImageNamed:@"gearshape"]
                                               identifier:nil
                                                  handler:^(UIAction *azione) { [debole apriImpostazioni]; }];
        backup.menu = [UIMenu menuWithTitle:@"" children:@[importa, esporta, passa, impostazioni]];
        backup.target = nil;
        backup.action = nil;
    }

    self.navigationItem.rightBarButtonItem = backup;
}

#pragma mark - Schede e pagine

- (void)preparaSchede
{
    // Vuoto: quali schede ci sono lo decide rifaiLeSchede: guardando le carte,
    // e costruirle qui vorrebbe dire scriverle in due posti.
    self.schede = [[UISegmentedControl alloc] initWithItems:@[]];
    self.schede.selectedSegmentTintColor = [OCTema sopraMarca];
    [self.schede setTitleTextAttributes:@{NSForegroundColorAttributeName: [OCTema sopraMarca]}
                               forState:UIControlStateNormal];
    [self.schede setTitleTextAttributes:@{NSForegroundColorAttributeName: [OCTema marca]}
                               forState:UIControlStateSelected];
    [self.schede addTarget:self action:@selector(schedaCambiata)
          forControlEvents:UIControlEventValueChanged];

    // La barra delle schede continua l'arancione della barra di sistema.
    UIView *sfondo = [UIView new];
    sfondo.backgroundColor = [OCTema marca];
    sfondo.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sfondo];

    self.schede.translatesAutoresizingMaskIntoConstraints = NO;
    [sfondo addSubview:self.schede];

    self.altezzaSchede = [sfondo.heightAnchor constraintEqualToConstant:52];

    [NSLayoutConstraint activateConstraints:@[
        [sfondo.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [sfondo.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [sfondo.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.altezzaSchede,

        [self.schede.centerYAnchor constraintEqualToAnchor:sfondo.centerYAnchor],
        [self.schede.leadingAnchor constraintEqualToAnchor:sfondo.leadingAnchor constant:12],
        [self.schede.trailingAnchor constraintEqualToAnchor:sfondo.trailingAnchor constant:-12],
    ]];

    self.schedeSfondo = sfondo;
}

/// Il campo di ricerca sta fra le schede e le carte, fuori dalle pagine, così
/// non si perde cambiando scheda. Filtra a ogni tasto, e la X del campo lo
/// svuota: la mostra la barra di sistema quando c'è del testo, anche a
/// tastiera chiusa.
- (void)preparaRicerca
{
    self.ricerca = [UISearchBar new];
    self.ricerca.searchBarStyle = UISearchBarStyleMinimal;
    self.ricerca.placeholder = NSLocalizedString(@"cerca_etichetta", nil);
    self.ricerca.delegate = self;
    self.ricerca.searchTextField.clearButtonMode = UITextFieldViewModeAlways;
    self.ricerca.hidden = YES;
    self.ricerca.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.ricerca];

    self.altezzaRicerca = [self.ricerca.heightAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        [self.ricerca.topAnchor constraintEqualToAnchor:self.schedeSfondo.bottomAnchor],
        [self.ricerca.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:4],
        [self.ricerca.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-4],
        self.altezzaRicerca,
    ]];
}

- (void)searchBar:(UISearchBar *)campo textDidChange:(NSString *)testo
{
    NSString *filtro = [testo stringByTrimmingCharactersInSet:
                                  [NSCharacterSet whitespaceCharacterSet]];
    for (OCGruppoViewController *gruppo in self.gruppi) {
        gruppo.filtro = filtro;
    }
}

/// Il tasto di ricerca chiude la tastiera: le carte trovate sono già lì, e la
/// tastiera ne coprirebbe metà.
- (void)searchBarSearchButtonClicked:(UISearchBar *)campo
{
    [campo resignFirstResponder];
}

/// Il campo c'è solo se la scheda aperta ha abbastanza carte, contate prima
/// del filtro. Quando sparisce si svuota, sia che si passi a una scheda più
/// piccola sia che si scenda sotto la soglia eliminando una carta: nascosto,
/// il filtro resterebbe acceso senza che si veda.
- (void)aggiornaRicerca
{
    OCGruppoViewController *aperta = self.pagine.viewControllers.firstObject;
    BOOL conRicerca = aperta.totale > OCCartePerLaRicerca;
    if (!conRicerca && self.ricerca.text.length > 0) {
        self.ricerca.text = @"";
        [self searchBar:self.ricerca textDidChange:@""];
    }
    self.ricerca.hidden = !conRicerca;
    self.altezzaRicerca.constant = conRicerca ? 56 : 0;
}

- (void)preparaPagine
{
    __weak typeof(self) debole = self;

    // Tre schermate sempre pronte: la terza, le preferite, si mostra solo
    // quando c'è qualcosa dentro, ma tenerla viva evita di ricostruirla ogni
    // volta che l'ultima stella si accende o si spegne.
    NSMutableArray<OCGruppoViewController *> *gruppi = [NSMutableArray array];
    for (NSInteger indice = 0; indice < 3; indice++) {
        OCGruppoViewController *gruppo = indice == 2
            ? [[OCGruppoViewController alloc] initPreferite]
            : [[OCGruppoViewController alloc] initConUsaEGetta:(indice == 1)];
        gruppo.suTocco = ^(OCCarta *carta) { [debole apriCarta:carta]; };
        gruppo.suCestino = ^(OCCarta *carta) { [debole confermaEliminazione:carta]; };
        gruppo.suErrore = ^(NSString *messaggio) { [debole avvisa:messaggio]; };
        [gruppi addObject:gruppo];
    }
    self.gruppi = gruppi;

    self.pagine = [[UIPageViewController alloc]
        initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll
          navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
                        options:nil];
    self.pagine.dataSource = self;
    self.pagine.delegate = self;
    [self.pagine setViewControllers:@[self.gruppi.firstObject]
                          direction:UIPageViewControllerNavigationDirectionForward
                           animated:NO
                         completion:nil];

    [self addChildViewController:self.pagine];
    self.pagine.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.pagine.view];
    [self.pagine didMoveToParentViewController:self];

    [NSLayoutConstraint activateConstraints:@[
        [self.pagine.view.topAnchor constraintEqualToAnchor:self.ricerca.bottomAnchor],
        [self.pagine.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.pagine.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.pagine.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

/// Il pulsante di aggiunta sta al centro e staccato dal fondo: sul bordo
/// finirebbe contro la barra di sistema.
- (void)preparaPulsanteAggiungi
{
    self.aggiungi = [UIButton buttonWithType:UIButtonTypeSystem];
    self.aggiungi.backgroundColor = [OCTema marca];
    self.aggiungi.tintColor = [OCTema sopraMarca];
    [self.aggiungi setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    self.aggiungi.layer.cornerRadius = 28;
    self.aggiungi.layer.shadowColor = [UIColor blackColor].CGColor;
    self.aggiungi.layer.shadowOpacity = 0.25;
    self.aggiungi.layer.shadowOffset = CGSizeMake(0, 2);
    self.aggiungi.layer.shadowRadius = 4;
    self.aggiungi.translatesAutoresizingMaskIntoConstraints = NO;
    [self.aggiungi addTarget:self action:@selector(apriAggiunta)
            forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.aggiungi];

    [NSLayoutConstraint activateConstraints:@[
        [self.aggiungi.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.aggiungi.bottomAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [self.aggiungi.widthAnchor constraintEqualToConstant:56],
        [self.aggiungi.heightAnchor constraintEqualToConstant:56],
    ]];
}

#pragma mark - Navigazione fra le schede

/// Le schede nell'ordine in cui stanno adesso.
///
/// Le preferite per prime, così aprendo l'app si vedono subito le carte che si
/// usano di più. Quando non ce ne sono la scheda non c'è e le altre due
/// tornano al loro posto: per questo nessuno deve ragionare per numero, ma
/// sempre passando di qui.
- (NSArray<OCGruppoViewController *> *)ordine
{
    NSMutableArray<OCGruppoViewController *> *quali = [NSMutableArray array];

    if (self.conPreferite) {
        [quali addObject:self.gruppi[2]];
    }
    [quali addObject:self.gruppi[0]];
    if (self.conUsaEGetta) {
        [quali addObject:self.gruppi[1]];
    }
    return quali;
}

- (NSInteger)schedaCorrente
{
    OCGruppoViewController *visibile = self.pagine.viewControllers.firstObject;
    NSInteger indice = [[self ordine] indexOfObject:visibile];
    return indice == NSNotFound ? 0 : indice;
}

- (void)schedaCambiata
{
    NSInteger destinazione = self.schede.selectedSegmentIndex;
    NSInteger corrente = [self schedaCorrente];

    if (destinazione == corrente) {
        return;
    }

    UIPageViewControllerNavigationDirection verso = destinazione > corrente
        ? UIPageViewControllerNavigationDirectionForward
        : UIPageViewControllerNavigationDirectionReverse;

    [self.pagine setViewControllers:@[[self ordine][destinazione]]
                          direction:verso
                           animated:YES
                         completion:nil];
    [self aggiornaRicerca];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pagine
      viewControllerBeforeViewController:(UIViewController *)vista
{
    NSArray<OCGruppoViewController *> *ordine = [self ordine];
    NSInteger indice = [ordine indexOfObject:(OCGruppoViewController *)vista];
    return (indice != NSNotFound && indice > 0) ? ordine[indice - 1] : nil;
}

- (UIViewController *)pageViewController:(UIPageViewController *)pagine
       viewControllerAfterViewController:(UIViewController *)vista
{
    NSArray<OCGruppoViewController *> *ordine = [self ordine];
    NSInteger indice = [ordine indexOfObject:(OCGruppoViewController *)vista];
    return (indice != NSNotFound && indice + 1 < (NSInteger)ordine.count)
        ? ordine[indice + 1] : nil;
}

/// Scorrendo con il dito la scheda in cima si sposta da sola.
- (void)pageViewController:(UIPageViewController *)pagine
        didFinishAnimating:(BOOL)finita
   previousViewControllers:(NSArray<UIViewController *> *)precedenti
       transitionCompleted:(BOOL)completata
{
    if (completata) {
        self.schede.selectedSegmentIndex = [self schedaCorrente];
        [self aggiornaRicerca];
    }
}

#pragma mark - Azioni

- (void)ricaricaTutto
{
    for (OCGruppoViewController *gruppo in self.gruppi) {
        [gruppo ricarica];
    }
    [self aggiornaSchedaPreferite];
    [self aggiornaRicerca];
}

/// Mette e toglie le due schede facoltative, la stella e l'usa e getta.
///
/// La regola è la stessa per tutte e due: senza carte dentro, la scheda non si
/// mostra. Una scheda vuota occupa spazio in cima allo schermo e non serve a
/// niente, e quando ne resta una sola sparisce anche la fila.
///
/// L'ordine conta: se la scheda che sparisce è quella aperta, la pagina va
/// spostata prima, altrimenti resta visibile una schermata che non ha più una
/// scheda sua.
- (void)aggiornaSchedaPreferite
{
    BOOL cePreferite = [OCCore cartePreferite:NULL].count > 0;
    BOOL ceUsaEGetta = [OCCore carteDelGruppo:YES errore:NULL].count > 0;

    if (cePreferite == self.conPreferite && ceUsaEGetta == self.conUsaEGetta) {
        return;
    }

    // Chi stava guardando una scheda deve restare su quella, non trovarsi
    // all'improvviso su un'altra: ci si segna la pagina prima di cambiare.
    OCGruppoViewController *guardava = self.pagine.viewControllers.firstObject;

    self.conPreferite = cePreferite;
    self.conUsaEGetta = ceUsaEGetta;

    NSArray<OCGruppoViewController *> *ordine = [self ordine];

    // La pagina aperta è sparita: si torna a quella principale, che c'è sempre.
    if (![ordine containsObject:guardava]) {
        [self.pagine setViewControllers:@[self.gruppi[0]]
                              direction:UIPageViewControllerNavigationDirectionForward
                               animated:NO
                             completion:nil];
    }

    [self rifaiLeSchede:ordine];
}

/// Rifà i segmenti dall'ordine corrente. Toglierli e rimetterli uno per uno
/// costringerebbe a ragionare per numeri, ed è lì che si sbaglia.
- (void)rifaiLeSchede:(NSArray<OCGruppoViewController *> *)ordine
{
    [self.schede removeAllSegments];

    for (NSUInteger i = 0; i < ordine.count; i++) {
        OCGruppoViewController *gruppo = ordine[i];
        UIImage *stella = [UIImage systemImageNamed:@"star.fill"];

        if (gruppo == self.gruppi[2] && stella != nil) {
            [self.schede insertSegmentWithImage:stella atIndex:i animated:NO];
        } else if (gruppo == self.gruppi[2]) {
            [self.schede insertSegmentWithTitle:NSLocalizedString(@"scheda_preferite", nil)
                                        atIndex:i animated:NO];
        } else if (gruppo == self.gruppi[1]) {
            [self.schede insertSegmentWithTitle:NSLocalizedString(@"scheda_usa_e_getta", nil)
                                        atIndex:i animated:NO];
        } else {
            [self.schede insertSegmentWithTitle:NSLocalizedString(@"scheda_carte", nil)
                                        atIndex:i animated:NO];
        }
    }
    self.schede.selectedSegmentIndex = [self schedaCorrente];

    // Con una scheda sola la fila non dice niente: sparisce, e le carte
    // guadagnano l'altezza.
    BOOL unaSola = ordine.count < 2;
    self.schedeSfondo.hidden = unaSola;
    self.altezzaSchede.constant = unaSola ? 0 : 52;
}

- (void)apriCarta:(OCCarta *)carta
{
    OCDettaglioViewController *dettaglio = [[OCDettaglioViewController alloc]
                                            initConId:carta.identificativo];
    [self.navigationController pushViewController:dettaglio animated:YES];
}

- (void)apriAggiunta
{
    // La casella "usa e getta" parte come la scheda da cui hai premuto il +.
    OCFormViewController *form = [[OCFormViewController alloc]
                                  initPerNuovaConUsaEGetta:([self schedaCorrente] == 1)];

    // Il modulo si apre come foglio, e chiudendolo questa schermata non passa
    // da viewWillAppear: senza questo la carta appena salvata compariva solo
    // cambiando scheda e tornando indietro.
    __weak typeof(self) debole = self;
    form.suSalvataggio = ^{ [debole ricaricaTutto]; };

    UINavigationController *contenitore = [[UINavigationController alloc]
                                           initWithRootViewController:form];
    [self presentViewController:contenitore animated:YES completion:nil];
}

- (void)apriInformazioni
{
    [self.navigationController pushViewController:[OCInfoViewController new] animated:YES];
}

- (void)confermaEliminazione:(OCCarta *)carta
{
    UIAlertController *domanda = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"elimina_titolo", nil)
                         message:[NSString stringWithFormat:NSLocalizedString(@"elimina_domanda", nil), carta.etichetta]
                  preferredStyle:UIAlertControllerStyleAlert];

    [domanda addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"annulla", nil)
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [domanda addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"elimina", nil)
                                                style:UIAlertActionStyleDestructive
                                              handler:^(UIAlertAction *azione) {
        NSError *errore = nil;
        if ([OCCore elimina:carta.identificativo errore:&errore]) {
            [self ricaricaTutto];
        } else {
            [self avvisa:errore.localizedDescription];
        }
    }]];

    [self presentViewController:domanda animated:YES completion:nil];
}

#pragma mark - Backup

/// Esporta e importa, nell'ordine in cui stanno su Android.
- (void)apriMenuBackup
{
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:nil
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];

    [menu addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"importa", nil)
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *azione) { [self importa]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"esporta", nil)
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *azione) { [self esporta]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"trasferisci", nil)
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *azione) { [self trasferisci]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"impostazioni", nil)
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *azione) { [self apriImpostazioni]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"annulla", nil)
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];

    // Su iPad un foglio di azioni deve sapere da dove esce.
    menu.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;

    [self presentViewController:menu animated:YES completion:nil];
}

- (void)esporta
{
    NSError *errore = nil;
    NSArray<OCCarta *> *tutte = [OCCore tutteLeCarte:&errore];

    if (tutte == nil) {
        [self avvisa:errore.localizedDescription];
        return;
    }
    if (tutte.count == 0) {
        [self avvisa:NSLocalizedString(@"niente_da_esportare", nil)];
        return;
    }
    [self chiediFormato:^(BOOL csv) {
        [self chiediPasswordConTitolo:NSLocalizedString(@"password_esporta_titolo", nil)
                            spiegando:NSLocalizedString(@"password_esporta_spiega", nil)
                         vuotoAmmesso:YES
                              bottone:NSLocalizedString(@"salva", nil)
                                  poi:^(NSString *password) {
            [self scriviBackupCsv:csv password:password];
        }];
    }];
}

/// Due formati, come su Android: l'archivio con le foto, oppure il CSV che
/// leggono le altre app.
- (void)chiediFormato:(void (^)(BOOL csv))poi
{
    UIAlertController *scelte = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"esporta_come", nil)
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [scelte addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"esporta_archivio", nil)
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *azione) { poi(NO); }]];
    [scelte addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"esporta_csv", nil)
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *azione) { poi(YES); }]];
    [scelte addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"annulla", nil)
                                               style:UIAlertActionStyleCancel handler:nil]];

    scelte.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:scelte animated:YES completion:nil];
}

/// La password del file. Vuota vuol dire file leggibile, ed è ammesso solo
/// quando si scrive: aprendone uno chiuso, senza password non si va da nessuna
/// parte.
- (void)chiediPasswordConTitolo:(NSString *)titolo
                      spiegando:(NSString *)spiegazione
                   vuotoAmmesso:(BOOL)vuotoAmmesso
                        bottone:(NSString *)bottone
                            poi:(void (^)(NSString *password))poi
{
    UIAlertController *domanda = [UIAlertController alertControllerWithTitle:titolo
                                                                    message:spiegazione
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [domanda addTextFieldWithConfigurationHandler:^(UITextField *campo) {
        campo.secureTextEntry = YES;
        campo.placeholder = NSLocalizedString(@"password", nil);
    }];

    [domanda addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"annulla", nil)
                                                style:UIAlertActionStyleCancel handler:nil]];
    if (vuotoAmmesso) {
        [domanda addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"senza_password", nil)
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction *azione) { poi(@""); }]];
    }
    [domanda addAction:[UIAlertAction actionWithTitle:bottone
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *azione) {
        NSString *scritta = domanda.textFields.firstObject.text ?: @"";
        if (scritta.length == 0 && !vuotoAmmesso) {
            return;
        }
        poi(scritta);
    }]];

    [self presentViewController:domanda animated:YES completion:nil];
}

#pragma mark - Lavoro lungo

/// Esportazione e importazione girano fuori dal thread principale: con una
/// password la chiave si ricava con Argon2 su 32 MiB, e un file preparato ne
/// può chiedere fino a 256, mentre l'interfaccia restava ferma senza dire
/// niente. Intanto c'è la rotella e la finestra non accetta tocchi: così
/// nessun'altra chiamata al core parte dall'interfaccia, e il core resta usato
/// da un thread alla volta, come vuole.
- (void)inizioLavoro
{
    UIActivityIndicatorView *rotella = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    rotella.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    rotella.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                               | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:rotella];
    [rotella startAnimating];
    self.rotella = rotella;
    self.finestraFerma = self.view.window;
    self.finestraFerma.userInteractionEnabled = NO;
}

- (void)fineLavoro
{
    [self.rotella removeFromSuperview];
    self.rotella = nil;
    self.finestraFerma.userInteractionEnabled = YES;
    self.finestraFerma = nil;
}

- (void)scriviBackupCsv:(BOOL)csv password:(NSString *)password
{
    [self inizioLavoro];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *errore = nil;
        // Archivio con le foto o CSV, e la password che chiude tutto: lo fa il
        // core, uguale su Android.
        NSData *contenuto = [OCCore esportaCsv:csv password:password errore:&errore];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self fineLavoro];
            if (contenuto == nil) {
                [self avvisa:errore.localizedDescription];
                return;
            }
            [self offriBackup:contenuto csv:csv password:password];
        });
    });
}

/// Il file esportato, dato al selettore di sistema perché l'utente lo metta
/// dove vuole.
- (void)offriBackup:(NSData *)contenuto csv:(BOOL)csv password:(NSString *)password
{
    // Nome, data ed estensione li sceglie il core, uguali su Android.
    NSString *percorso = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [OCCore nomeEsportazioneCsv:csv password:password]];

    // Il file si scrive in una cartella temporanea e poi lo prende il selettore
    // di sistema: l'utente sceglie dove metterlo, e l'app non chiede nessun
    // permesso sui documenti.
    if (![contenuto writeToFile:percorso atomically:YES]) {
        [self avvisa:NSLocalizedString(@"backup_non_scritto", nil)];
        return;
    }

    UIDocumentPickerViewController *selettore = [[UIDocumentPickerViewController alloc]
        initForExportingURLs:@[[NSURL fileURLWithPath:percorso]] asCopy:YES];
    selettore.delegate = self;
    [self presentViewController:selettore animated:YES completion:nil];
}

- (void)importa
{
    // Nessun filtro sull'estensione: i servizi di archiviazione espongono i
    // file senza un tipo affidabile, e un filtro li nasconderebbe.
    UIDocumentPickerViewController *selettore = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    selettore.delegate = self;
    self.selettoreImporta = selettore;
    [self presentViewController:selettore animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)selettore
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)indirizzi
{
    if (selettore != self.selettoreImporta) {
        [self avvisa:NSLocalizedString(@"backup_salvato", nil)];
        return;
    }

    NSURL *scelto = indirizzi.firstObject;
    if (scelto == nil) {
        return;
    }

    BOOL protetto = [scelto startAccessingSecurityScopedResource];

    /* Il tetto è quello del core, lo stesso dell'esportazione: tiene fuori il
     * file sbagliato scelto per errore, che verrebbe caricato tutto in memoria
     * prima di scoprirlo, e lascia entrare ogni backup uscito dall'app. */
    NSNumber *dimensione = nil;
    [scelto getResourceValue:&dimensione forKey:NSURLFileSizeKey error:NULL];
    if (dimensione != nil && dimensione.longLongValue > [OCCore fileMassimo]) {
        if (protetto) {
            [scelto stopAccessingSecurityScopedResource];
        }
        [self avvisa:[OCCore testoFileTroppoGrande]];
        return;
    }

    NSData *contenuto = [NSData dataWithContentsOfURL:scelto];
    if (protetto) {
        [scelto stopAccessingSecurityScopedResource];
    }

    if (contenuto == nil) {
        [self avvisa:NSLocalizedString(@"backup_non_letto", nil)];
        return;
    }
    [self confermaRipristino:contenuto];
}

- (void)confermaRipristino:(NSData *)contenuto
{
    NSError *errore = nil;
    NSArray<OCCarta *> *tutte = [OCCore tutteLeCarte:&errore];
    BOOL vuoto = tutte != nil && tutte.count == 0;

    // Un CSV è un'altra cosa rispetto a un backup: può aggiungersi alle carte
    // che ci sono, che è quello che vuole chi arriva da un'altra app, oppure
    // prendere il loro posto. Lo decide chi importa, con due risposte che
    // dicono quello che fanno: fino alla 1.0.3 la domanda diceva «Sostituisci»
    // e l'app aggiungeva.
    if ([OCCore tipoFile:contenuto] == OCTipoFileCsv) {
        if (vuoto) {
            [self scriviLeCarte:contenuto password:@"" sostituisciCsv:NO];
            return;
        }
        UIAlertController *scelta = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"csv_titolo", nil)
                             message:NSLocalizedString(@"csv_avviso", nil)
                      preferredStyle:UIAlertControllerStyleAlert];
        [scelta addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"annulla", nil)
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
        [scelta addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"csv_aggiungi", nil)
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *azione) {
            [self scriviLeCarte:contenuto password:@"" sostituisciCsv:NO];
        }]];
        [scelta addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"ripristina_conferma", nil)
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *azione) {
            [self scriviLeCarte:contenuto password:@"" sostituisciCsv:YES];
        }]];
        [self presentViewController:scelta animated:YES completion:nil];
        return;
    }

    // Con zero carte non c'è niente da sostituire: la domanda sarebbe solo un
    // passaggio in più prima di una cosa che non toglie nulla a nessuno.
    if (vuoto) {
        [self chiediPasswordSeServe:contenuto];
        return;
    }

    UIAlertController *domanda = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"ripristina_titolo", nil)
                         message:NSLocalizedString(@"ripristina_avviso", nil)
                  preferredStyle:UIAlertControllerStyleAlert];

    [domanda addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"annulla", nil)
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [domanda addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"ripristina_conferma", nil)
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *azione) {
        [self chiediPasswordSeServe:contenuto];
    }]];

    [self presentViewController:domanda animated:YES completion:nil];
}

/// La password si chiede solo se il file ce l'ha: chi non l'ha mai usata non
/// vede niente di nuovo.
- (void)chiediPasswordSeServe:(NSData *)contenuto
{
    // Qui si arriva dopo «Sostituisci», o senza carte: anche un CSV chiuso con
    // la password prende il posto di quelle che ci sono. Con NO si aggiungeva,
    // e le carte finivano doppie.
    if ([OCCore tipoFile:contenuto] != OCTipoFileCifrato) {
        [self scriviLeCarte:contenuto password:@"" sostituisciCsv:YES];
        return;
    }
    [self chiediPasswordConTitolo:NSLocalizedString(@"password_apri_titolo", nil)
                        spiegando:NSLocalizedString(@"password_apri_spiega", nil)
                     vuotoAmmesso:NO
                          // Qui non si salva niente: si apre un file che c'è già.
                          bottone:NSLocalizedString(@"apri", nil)
                              poi:^(NSString *password) {
        [self scriviLeCarte:contenuto password:password sostituisciCsv:YES];
    }];
}

- (void)scriviLeCarte:(NSData *)dati password:(NSString *)password sostituisciCsv:(BOOL)sostituisciCsv
{
    [self inizioLavoro];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *errore = nil;
        // Archivio, CSV o JSON, con o senza password: il core riconosce il
        // file, rimette a posto le foto e scrive le carte in una volta.
        NSInteger quante = [OCCore importa:dati
                                  password:password
                               sostituisci:sostituisciCsv
                                    errore:&errore];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self fineLavoro];
            if (quante < 0) {
                [self avvisa:errore.localizedDescription];
                return;
            }
            [self ricaricaTutto];
            /* Il singolare e il plurale li sceglie il sistema, dal
             * .stringsdict: ci sono lingue dove le forme non sono due. */
            [self avvisa:[NSString localizedStringWithFormat:
                          NSLocalizedString(@"carte_ripristinate", nil), (long)quante]];
        });
    });
}

- (void)apriImpostazioni
{
    OCImpostazioniViewController *schermo = [OCImpostazioniViewController new];
    __weak typeof(self) debole = self;
    schermo.suCarteAzzerate = ^{ [debole ricaricaTutto]; };
    UINavigationController *contenitore =
        [[UINavigationController alloc] initWithRootViewController:schermo];
    [self presentViewController:contenitore animated:YES completion:nil];
}

/// Passaggio delle carte fra due telefoni con i QR.
- (void)trasferisci
{
    OCTrasferimentoViewController *passaggio = [OCTrasferimentoViewController new];

    __weak typeof(self) debole = self;
    passaggio.suRicevute = ^(NSInteger quante) {
        [debole ricaricaTutto];
        [debole avvisa:[NSString localizedStringWithFormat:
                        NSLocalizedString(@"carte_ricevute", nil), (long)quante]];
    };

    UINavigationController *contenitore =
        [[UINavigationController alloc] initWithRootViewController:passaggio];
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
