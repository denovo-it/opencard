// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCFormViewController.h"

#import <Vision/Vision.h>

#import "OCCore.h"
#import "OCScannerViewController.h"
#import "OCTema.h"

/// Gli stessi colori che assegna il core, per la scelta a mano.
static NSArray<NSString *> *OCColoriScelta(void)
{
    return @[@"#E53935", @"#8E24AA", @"#1E88E5", @"#00897B", @"#43A047", @"#FB8C00",
             @"#6D4C41", @"#039BE5", @"#D81B60", @"#3949AB", @"#00ACC1", @"#7CB342"];
}

/// Gli stessi limiti del form Android (`activity_form.xml`): oltre, il core
/// taglierebbe in silenzio e la carta arriverebbe monca senza che si veda.
static const NSUInteger OCLimiteNome = 120;
static const NSUInteger OCLimiteCodice = 500;

@interface OCFormViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate,
                                    UIDocumentPickerDelegate, UITextFieldDelegate>
@property (nonatomic, assign) NSInteger identificativo;
@property (nonatomic, assign) BOOL usaEGetta;
@property (nonatomic, copy, nullable) NSString *coloreScelto;
@property (nonatomic, copy) NSString *coloreProposto;

@property (nonatomic, strong) UITextField *nome;
@property (nonatomic, strong) UITextField *codice;
@property (nonatomic, strong) UISegmentedControl *tipo;
@property (nonatomic, strong) UISwitch *interruttore;
/// La stella si accende anche da qui, oltre che dalla carta aperta: chi sta
/// già modificando non deve uscire e rientrare.
@property (nonatomic, strong) UISwitch *stella;
@property (nonatomic, strong) UIStackView *tavolozza;
@property (nonatomic, strong) UIScrollView *scorrevole;
@property (nonatomic, strong) UILabel *errore;
@property (nonatomic, strong) UIButton *elimina;
@end

@implementation OCFormViewController

- (instancetype)initPerNuovaConUsaEGetta:(BOOL)usaEGetta
{
    self = [super initWithNibName:nil bundle:nil];
    if (self != nil) {
        _identificativo = 0;
        _usaEGetta = usaEGetta;
        _coloreProposto = [OCCore colorePerId:[OCCore prossimoId]];
    }
    return self;
}

- (instancetype)initPerModificaConId:(NSInteger)identificativo
{
    self = [super initWithNibName:nil bundle:nil];
    if (self != nil) {
        _identificativo = identificativo;
        _coloreProposto = @"#E6642B";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = self.identificativo == 0 ? @"Aggiungi" : @"Modifica";

    // Annulla e Salva in cima: in fondo finivano sotto la tastiera quando un
    // campo aveva il fuoco.
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Annulla" style:UIBarButtonItemStylePlain
               target:self action:@selector(chiudi)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Salva" style:UIBarButtonItemStyleDone
               target:self action:@selector(salva)];

    [self costruisciModulo];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tastieraCambiata:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];

    if (self.identificativo != 0) {
        [self carica];
    } else {
        self.interruttore.on = self.usaEGetta;
        [self aggiornaTavolozza];
    }
}

#pragma mark - Costruzione

- (UITextField *)campoConSegnaposto:(NSString *)segnaposto
{
    UITextField *campo = [UITextField new];
    campo.placeholder = segnaposto;
    campo.borderStyle = UITextBorderStyleRoundedRect;
    campo.autocorrectionType = UITextAutocorrectionTypeNo;
    campo.clearButtonMode = UITextFieldViewModeWhileEditing;
    campo.delegate = self;
    campo.inputAccessoryView = [self barraTastiera];
    return campo;
}

/// Ferma la scrittura e l'incolla oltre il limite del campo.
- (BOOL)textField:(UITextField *)campo
    shouldChangeCharactersInRange:(NSRange)intervallo
                replacementString:(NSString *)testo
{
    NSUInteger limite = campo == self.nome ? OCLimiteNome : OCLimiteCodice;
    return campo.text.length - intervallo.length + testo.length <= limite;
}

