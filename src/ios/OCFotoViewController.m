// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCFotoViewController.h"

@interface OCFotoViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *immagine;
@property (nonatomic, copy) NSString *titoloFoto;
@property (nonatomic, strong) UIScrollView *scorrevole;
@property (nonatomic, strong) UIImageView *vista;
@end

@implementation OCFotoViewController

- (instancetype)initConImmagine:(UIImage *)immagine titolo:(NSString *)titolo
{
    self = [super initWithNibName:nil bundle:nil];
    if (self != nil) {
        _immagine = immagine;
        _titoloFoto = titolo;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Fondo nero: la foto di una tessera si legge meglio senza niente intorno.
    self.view.backgroundColor = [UIColor blackColor];
    self.title = self.titoloFoto;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                             target:self
                             action:@selector(chiudi)];

    self.scorrevole = [UIScrollView new];
    self.scorrevole.delegate = self;
    self.scorrevole.minimumZoomScale = 1;
    self.scorrevole.maximumZoomScale = 6;
    self.scorrevole.showsHorizontalScrollIndicator = NO;
    self.scorrevole.showsVerticalScrollIndicator = NO;
    self.scorrevole.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scorrevole];

    self.vista = [[UIImageView alloc] initWithImage:self.immagine];
    self.vista.contentMode = UIViewContentModeScaleAspectFit;
    self.vista.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scorrevole addSubview:self.vista];

    // Due tocchi ingrandiscono e rimpiccioliscono: è il gesto che su iPhone si
    // prova per primo, e senza sembra che lo zoom non ci sia.
    UITapGestureRecognizer *doppio = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(doppioTocco:)];
    doppio.numberOfTapsRequired = 2;
    [self.vista addGestureRecognizer:doppio];
    self.vista.userInteractionEnabled = YES;

    UILayoutGuide *area = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scorrevole.topAnchor constraintEqualToAnchor:area.topAnchor],
        [self.scorrevole.bottomAnchor constraintEqualToAnchor:area.bottomAnchor],
        [self.scorrevole.leadingAnchor constraintEqualToAnchor:area.leadingAnchor],
        [self.scorrevole.trailingAnchor constraintEqualToAnchor:area.trailingAnchor],

        [self.vista.topAnchor constraintEqualToAnchor:self.scorrevole.topAnchor],
        [self.vista.bottomAnchor constraintEqualToAnchor:self.scorrevole.bottomAnchor],
        [self.vista.leadingAnchor constraintEqualToAnchor:self.scorrevole.leadingAnchor],
        [self.vista.trailingAnchor constraintEqualToAnchor:self.scorrevole.trailingAnchor],
        [self.vista.widthAnchor constraintEqualToAnchor:self.scorrevole.widthAnchor],
        [self.vista.heightAnchor constraintEqualToAnchor:self.scorrevole.heightAnchor],
    ]];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scorrevole
{
    (void)scorrevole;
    return self.vista;
}

- (void)doppioTocco:(UITapGestureRecognizer *)gesto
{
    if (self.scorrevole.zoomScale > 1.01) {
        [self.scorrevole setZoomScale:1 animated:YES];
        return;
    }
    CGPoint dove = [gesto locationInView:self.vista];
    CGFloat lato = self.scorrevole.bounds.size.width / 3;
    [self.scorrevole zoomToRect:CGRectMake(dove.x - lato / 2, dove.y - lato / 2, lato, lato)
                       animated:YES];
}

- (void)chiudi
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
