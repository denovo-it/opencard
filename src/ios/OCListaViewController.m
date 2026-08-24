// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCListaViewController.h"

#import "OCCore.h"
#import "OCDettaglioViewController.h"
#import "OCFormViewController.h"
#import "OCGruppoViewController.h"
#import "OCInfoViewController.h"
#import "OCTema.h"
#import "OCTrasferimentoViewController.h"

@interface OCListaViewController () <UIPageViewControllerDataSource, UIPageViewControllerDelegate,
                                     UIDocumentPickerDelegate>
@property (nonatomic, strong) UISegmentedControl *schede;
@property (nonatomic, strong) UIPageViewController *pagine;
@property (nonatomic, strong) NSArray<OCGruppoViewController *> *gruppi;
@property (nonatomic, strong) UIButton *aggiungi;
@property (nonatomic, strong) UIView *schedeSfondo;
/// Vero quando la scheda con la stella è in mezzo alle altre.
@property (nonatomic, assign) BOOL conPreferite;
/// Vero fino alla prima comparsa: serve a distinguere l'apertura dell'app dal
/// ritorno da una carta, dove la scheda aperta va lasciata dov'era.
@property (nonatomic, assign) BOOL primaApertura;
- (void)importa;
- (void)esporta;
- (void)trasferisci;
@end

@implementation OCListaViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.primaApertura = YES;

    [self preparaBarra];
    [self preparaSchede];
    [self preparaPagine];
    [self preparaPulsanteAggiungi];
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
}

#pragma mark - Barra

/// Il marchio prende il posto del titolo, come su Android, e sta al centro da
/// solo: la sigla del canale la dicono la schermata di avvio e le note di
/// rilascio.
- (void)preparaBarra
{
    UIImage *marca = [UIImage imageNamed:@"opencard_appbar"];

    if (marca != nil) {
        UIImageView *vista = [[UIImageView alloc] initWithImage:marca];
        vista.contentMode = UIViewContentModeScaleAspectFit;
        vista.frame = CGRectMake(0, 0, 92, 34);
        self.navigationItem.titleView = vista;
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
        UIAction *importa = [UIAction actionWithTitle:@"Importa da file"
                                                image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                           identifier:nil
                                              handler:^(UIAction *azione) { [debole importa]; }];
        UIAction *esporta = [UIAction actionWithTitle:@"Esporta su file"
                                                image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                           identifier:nil
                                              handler:^(UIAction *azione) { [debole esporta]; }];
        UIAction *passa = [UIAction actionWithTitle:@"Copia tra telefoni"
                                              image:[UIImage systemImageNamed:@"qrcode"]
                                         identifier:nil
                                            handler:^(UIAction *azione) { [debole trasferisci]; }];
        backup.menu = [UIMenu menuWithTitle:@"" children:@[importa, esporta, passa]];
        backup.target = nil;
        backup.action = nil;
    }

    self.navigationItem.rightBarButtonItem = backup;
}

#pragma mark - Schede e pagine