- (UIButton *)bottoneAcquisizione:(NSString *)testo
                          simbolo:(NSString *)simbolo
                           azione:(SEL)azione
{
    UIButton *bottone = [UIButton buttonWithType:UIButtonTypeSystem];
    [bottone setTitle:testo forState:UIControlStateNormal];
    [bottone setImage:[UIImage systemImageNamed:simbolo] forState:UIControlStateNormal];
    bottone.titleLabel.font = [UIFont systemFontOfSize:12];
    bottone.tintColor = [OCTema marca];
    bottone.backgroundColor = [[OCTema marca] colorWithAlphaComponent:0.1];
    bottone.layer.cornerRadius = 10;
    [bottone addTarget:self action:azione forControlEvents:UIControlEventTouchUpInside];

    // Icona sopra ed etichetta sotto: affiancate, su un telefono stretto la
    // scritta verrebbe troncata.
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configurazione = [UIButtonConfiguration plainButtonConfiguration];
        configurazione.imagePlacement = NSDirectionalRectEdgeTop;
        configurazione.imagePadding = 4;
        configurazione.title = testo;
        configurazione.image = [UIImage systemImageNamed:simbolo];
        bottone.configuration = configurazione;
    }
    [bottone.heightAnchor constraintEqualToConstant:60].active = YES;
    return bottone;
}

