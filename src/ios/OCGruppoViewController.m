// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCGruppoViewController.h"

#import "OCCartaCella.h"
#import "OCCore.h"
#import "OCTema.h"

static NSString *const OCRiusoCella = @"carta";

NSString *const OCChiaveDueColonne = @"due_colonne";

@interface OCGruppoViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView *griglia;
@property (nonatomic, strong) UILabel *vuoto;
@property (nonatomic, strong) NSMutableArray<OCCarta *> *carte;
@end

@implementation OCGruppoViewController

- (instancetype)initConUsaEGetta:(BOOL)usaEGetta
{
    self = [super initWithNibName:nil bundle:nil];
    if (self != nil) {
        _usaEGetta = usaEGetta;
        _carte = [NSMutableArray array];
        _filtro = @"";
    }
    return self;
}

- (instancetype)initPreferite
{
    self = [self initConUsaEGetta:NO];
    if (self != nil) {
        _preferite = YES;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UICollectionViewFlowLayout *disposizione = [UICollectionViewFlowLayout new];
    disposizione.minimumLineSpacing = 0;
    // Su due colonne le schede si toccano: lo spazio fra loro lo fanno i
    // margini della cella, come fra una fila e l'altra.
    disposizione.minimumInteritemSpacing = 0;
    // Lo spazio in fondo lascia respiro all'ultima carta, che altrimenti
    // finirebbe sotto il pulsante di aggiunta.
    disposizione.sectionInset = UIEdgeInsetsMake(8, 0, 96, 0);

    self.griglia = [[UICollectionView alloc] initWithFrame:CGRectZero
                                      collectionViewLayout:disposizione];
    self.griglia.backgroundColor = [UIColor clearColor];
    self.griglia.dataSource = self;
    self.griglia.delegate = self;
    self.griglia.alwaysBounceVertical = YES;
    [self.griglia registerClass:[OCCartaCella class] forCellWithReuseIdentifier:OCRiusoCella];
    self.griglia.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.griglia];

    self.vuoto = [UILabel new];
    self.vuoto.numberOfLines = 0;
    self.vuoto.textAlignment = NSTextAlignmentCenter;
    self.vuoto.textColor = [OCTema tenue];
    self.vuoto.font = [UIFont systemFontOfSize:16];
    self.vuoto.hidden = YES;
    self.vuoto.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.vuoto];

    [NSLayoutConstraint activateConstraints:@[
        [self.griglia.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.griglia.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.griglia.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.griglia.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.vuoto.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.vuoto.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.vuoto.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.vuoto.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
    ]];

    // Pressione prolungata per trascinare, come su Android. L'ordine si salva
    // quando si lascia la presa, non a ogni scambio: altrimenti il file dei
    // dati verrebbe riscritto decine di volte per un movimento solo.
    UILongPressGestureRecognizer *trascina = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(trascinamento:)];
    [self.griglia addGestureRecognizer:trascina];
}

- (void)viewWillAppear:(BOOL)animato
{
    [super viewWillAppear:animato];
    [self ricarica];
}

- (void)setFiltro:(NSString *)filtro
{
    _filtro = [filtro copy];
    [self ricarica];
}

/// Il messaggio della lista vuota: mentre si cerca dice che non si è trovato
/// niente, e non che la scheda è ancora da riempire.
- (NSString *)testoVuoto
{
    if (self.filtro.length > 0) {
        return NSLocalizedString(@"nessuna_trovata", nil);
    }
    if (self.preferite) {
        return NSLocalizedString(@"nessuna_preferita", nil);
    }
    if (self.usaEGetta) {
        return NSLocalizedString(@"nessuna_usa_e_getta", nil);
    }
    return NSLocalizedString(@"nessuna_carta", nil);
}

- (void)ricarica
{
    NSError *errore = nil;
    NSArray<OCCarta *> *carte = self.preferite
        ? [OCCore cartePreferite:&errore]
        : [OCCore carteDelGruppo:self.usaEGetta errore:&errore];

    if (carte == nil) {
        if (self.suErrore != nil) {
            self.suErrore(errore.localizedDescription);
        }
        return;
    }

    _totale = carte.count;

    // L'etichetta deve contenere il testo cercato, in qualunque punto.
    // Maiuscole e accenti non contano: chi scrive «caffe» trova «Caffè».
    if (self.filtro.length > 0) {
        NSString *cercato = self.filtro;
        NSPredicate *contiene = [NSPredicate predicateWithBlock:^BOOL(OCCarta *carta, NSDictionary *legami) {
            return [carta.etichetta ?: @"" rangeOfString:cercato
                                                 options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch]
                       .location != NSNotFound;
        }];
        carte = [carte filteredArrayUsingPredicate:contiene];
    }

    self.carte = [carte mutableCopy];
    self.vuoto.text = [self testoVuoto];
    self.vuoto.hidden = self.carte.count > 0;
    [self.griglia reloadData];
}

#pragma mark - Contenuto

- (NSInteger)collectionView:(UICollectionView *)griglia numberOfItemsInSection:(NSInteger)sezione
{
    return self.carte.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)griglia
                  cellForItemAtIndexPath:(NSIndexPath *)posizione
{
    OCCartaCella *cella = [griglia dequeueReusableCellWithReuseIdentifier:OCRiusoCella
                                                             forIndexPath:posizione];
    OCCarta *carta = self.carte[posizione.item];
    [cella mostra:carta
       conCestino:self.usaEGetta
         aTessera:[[NSUserDefaults standardUserDefaults] boolForKey:OCChiaveDueColonne]];

    __weak typeof(self) debole = self;
    cella.suCestino = ^(OCCarta *daEliminare) {
        if (debole.suCestino != nil) {
            debole.suCestino(daEliminare);
        }
    };
    return cella;
}