- (void)preparaSchede
{
    self.schede = [[UISegmentedControl alloc] initWithItems:@[@"Carte", @"Usa & getta"]];
    self.schede.selectedSegmentIndex = 0;
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

    [NSLayoutConstraint activateConstraints:@[
        [sfondo.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [sfondo.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [sfondo.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [sfondo.heightAnchor constraintEqualToConstant:52],

        [self.schede.centerYAnchor constraintEqualToAnchor:sfondo.centerYAnchor],
        [self.schede.leadingAnchor constraintEqualToAnchor:sfondo.leadingAnchor constant:12],
        [self.schede.trailingAnchor constraintEqualToAnchor:sfondo.trailingAnchor constant:-12],
    ]];

    self.schedeSfondo = sfondo;
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
        [self.pagine.view.topAnchor constraintEqualToAnchor:self.schedeSfondo.bottomAnchor],
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
    if (!self.conPreferite) {
        return @[self.gruppi[0], self.gruppi[1]];
    }
    return @[self.gruppi[2], self.gruppi[0], self.gruppi[1]];
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
    }
}

#pragma mark - Azioni

- (void)ricaricaTutto
{
    for (OCGruppoViewController *gruppo in self.gruppi) {
        [gruppo ricarica];
    }
    [self aggiornaSchedaPreferite];
}

/// Mette o toglie la scheda con la stella.
///
/// L'ordine conta: se la scheda sparisce mentre è quella aperta, la pagina va
/// spostata prima, altrimenti resta visibile una schermata che non ha più una
/// scheda sua.
- (void)aggiornaSchedaPreferite
{
    NSArray<OCCarta *> *preferite = [OCCore cartePreferite:NULL];
    BOOL servono = preferite.count > 0;

    if (servono == self.conPreferite) {
        return;
    }
    self.conPreferite = servono;

    // La scheda con la stella è la prima: aggiungerla e toglierla sposta le
    // altre, quindi la pagina visibile va rimessa dov'è finita.
    if (servono) {
        UIImage *stella = [UIImage systemImageNamed:@"star.fill"];
        if (stella != nil) {
            [self.schede insertSegmentWithImage:stella atIndex:0 animated:YES];
        } else {
            [self.schede insertSegmentWithTitle:@"Preferite" atIndex:0 animated:YES];
        }
        self.schede.selectedSegmentIndex = [self schedaCorrente];
        return;
    }

    if (self.pagine.viewControllers.firstObject == self.gruppi[2]) {
        [self.pagine setViewControllers:@[self.gruppi[0]]
                              direction:UIPageViewControllerNavigationDirectionForward
                               animated:NO
                             completion:nil];
    }
    if (self.schede.numberOfSegments > 2) {
        [self.schede removeSegmentAtIndex:0 animated:YES];
    }
    self.schede.selectedSegmentIndex = [self schedaCorrente];
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
        alertControllerWithTitle:@"Elimina codice"
                         message:[NSString stringWithFormat:@"Eliminare \"%@\"?", carta.etichetta]
                  preferredStyle:UIAlertControllerStyleAlert];

    [domanda addAction:[UIAlertAction actionWithTitle:@"Annulla"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [domanda addAction:[UIAlertAction actionWithTitle:@"Elimina"
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

    [menu addAction:[UIAlertAction actionWithTitle:@"Importa da file"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *azione) { [self importa]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Esporta su file"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *azione) { [self esporta]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Copia tra telefoni"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *azione) { [self trasferisci]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Annulla"
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
        [self avvisa:@"Non c'è ancora nessuna carta da esportare."];
        return;
    }

    NSData *contenuto = [OCCore esportaBackup:&errore];
    if (contenuto == nil) {
        [self avvisa:errore.localizedDescription];
        return;
    }

    // Il file si scrive in una cartella temporanea e poi lo prende il
    // selettore di sistema: l'utente sceglie dove metterlo, e l'app non
    // chiede nessun permesso sui documenti.
    NSString *percorso = [NSTemporaryDirectory() stringByAppendingPathComponent:[OCCore nomeBackup]];
    if (![contenuto writeToFile:percorso atomically:YES]) {
        [self avvisa:@"Esportazione non riuscita."];
        return;
    }

    UIDocumentPickerViewController *selettore = [[UIDocumentPickerViewController alloc]
        initWithURL:[NSURL fileURLWithPath:percorso] inMode:UIDocumentPickerModeExportToService];
    selettore.delegate = self;
    [self presentViewController:selettore animated:YES completion:nil];
}

- (void)importa
{
    // Nessun filtro sull'estensione: i servizi di archiviazione espongono i
    // file senza un tipo affidabile, e un filtro li nasconderebbe.
    UIDocumentPickerViewController *selettore = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.item"] inMode:UIDocumentPickerModeImport];
    selettore.delegate = self;
    [self presentViewController:selettore animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)selettore
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)indirizzi
{
    if (selettore.documentPickerMode != UIDocumentPickerModeImport) {
        [self avvisa:@"Carte esportate."];
        return;
    }

    NSURL *scelto = indirizzi.firstObject;
    if (scelto == nil) {
        return;
    }

    BOOL protetto = [scelto startAccessingSecurityScopedResource];

    /* Un backup vero pesa qualche decina di kilobyte: dieci megabyte coprono
     * qualsiasi caso reale. Il tetto tiene fuori il file sbagliato scelto per
     * errore, che verrebbe caricato tutto in memoria prima di scoprirlo. */
    NSNumber *dimensione = nil;
    [scelto getResourceValue:&dimensione forKey:NSURLFileSizeKey error:NULL];
    if (dimensione != nil && dimensione.longLongValue > 10 * 1024 * 1024) {
        if (protetto) {
            [scelto stopAccessingSecurityScopedResource];
        }
        [self avvisa:@"Il file è troppo grande per essere un backup di OpenCard."];
        return;
    }

    NSData *contenuto = [NSData dataWithContentsOfURL:scelto];
    if (protetto) {
        [scelto stopAccessingSecurityScopedResource];
    }

    if (contenuto == nil) {
        [self avvisa:@"Non sono riuscito a leggere il file."];
        return;
    }
    [self confermaRipristino:contenuto];
}

- (void)confermaRipristino:(NSData *)contenuto
{
    UIAlertController *domanda = [UIAlertController
        alertControllerWithTitle:@"Sostituire le carte?"
                         message:@"Le carte che hai adesso vengono sostituite da quelle del backup."
                  preferredStyle:UIAlertControllerStyleAlert];

    [domanda addAction:[UIAlertAction actionWithTitle:@"Annulla"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [domanda addAction:[UIAlertAction actionWithTitle:@"Sostituisci"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *azione) {
        NSError *errore = nil;
        NSInteger quante = [OCCore ripristinaBackup:contenuto errore:&errore];

        if (quante < 0) {
            [self avvisa:errore.localizedDescription];
            return;
        }
        [self ricaricaTutto];
        [self avvisa:quante == 1 ? @"Ripristinata una carta."
                                 : [NSString stringWithFormat:@"Ripristinate %ld carte.", (long)quante]];
    }]];

    [self presentViewController:domanda animated:YES completion:nil];
}

/// Passaggio delle carte fra due telefoni con i QR.
- (void)trasferisci
{
    OCTrasferimentoViewController *passaggio = [OCTrasferimentoViewController new];

    __weak typeof(self) debole = self;
    passaggio.suRicevute = ^(NSInteger quante) {
        [debole ricaricaTutto];
        [debole avvisa:quante == 1
            ? @"Ricevuta una carta."
            : [NSString stringWithFormat:@"Ricevute %ld carte.", (long)quante]];
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