- (void)costruisciModulo
{
    // Le stesse due parole che Android mette come etichetta dei campi.
    self.nome = [self campoConSegnaposto:@"Etichetta"];
    self.codice = [self campoConSegnaposto:@"Codice"];
    self.codice.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightRegular];

    // Dall'etichetta si passa al codice, dal codice la tastiera si chiude.
    self.nome.returnKeyType = UIReturnKeyNext;
    self.codice.returnKeyType = UIReturnKeyDone;

    self.tipo = [[UISegmentedControl alloc] initWithItems:@[@"Barcode", @"QR code"]];
    self.tipo.selectedSegmentIndex = 0;

    UIStackView *acquisizione = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self bottoneAcquisizione:@"Foto" simbolo:@"camera" azione:@selector(daFotocamera)],
        [self bottoneAcquisizione:@"Galleria" simbolo:@"photo" azione:@selector(daGalleria)],
        [self bottoneAcquisizione:@"File" simbolo:@"folder" azione:@selector(daFile)],
    ]];
    acquisizione.axis = UILayoutConstraintAxisHorizontal;
    acquisizione.distribution = UIStackViewDistributionFillEqually;
    acquisizione.spacing = 8;

    self.tavolozza = [UIStackView new];
    self.tavolozza.axis = UILayoutConstraintAxisHorizontal;
    self.tavolozza.spacing = 8;

    UIScrollView *scorrevoleColori = [UIScrollView new];
    scorrevoleColori.showsHorizontalScrollIndicator = NO;
    self.tavolozza.translatesAutoresizingMaskIntoConstraints = NO;
    [scorrevoleColori addSubview:self.tavolozza];
    [NSLayoutConstraint activateConstraints:@[
        [self.tavolozza.topAnchor constraintEqualToAnchor:scorrevoleColori.topAnchor],
        [self.tavolozza.bottomAnchor constraintEqualToAnchor:scorrevoleColori.bottomAnchor],
        [self.tavolozza.leadingAnchor constraintEqualToAnchor:scorrevoleColori.leadingAnchor],
        [self.tavolozza.trailingAnchor constraintEqualToAnchor:scorrevoleColori.trailingAnchor],
        [self.tavolozza.heightAnchor constraintEqualToAnchor:scorrevoleColori.heightAnchor],
        [scorrevoleColori.heightAnchor constraintEqualToConstant:48],
    ]];

    self.interruttore = [UISwitch new];
    self.interruttore.onTintColor = [OCTema marca];

    UILabel *etichettaUsaEGetta = [UILabel new];
    etichettaUsaEGetta.text = @"Usa & getta";
    etichettaUsaEGetta.font = [UIFont systemFontOfSize:16];

    UIStackView *rigaUsaEGetta = [[UIStackView alloc]
        initWithArrangedSubviews:@[etichettaUsaEGetta, self.interruttore]];
    rigaUsaEGetta.axis = UILayoutConstraintAxisHorizontal;

    self.stella = [UISwitch new];
    self.stella.onTintColor = [OCTema marca];

    UILabel *etichettaStella = [UILabel new];
    etichettaStella.text = @"Preferita";
    etichettaStella.font = [UIFont systemFontOfSize:16];

    UIStackView *rigaStella = [[UIStackView alloc]
        initWithArrangedSubviews:@[etichettaStella, self.stella]];
    rigaStella.axis = UILayoutConstraintAxisHorizontal;

    UILabel *spiegazione = [UILabel new];
    spiegazione.text = @"Finisce nella seconda scheda, con il cestino per toglierla "
                        "appena l'hai usata.";
    spiegazione.font = [UIFont systemFontOfSize:13];
    spiegazione.textColor = [OCTema attenuato];
    spiegazione.numberOfLines = 0;

    self.errore = [UILabel new];
    self.errore.font = [UIFont systemFontOfSize:13];
    self.errore.textColor = [OCTema pericolo];
    self.errore.numberOfLines = 0;

    // In fondo e lontano da Salva: si vede solo modificando una carta che
    // esiste già, e chiede conferma prima di cancellare.
    self.elimina = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.elimina setTitle:@"Elimina" forState:UIControlStateNormal];
    [self.elimina setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal];
    self.elimina.tintColor = [OCTema pericolo];
    self.elimina.layer.borderColor = [OCTema pericolo].CGColor;
    self.elimina.layer.borderWidth = 1;
    self.elimina.layer.cornerRadius = 10;
    self.elimina.hidden = self.identificativo == 0;
    [self.elimina.heightAnchor constraintEqualToConstant:44].active = YES;
    [self.elimina addTarget:self action:@selector(confermaEliminazione)
           forControlEvents:UIControlEventTouchUpInside];

    UIStackView *colonna = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.nome, self.codice, [self titoletto:@"Tipo di codice"], self.tipo, acquisizione,
        [self titoletto:@"Colore"], scorrevoleColori,
        // L'errore sta sotto Elimina e non sopra: da vuoto occupa comunque una
        // riga, e in mezzo faceva un buco fra la preferita e il pulsante.
        rigaUsaEGetta, spiegazione, rigaStella, self.elimina, self.errore,
    ]];
    colonna.axis = UILayoutConstraintAxisVertical;
    colonna.spacing = 16;
    colonna.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scorrevole = [UIScrollView new];
    scorrevole.translatesAutoresizingMaskIntoConstraints = NO;

    // La tastiera si toglie di mezzo in tre modi: il tasto Fine sopra i tasti,
    // un tocco fuori dai campi, il trascinamento del modulo verso il basso.
    // `cancelsTouchesInView` resta NO, altrimenti il tocco si ferma qui e i
    // pulsanti del modulo non rispondono più.
    scorrevole.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    UITapGestureRecognizer *tocco = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(chiudiTastiera)];
    tocco.cancelsTouchesInView = NO;
    [scorrevole addGestureRecognizer:tocco];

    [scorrevole addSubview:colonna];
    [self.view addSubview:scorrevole];
    self.scorrevole = scorrevole;

    UILayoutGuide *area = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scorrevole.topAnchor constraintEqualToAnchor:area.topAnchor],
        [scorrevole.bottomAnchor constraintEqualToAnchor:area.bottomAnchor],
        [scorrevole.leadingAnchor constraintEqualToAnchor:area.leadingAnchor],
        [scorrevole.trailingAnchor constraintEqualToAnchor:area.trailingAnchor],

        [colonna.topAnchor constraintEqualToAnchor:scorrevole.topAnchor constant:20],
        [colonna.bottomAnchor constraintEqualToAnchor:scorrevole.bottomAnchor constant:-20],
        [colonna.leadingAnchor constraintEqualToAnchor:scorrevole.leadingAnchor constant:20],
        [colonna.trailingAnchor constraintEqualToAnchor:scorrevole.trailingAnchor constant:-20],
        [colonna.widthAnchor constraintEqualToAnchor:scorrevole.widthAnchor constant:-40],
    ]];
}