/// La scheda cresce col nome, come su Android, dove l'altezza è wrap_content:
/// un nome lungo va a capo invece di sparire. Lo spazio tolto al nome è quello
/// che occupano i margini della scheda, il glifo e il cestino.
- (CGSize)collectionView:(UICollectionView *)griglia
                  layout:(UICollectionViewLayout *)disposizione
  sizeForItemAtIndexPath:(NSIndexPath *)posizione
{
    BOOL dueColonne = [[NSUserDefaults standardUserDefaults] boolForKey:OCChiaveDueColonne];
    CGFloat larghezza = CGRectGetWidth(griglia.bounds);

    if (!dueColonne) {
        return CGSizeMake(larghezza, [self altezzaDi:posizione.item larghezza:larghezza]);
    }

    // Su due colonne le schede della stessa fila sono alte uguali: quella
    // del nome più lungo decide per tutte e due.
    CGFloat mezza = floor(larghezza / 2);
    NSInteger prima = posizione.item - posizione.item % 2;
    CGFloat altezza = [self altezzaATesseraDi:prima larghezza:mezza];
    if (prima + 1 < (NSInteger)self.carte.count) {
        altezza = MAX(altezza, [self altezzaATesseraDi:prima + 1 larghezza:mezza]);
    }
    return CGSizeMake(mezza, altezza);
}

/// Quanto è alto il nome di una carta, scritto largo al massimo `larghezza`.
- (CGFloat)altezzaNomeDi:(NSInteger)indice larghezza:(CGFloat)larghezza
{
    NSString *etichetta = self.carte[indice].etichetta ?: @"";

    CGRect misura = [etichetta boundingRectWithSize:CGSizeMake(larghezza, CGFLOAT_MAX)
                                            options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:@{NSFontAttributeName:
                                                          [UIFont boldSystemFontOfSize:18]}
                                            context:nil];
    return ceil(CGRectGetHeight(misura));
}

- (CGFloat)altezzaDi:(NSInteger)indice larghezza:(CGFloat)larghezza
{
    // 32 sono i margini interni della scheda, 12 quelli fra una scheda e
    // l'altra; il glifo è alto 28 e da solo tiene aperta la riga.
    return MAX([self altezzaNomeDi:indice larghezza:larghezza - 128], 28) + 32 + 12;
}

/// A tessera il nome sta sotto il glifo, largo quanto la scheda meno i
/// margini: 24 fuori e 32 dentro. In altezza 16 + 28 del glifo + 8 sopra il
/// nome, 16 sotto e i soliti 12 fra una scheda e l'altra.
- (CGFloat)altezzaATesseraDi:(NSInteger)indice larghezza:(CGFloat)larghezza
{
    return [self altezzaNomeDi:indice larghezza:larghezza - 56] + 16 + 28 + 8 + 16 + 12;
}

- (void)collectionView:(UICollectionView *)griglia didSelectItemAtIndexPath:(NSIndexPath *)posizione
{
    if (self.suTocco != nil) {
        self.suTocco(self.carte[posizione.item]);
    }
}

#pragma mark - Riordino

- (BOOL)collectionView:(UICollectionView *)griglia canMoveItemAtIndexPath:(NSIndexPath *)posizione
{
    // Nella scheda con la stella no: le preferite arrivano dai due gruppi, che
    // hanno due ordini loro, e riordinare qui vorrebbe dire inventarne un terzo
    // che poi nessuno rilegge.
    //
    // E neanche mentre si cerca: l'ordine salvato sarebbe quello delle sole
    // carte visibili, e le altre uscirebbero dall'elenco.
    return !self.preferite && self.filtro.length == 0;
}

- (void)collectionView:(UICollectionView *)griglia
   moveItemAtIndexPath:(NSIndexPath *)da
           toIndexPath:(NSIndexPath *)a
{
    OCCarta *carta = self.carte[da.item];
    [self.carte removeObjectAtIndex:da.item];
    [self.carte insertObject:carta atIndex:a.item];
}

- (void)trascinamento:(UILongPressGestureRecognizer *)gesto
{
    // Il gesto arriva lo stesso anche dove non si riordina: senza questo, al
    // rilascio si salverebbe l'ordine della lista filtrata.
    if (self.filtro.length > 0) {
        return;
    }

    CGPoint punto = [gesto locationInView:self.griglia];

    switch (gesto.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath *posizione = [self.griglia indexPathForItemAtPoint:punto];
            if (posizione != nil) {
                [self.griglia beginInteractiveMovementForItemAtIndexPath:posizione];
            }
            break;
        }
        case UIGestureRecognizerStateChanged:
            [self.griglia updateInteractiveMovementTargetPosition:punto];
            break;
        case UIGestureRecognizerStateEnded:
            [self.griglia endInteractiveMovement];
            [self salvaOrdine];
            break;
        default:
            [self.griglia cancelInteractiveMovement];
            break;
    }
}

- (void)salvaOrdine
{
    NSMutableArray<NSNumber *> *ids = [NSMutableArray arrayWithCapacity:self.carte.count];
    for (OCCarta *carta in self.carte) {
        [ids addObject:@(carta.identificativo)];
    }

    NSError *errore = nil;
    if (![OCCore riordina:self.usaEGetta identificativi:ids errore:&errore] && self.suErrore != nil) {
        self.suErrore(errore.localizedDescription);
    }
}

@end
