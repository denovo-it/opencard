// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCGruppoViewController.h"

#import "OCCartaCella.h"
#import "OCCore.h"
#import "OCTema.h"

static NSString *const OCRiusoCella = @"carta";

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
    if (self.preferite) {
        self.vuoto.text = @"Qui finiscono le carte con la stella.";
    } else if (self.usaEGetta) {
        self.vuoto.text = @"Qui finiscono i buoni e i codici che si usano una volta sola.";
    } else {
        self.vuoto.text = @"Non hai ancora salvato nessuna carta.\nTocca il pulsante + per aggiungerne una.";
    }
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

    self.carte = [carte mutableCopy];
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
    [cella mostra:carta conCestino:self.usaEGetta];

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
    CGFloat larghezza = CGRectGetWidth(griglia.bounds);
    CGFloat perIlNome = larghezza - 128;
    NSString *etichetta = self.carte[posizione.item].etichetta ?: @"";

    CGRect misura = [etichetta boundingRectWithSize:CGSizeMake(perIlNome, CGFLOAT_MAX)
                                            options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:@{NSFontAttributeName:
                                                          [UIFont boldSystemFontOfSize:18]}
                                            context:nil];

    // 32 sono i margini interni della scheda, 12 quelli fra una scheda e
    // l'altra; il glifo è alto 28 e da solo tiene aperta la riga.
    CGFloat altezza = MAX(ceil(CGRectGetHeight(misura)), 28) + 32 + 12;
    return CGSizeMake(larghezza, altezza);
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
    return !self.preferite;
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