- (UILabel *)titoletto:(NSString *)testo
{
    UILabel *etichetta = [UILabel new];
    etichetta.text = testo;
    etichetta.font = [UIFont systemFontOfSize:13];
    etichetta.textColor = [OCTema attenuato];
    return etichetta;
}

#pragma mark - Tastiera

/// La barra sopra i tasti, con il solo pulsante per chiudere.
///
/// Il tasto Fine della tastiera basterebbe, ma si vede solo quando il fuoco è
/// nel campo giusto: qui il modo per uscire è sempre scritto a video.
- (UIToolbar *)barraTastiera
{
    // La larghezza dello schermo e non zero: come vista sopra la tastiera un
    // riquadro vuoto resta vuoto, e il pulsante non si vedrebbe.
    UIToolbar *barra = [[UIToolbar alloc]
        initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 44)];
    barra.items = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                      target:nil
                                                      action:nil],
        [[UIBarButtonItem alloc] initWithTitle:@"Fine"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(chiudiTastiera)],
    ];
    [barra sizeToFit];
    return barra;
}

- (void)chiudiTastiera
{
    [self.view endEditing:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)campo
{
    if (campo == self.nome) {
        [self.codice becomeFirstResponder];
    } else {
        [campo resignFirstResponder];
    }
    return NO;
}

/// Con la tastiera aperta il modulo finisce sotto, e la parte bassa, dove
/// stanno i colori e il pulsante di eliminazione, non si raggiunge più. Lo
/// spazio in fondo cresce di quanto la tastiera copre davvero.
- (void)tastieraCambiata:(NSNotification *)avviso
{
    NSValue *quadro = avviso.userInfo[UIKeyboardFrameEndUserInfoKey];
    UIWindow *finestra = self.view.window;
    if (quadro == nil || finestra == nil) {
        return;
    }

    // Il riquadro arriva in coordinate dello schermo: su iPad, con l'app in
    // una finestra affiancata, non sono quelle della finestra e la parte
    // coperta verrebbe fuori sbagliata.
    CGRect nellaFinestra = [finestra convertRect:quadro.CGRectValue
                             fromCoordinateSpace:finestra.screen.coordinateSpace];
    CGRect tastiera = [self.view convertRect:nellaFinestra fromView:finestra];
    CGRect sovrapposto = CGRectIntersection(self.scorrevole.frame, tastiera);
    CGFloat coperto = CGRectIsNull(sovrapposto) ? 0 : CGRectGetHeight(sovrapposto);

    self.scorrevole.contentInset = UIEdgeInsetsMake(0, 0, coperto, 0);
    self.scorrevole.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, coperto, 0);
}

#pragma mark - Colori

/// Il primo colore è quello che spetta alla carta: lasciandolo com'è non si
/// scrive niente nel file, ed è il caso normale.
- (void)aggiornaTavolozza
{
    for (UIView *vecchia in self.tavolozza.arrangedSubviews) {
        [vecchia removeFromSuperview];
    }

    NSMutableArray<NSString *> *colori = [NSMutableArray arrayWithObject:self.coloreProposto];
    for (NSString *colore in OCColoriScelta()) {
        if (![colori containsObject:colore]) {
            [colori addObject:colore];
        }
    }

    NSString *attuale = self.coloreScelto ?: self.coloreProposto;

    for (NSString *colore in colori) {
        UIButton *quadretto = [UIButton buttonWithType:UIButtonTypeCustom];
        quadretto.backgroundColor = [OCTema coloreDaEsadecimale:colore];
        quadretto.layer.cornerRadius = 24;
        quadretto.layer.borderWidth = [colore isEqualToString:attuale] ? 3 : 0;
        quadretto.layer.borderColor = [OCTema inchiostro].CGColor;
        quadretto.accessibilityLabel = colore;
        [quadretto addTarget:self action:@selector(coloreToccato:)
            forControlEvents:UIControlEventTouchUpInside];
        [NSLayoutConstraint activateConstraints:@[
            [quadretto.widthAnchor constraintEqualToConstant:48],
            [quadretto.heightAnchor constraintEqualToConstant:48],
        ]];
        [self.tavolozza addArrangedSubview:quadretto];
    }
}

- (void)coloreToccato:(UIButton *)quadretto
{
    self.coloreScelto = quadretto.accessibilityLabel;
    [self aggiornaTavolozza];
}

#pragma mark - Dati

- (void)carica
{
    NSError *errore = nil;
    OCCarta *carta = [OCCore cartaConId:self.identificativo errore:&errore];

    if (carta == nil) {
        self.errore.text = errore.localizedDescription;
        return;
    }

    self.nome.text = carta.etichetta;
    self.codice.text = carta.codice;
    self.tipo.selectedSegmentIndex = carta.qrcode ? 1 : 0;
    self.interruttore.on = carta.usaEGetta;
    self.stella.on = carta.preferita;
    self.usaEGetta = carta.usaEGetta;
    self.coloreProposto = carta.colore;
    if (carta.coloreScelto) {
        self.coloreScelto = carta.colore;
    }
    [self aggiornaTavolozza];
}

- (void)salva
{
    NSString *etichetta = [self.nome.text stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    NSString *valore = [self.codice.text stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";

    if (etichetta.length == 0) {
        self.errore.text = @"L'etichetta è obbligatoria.";
        return;
    }
    if (valore.length == 0) {
        self.errore.text = @"Il codice è obbligatorio.";
        return;
    }

    BOOL qrcode = self.tipo.selectedSegmentIndex == 1;
    NSString *colore = self.coloreScelto ?: @"";
    NSError *errore = nil;
    BOOL esito;

    NSInteger quale = self.identificativo;

    if (self.identificativo == 0) {
        quale = [OCCore inserisci:etichetta codice:valore qrcode:qrcode colore:colore
                        usaEGetta:self.interruttore.isOn errore:&errore];
        esito = quale >= 0;
    } else {
        esito = [OCCore aggiorna:self.identificativo etichetta:etichetta codice:valore
                          qrcode:qrcode colore:colore usaEGetta:self.interruttore.isOn
                          errore:&errore];
    }

    if (!esito) {
        self.errore.text = errore.localizedDescription;
        return;
    }

    // La stella si scrive a parte, perché non passa da inserisci e aggiorna:
    // quelle due lasciano stare il campo apposta, così modificare una carta
    // non le toglie la preferenza.
    if (![OCCore impostaPreferita:quale accesa:self.stella.isOn errore:&errore]) {
        self.errore.text = errore.localizedDescription;
        return;
    }

    void (^avvisa)(void) = self.suSalvataggio;
    [self dismissViewControllerAnimated:YES completion:^{
        if (avvisa != nil) {
            avvisa();
        }
    }];
}

/// La domanda è la stessa del cestino nell'elenco, con lo stesso titolo e lo
/// stesso nome fra virgolette: chi cancella deve leggere la stessa cosa da
/// qualunque parte sia arrivato.
- (void)confermaEliminazione
{
    NSString *etichetta = [self.nome.text stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";

    UIAlertController *domanda = [UIAlertController
        alertControllerWithTitle:@"Elimina codice"
                         message:[NSString stringWithFormat:@"Eliminare \"%@\"?", etichetta]
                  preferredStyle:UIAlertControllerStyleAlert];

    [domanda addAction:[UIAlertAction actionWithTitle:@"Annulla"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [domanda addAction:[UIAlertAction actionWithTitle:@"Elimina"
                                                style:UIAlertActionStyleDestructive
                                              handler:^(UIAlertAction *azione) {
        NSError *errore = nil;
        if (![OCCore elimina:self.identificativo errore:&errore]) {
            self.errore.text = errore.localizedDescription;
            return;
        }
        void (^avvisa)(void) = self.suEliminazione;
        [self dismissViewControllerAnimated:YES completion:^{
            if (avvisa != nil) {
                avvisa();
            }
        }];
    }]];

    [self presentViewController:domanda animated:YES completion:nil];
}

- (void)chiudi
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Acquisizione del codice

- (void)accetta:(NSString *)letto qrcode:(BOOL)qrcode
{
    self.codice.text = letto;
    self.tipo.selectedSegmentIndex = qrcode ? 1 : 0;
    self.errore.text = @"";
}

- (void)daFotocamera
{
    OCScannerViewController *scanner = [OCScannerViewController new];
    __weak typeof(self) debole = self;
    scanner.suLettura = ^(NSString *codice, BOOL qrcode) {
        [debole accetta:codice qrcode:qrcode];
    };

    UINavigationController *contenitore = [[UINavigationController alloc]
                                           initWithRootViewController:scanner];
    [self presentViewController:contenitore animated:YES completion:nil];
}

- (void)daGalleria
{
    UIImagePickerController *selettore = [UIImagePickerController new];
    selettore.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    selettore.delegate = self;
    [self presentViewController:selettore animated:YES completion:nil];
}

- (void)daFile
{
    UIDocumentPickerViewController *selettore = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.image"] inMode:UIDocumentPickerModeImport];
    selettore.delegate = self;
    [self presentViewController:selettore animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)selettore
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)informazioni
{
    UIImage *immagine = informazioni[UIImagePickerControllerOriginalImage];
    [selettore dismissViewControllerAnimated:YES completion:^{
        [self leggiDaImmagine:immagine];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)selettore
{
    [selettore dismissViewControllerAnimated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)selettore
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)indirizzi
{
    NSURL *scelto = indirizzi.firstObject;
    if (scelto == nil) {
        return;
    }

    BOOL protetto = [scelto startAccessingSecurityScopedResource];
    NSData *contenuto = [NSData dataWithContentsOfURL:scelto];
    if (protetto) {
        [scelto stopAccessingSecurityScopedResource];
    }

    UIImage *immagine = contenuto != nil ? [UIImage imageWithData:contenuto] : nil;
    if (immagine == nil) {
        self.errore.text = @"Non sono riuscito a leggere l'immagine.";
        return;
    }
    [self leggiDaImmagine:immagine];
}

/// Legge il codice da un'immagine già esistente. Vision è di sistema e
/// riconosce gli stessi formati della fotocamera.
- (void)leggiDaImmagine:(UIImage *)immagine
{
    if (immagine.CGImage == NULL) {
        self.errore.text = @"Non sono riuscito a leggere l'immagine.";
        return;
    }

    VNDetectBarcodesRequest *richiesta = [[VNDetectBarcodesRequest alloc]
        initWithCompletionHandler:^(VNRequest *fatta, NSError *guasto) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (guasto != nil) {
                self.errore.text = [NSString stringWithFormat:@"Lettura non riuscita: %@",
                                    guasto.localizedDescription];
                return;
            }

            for (VNBarcodeObservation *trovato in fatta.results) {
                if (trovato.payloadStringValue.length == 0) {
                    continue;
                }
                BOOL qrcode = [trovato.symbology isEqualToString:VNBarcodeSymbologyQR];
                [self accetta:trovato.payloadStringValue qrcode:qrcode];
                return;
            }
            self.errore.text = @"Nell'immagine non c'è nessun codice leggibile.";
        });
    }];

    VNImageRequestHandler *lettore = [[VNImageRequestHandler alloc]
        initWithCGImage:immagine.CGImage options:@{}];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *guasto = nil;
        [lettore performRequests:@[richiesta] error:&guasto];
    });
}

@end
