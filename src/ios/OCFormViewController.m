// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCFormViewController.h"

#import <Vision/Vision.h>

#import "OCCore.h"
#import "OCFoto.h"
#import "OCScannerViewController.h"
#import "OCTema.h"

#include "store.h"

/// Gli stessi colori che assegna il core, per la scelta a mano.
static NSArray<NSString *> *OCColoriScelta(void)
{
    return @[@"#E53935", @"#8E24AA", @"#1E88E5", @"#00897B", @"#43A047", @"#FB8C00",
             @"#6D4C41", @"#039BE5", @"#D81B60", @"#3949AB", @"#00ACC1", @"#7CB342"];
}

/// La simbologia del core che corrisponde a un formato di Vision, che è il
/// lettore delle immagini già scattate. I nomi non sono quelli di AVFoundation,
/// che legge dal vivo: sono due elenchi diversi per la stessa cosa.
///
/// Vale lo stesso della fotocamera: il lettore sa già che codice ha letto, e
/// dirlo è meglio che ricavarlo dal testo. Un formato che non sappiamo
/// disegnare torna `OCSimbologiaAuto` e la scelta resta all'app.
///
/// MSI Plessey resta fuori: la sua costante esiste da iOS 17 e sotto vale nil,
/// che dentro un dizionario letterale fa cadere l'app. Il DataBar resta fuori
/// perché il testo che torna da Vision non è quello che zint vuole in ingresso.
static NSInteger OCSimbologiaDiVision(VNBarcodeSymbology simbologia)
{
    static NSDictionary<VNBarcodeSymbology, NSNumber *> *tabella = nil;
    static dispatch_once_t unaVolta;
    dispatch_once(&unaVolta, ^{
        tabella = @{
            VNBarcodeSymbologyCode128: @(OPENCARD_SIM_CODE128),
            VNBarcodeSymbologyQR: @(OPENCARD_SIM_QR),
            VNBarcodeSymbologyAztec: @(OPENCARD_SIM_AZTEC),
            VNBarcodeSymbologyCodabar: @(OPENCARD_SIM_CODABAR),
            VNBarcodeSymbologyCode39: @(OPENCARD_SIM_CODE39),
            VNBarcodeSymbologyCode39Checksum: @(OPENCARD_SIM_CODE39),
            VNBarcodeSymbologyCode93: @(OPENCARD_SIM_CODE93),
            VNBarcodeSymbologyCode93i: @(OPENCARD_SIM_CODE93),
            VNBarcodeSymbologyDataMatrix: @(OPENCARD_SIM_DATAMATRIX),
            VNBarcodeSymbologyEAN8: @(OPENCARD_SIM_EAN8),
            VNBarcodeSymbologyEAN13: @(OPENCARD_SIM_EAN13),
            VNBarcodeSymbologyITF14: @(OPENCARD_SIM_ITF),
            VNBarcodeSymbologyI2of5: @(OPENCARD_SIM_ITF),
            VNBarcodeSymbologyI2of5Checksum: @(OPENCARD_SIM_ITF),
            VNBarcodeSymbologyPDF417: @(OPENCARD_SIM_PDF417),
            VNBarcodeSymbologyUPCE: @(OPENCARD_SIM_UPCE),
            VNBarcodeSymbologyMicroQR: @(OPENCARD_SIM_MICROQR),
        };
    });
    NSNumber *quale = simbologia != nil ? tabella[simbologia] : nil;
    return quale != nil ? quale.integerValue : OCSimbologiaAuto;
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
/// Il tipo di codice: un pulsante che apre l'elenco delle 18 simbologie.
/// Quale sia scelta sta in `simbologiaScelta`, non nel titolo del pulsante.
@property (nonatomic, strong) UIButton *tipo;
@property (nonatomic, assign) NSInteger simbologiaScelta;
/// Vero se la riga rossa sta mostrando l'avviso sul tipo di codice.
@property (nonatomic, assign) BOOL avvisoSimbologia;

@property (nonatomic, strong) UITextView *note;
@property (nonatomic, strong) UIDatePicker *scadenza;
@property (nonatomic, strong) UIButton *togliScadenza;
/// Il calendario una data ce l'ha sempre: questa dice se l'ha messa l'utente.
@property (nonatomic, assign) BOOL scadenzaMessa;
@property (nonatomic, strong) UITextField *saldo;

/// Le foto scelte, in memoria finché non si salva: una carta nuova il suo id
/// non ce l'ha ancora, e il nome del file lo contiene.
@property (nonatomic, strong, nullable) UIImage *fotoFronte;
@property (nonatomic, strong, nullable) UIImage *fotoRetro;
/// I nomi dei file già scritti, per sapere cosa cancellare se la foto si toglie.
@property (nonatomic, copy) NSString *nomeFotoFronte;
@property (nonatomic, copy) NSString *nomeFotoRetro;
@property (nonatomic, strong) UIButton *riquadroFronte;
@property (nonatomic, strong) UIButton *riquadroRetro;
/// Per chi arriva la foto che sta scegliendo: 0 il codice, 1 il fronte, 2 il retro.
@property (nonatomic, assign) NSInteger fotoPer;
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
    self.title = self.identificativo == 0 ? NSLocalizedString(@"aggiungi", nil) : NSLocalizedString(@"modifica_codice", nil);

    // Annulla e Salva in cima: in fondo finivano sotto la tastiera quando un
    // campo aveva il fuoco.
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:NSLocalizedString(@"annulla", nil) style:UIBarButtonItemStylePlain
               target:self action:@selector(chiudi)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:NSLocalizedString(@"salva", nil) style:UIBarButtonItemStyleDone
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
    self.nome = [self campoConSegnaposto:NSLocalizedString(@"etichetta", nil)];
    self.codice = [self campoConSegnaposto:NSLocalizedString(@"codice", nil)];
    self.codice.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightRegular];

    // Dall'etichetta si passa al codice, dal codice la tastiera si chiude.
    self.nome.returnKeyType = UIReturnKeyNext;
    self.codice.returnKeyType = UIReturnKeyDone;

    // L'avviso sul tipo di codice segue anche il codice: cambiandolo a mano una
    // scelta che prima non ci stava può andare bene, e viceversa.
    [self.codice addTarget:self action:@selector(codiceCambiato)
          forControlEvents:UIControlEventEditingChanged];

    // Barre o quadrato non basta più: le simbologie sono 18, e quale sia
    // cambia il disegno alla cassa. Un pulsante che apre l'elenco occupa una
    // riga sola, dove un segmentato a 18 voci non ci starebbe.
    self.tipo = [UIButton buttonWithType:UIButtonTypeSystem];
    self.tipo.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    self.tipo.titleLabel.font = [UIFont systemFontOfSize:16];
    self.tipo.showsMenuAsPrimaryAction = YES;
    self.tipo.layer.borderColor = [UIColor separatorColor].CGColor;
    self.tipo.layer.borderWidth = 1;
    self.tipo.layer.cornerRadius = 8;
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configurazione = [UIButtonConfiguration plainButtonConfiguration];
        configurazione.contentInsets = NSDirectionalEdgeInsetsMake(0, 12, 0, 12);
        self.tipo.configuration = configurazione;
    }
    [self.tipo.heightAnchor constraintEqualToConstant:44].active = YES;
    // Automatico è il punto di partenza: chi aggiunge una tessera non sa che
    // codice ha in mano, e non deve saperlo.
    self.simbologiaScelta = OCSimbologiaAuto;
    [self aggiornaSimbologia];

    UIStackView *acquisizione = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self bottoneAcquisizione:NSLocalizedString(@"da_fotocamera", nil) simbolo:@"camera" azione:@selector(daFotocamera)],
        [self bottoneAcquisizione:NSLocalizedString(@"da_galleria", nil) simbolo:@"photo" azione:@selector(daGalleria)],
        [self bottoneAcquisizione:NSLocalizedString(@"da_file", nil) simbolo:@"folder" azione:@selector(daFile)],
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

    // I tre campi in più. La nota è alta quattro righe, la scadenza si sceglie
    // dal calendario e il saldo è testo libero, perché «12,50 €», «300 punti» e
    // «due caffè» sono tutti saldi veri.
    self.note = [UITextView new];
    self.note.font = [UIFont systemFontOfSize:16];
    self.note.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.note.layer.cornerRadius = 8;
    [self.note.heightAnchor constraintEqualToConstant:88].active = YES;

    self.scadenza = [UIDatePicker new];
    self.scadenza.datePickerMode = UIDatePickerModeDate;
    self.scadenza.preferredDatePickerStyle = UIDatePickerStyleCompact;
    [self.scadenza addTarget:self action:@selector(scadenzaToccata)
            forControlEvents:UIControlEventValueChanged];

    // La X per togliere la data: senza, una scadenza messa per sbaglio non si
    // toglie più, perché il calendario una data ce l'ha sempre.
    self.togliScadenza = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.togliScadenza setImage:[UIImage systemImageNamed:@"xmark.circle.fill"]
                        forState:UIControlStateNormal];
    self.togliScadenza.tintColor = [OCTema attenuato];
    self.togliScadenza.hidden = YES;
    [self.togliScadenza addTarget:self action:@selector(scadenzaTolta)
                 forControlEvents:UIControlEventTouchUpInside];

    UILabel *etichettaScadenza = [UILabel new];
    etichettaScadenza.text = NSLocalizedString(@"scadenza", nil);
    etichettaScadenza.font = [UIFont systemFontOfSize:16];

    UIStackView *rigaScadenza = [[UIStackView alloc] initWithArrangedSubviews:@[
        etichettaScadenza, self.scadenza, self.togliScadenza,
    ]];
    rigaScadenza.axis = UILayoutConstraintAxisHorizontal;
    rigaScadenza.spacing = 8;

    self.saldo = [self campoConSegnaposto:NSLocalizedString(@"saldo", nil)];
    self.saldo.returnKeyType = UIReturnKeyDone;

    self.riquadroFronte = [self riquadroFoto:NSLocalizedString(@"foto_fronte", nil)
                                      azione:@selector(scegliFotoFronte)];
    self.riquadroRetro = [self riquadroFoto:NSLocalizedString(@"foto_retro", nil)
                                     azione:@selector(scegliFotoRetro)];

    UIStackView *rigaFoto = [[UIStackView alloc]
        initWithArrangedSubviews:@[self.riquadroFronte, self.riquadroRetro]];
    rigaFoto.axis = UILayoutConstraintAxisHorizontal;
    rigaFoto.distribution = UIStackViewDistributionFillEqually;
    rigaFoto.spacing = 12;

    self.interruttore = [UISwitch new];
    self.interruttore.onTintColor = [OCTema marca];

    UILabel *etichettaUsaEGetta = [UILabel new];
    etichettaUsaEGetta.text = NSLocalizedString(@"scheda_usa_e_getta", nil);
    etichettaUsaEGetta.font = [UIFont systemFontOfSize:16];

    UIStackView *rigaUsaEGetta = [[UIStackView alloc]
        initWithArrangedSubviews:@[etichettaUsaEGetta, self.interruttore]];
    rigaUsaEGetta.axis = UILayoutConstraintAxisHorizontal;

    self.stella = [UISwitch new];
    self.stella.onTintColor = [OCTema marca];

    UILabel *etichettaStella = [UILabel new];
    etichettaStella.text = NSLocalizedString(@"preferita", nil);
    etichettaStella.font = [UIFont systemFontOfSize:16];

    UIStackView *rigaStella = [[UIStackView alloc]
        initWithArrangedSubviews:@[etichettaStella, self.stella]];
    rigaStella.axis = UILayoutConstraintAxisHorizontal;

    UILabel *spiegazione = [UILabel new];
    spiegazione.text = NSLocalizedString(@"usa_e_getta_spiega", nil);
    spiegazione.font = [UIFont systemFontOfSize:13];
    spiegazione.textColor = [OCTema attenuato];
    spiegazione.numberOfLines = 0;

    self.errore = [UILabel new];
    self.errore.font = [UIFont systemFontOfSize:13];
    self.errore.textColor = [OCTema pericolo];
    self.errore.numberOfLines = 0;
    self.errore.hidden = YES;

    // In fondo e lontano da Salva: si vede solo modificando una carta che
    // esiste già, e chiede conferma prima di cancellare.
    self.elimina = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.elimina setTitle:NSLocalizedString(@"elimina", nil) forState:UIControlStateNormal];
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
        // L'errore sta in cima e non in fondo: Salva è nella barra, sempre
        // sotto gli occhi, mentre il modulo può essere scorso fin dove si vuole,
        // e un messaggio in fondo non lo leggeva nessuno. Da vuoto è `hidden`,
        // e una vista nascosta esce dal conto della colonna: niente buco.
        self.errore,
        self.nome, self.codice, [self titoletto:NSLocalizedString(@"tipo_di_codice", nil)], self.tipo, acquisizione,
        [self titoletto:NSLocalizedString(@"colore", nil)], scorrevoleColori,
        [self titoletto:NSLocalizedString(@"nota", nil)], self.note,
        rigaScadenza, self.saldo, rigaFoto,
        rigaUsaEGetta, spiegazione, rigaStella, self.elimina,
    ]];
    colonna.axis = UILayoutConstraintAxisVertical;
    colonna.spacing = 16;
    colonna.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scorrevole = [UIScrollView new];
    scorrevole.translatesAutoresizingMaskIntoConstraints = NO;

    // La tastiera si toglie di mezzo trascinando il modulo, o toccando fuori dai
    // campi. Due accortezze, tutte e due volute dopo la prova su iPad:
    //
    // `OnDrag` e non `Interactive`: con `Interactive` la tastiera segue il dito
    // e se ne va solo se il dito arriva sopra di lei, che su un modulo è un
    // gesto da indovinare. Così basta cominciare a trascinare.
    //
    // Il rimbalzo verticale perché su uno schermo grande il modulo ci sta tutto:
    // senza, la vista non si muove, e una vista che non si muove non fa partire
    // nessun trascinamento.
    //
    // `cancelsTouchesInView` resta NO, altrimenti il tocco si ferma qui e i
    // pulsanti del modulo non rispondono più.
    scorrevole.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    scorrevole.alwaysBounceVertical = YES;
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

/// Il riquadro di una foto: vuoto mostra il nome del lato, pieno la foto.
- (UIButton *)riquadroFoto:(NSString *)testo azione:(SEL)azione
{
    UIButton *riquadro = [UIButton buttonWithType:UIButtonTypeSystem];
    [riquadro setTitle:testo forState:UIControlStateNormal];
    riquadro.titleLabel.font = [UIFont systemFontOfSize:13];
    riquadro.tintColor = [OCTema attenuato];
    riquadro.backgroundColor = [UIColor secondarySystemBackgroundColor];
    riquadro.layer.cornerRadius = 10;
    riquadro.clipsToBounds = YES;
    riquadro.imageView.contentMode = UIViewContentModeScaleAspectFill;
    [riquadro.heightAnchor constraintEqualToConstant:110].active = YES;
    [riquadro addTarget:self action:azione forControlEvents:UIControlEventTouchUpInside];
    return riquadro;
}

#pragma mark - Simbologia

/// Rifà il titolo e l'elenco, con la spunta su quella scelta. L'elenco si
/// ricostruisce ogni volta perché la spunta sta dentro le voci.
///
/// Scegliendo un tipo che non contiene il codice l'avviso arriva subito, senza
/// aspettare Salva.
- (void)aggiornaSimbologia
{
    // In cima c'è Automatico, che non è una simbologia del core: l'elenco è
    // quello del core con una voce in più davanti, e i numeri restano quelli.
    NSArray<NSString *> *nomi = [@[NSLocalizedString(@"simbologia_auto", nil)]
                                 arrayByAddingObjectsFromArray:[OCCore nomiSimbologie]];
    NSInteger scelta = self.simbologiaScelta;

    if (scelta < OCSimbologiaAuto || scelta >= (NSInteger)nomi.count - 1) {
        scelta = OCSimbologiaAuto;
        self.simbologiaScelta = scelta;
    }
    // Con una configurazione addosso il titolo lo tiene lei: setTitle: non
    // farebbe niente e il pulsante resterebbe vuoto.
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configurazione = self.tipo.configuration;
        configurazione.title = nomi[scelta + 1];
        self.tipo.configuration = configurazione;
    } else {
        [self.tipo setTitle:nomi[scelta + 1] forState:UIControlStateNormal];
    }

    NSMutableArray<UIAction *> *voci = [NSMutableArray arrayWithCapacity:nomi.count];
    __weak typeof(self) debole = self;

    for (NSUInteger i = 0; i < nomi.count; i++) {
        NSInteger quale = (NSInteger)i - 1;
        UIAction *voce = [UIAction actionWithTitle:nomi[i]
                                             image:nil
                                        identifier:nil
                                           handler:^(__kindof UIAction *azione) {
            (void)azione;
            debole.simbologiaScelta = quale;
            [debole aggiornaSimbologia];
        }];
        voce.state = (quale == scelta) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [voci addObject:voce];
    }
    self.tipo.menu = [UIMenu menuWithTitle:NSLocalizedString(@"tipo_di_codice", nil)
                                  children:voci];
    [self controllaSimbologia];
}

/// L'avviso quando il tipo scelto non può contenere il codice che c'è.
///
/// Arriva scegliendo, non premendo Salva: così si vede subito che quella strada
/// non porta da nessuna parte, e si vede anche aprendo una carta salvata storta
/// da una versione precedente. Salva poi si rifiuta lo stesso.
///
/// Con Automatico non compare mai: quella strada una simbologia buona la trova
/// sempre.
- (void)controllaSimbologia
{
    NSString *valore = [self.codice.text stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    NSInteger quale = self.simbologiaScelta;

    if (valore.length == 0 || quale == OCSimbologiaAuto ||
        [OCCore codiceSta:valore simbologia:quale]) {
        if (self.avvisoSimbologia) {
            [self mostraErrore:@""];
        }
        return;
    }
    [self mostraErrore:[NSString stringWithFormat:
                        NSLocalizedString(@"simbologia_non_ci_sta", nil),
                        [OCCore nomiSimbologie][quale]]];
    self.avvisoSimbologia = YES;
}

/// Il codice cambiato a mano può rendere buona una scelta che non lo era, o il
/// contrario.
- (void)codiceCambiato
{
    [self controllaSimbologia];
}

#pragma mark - Scadenza

- (void)scadenzaToccata
{
    self.scadenzaMessa = YES;
    self.togliScadenza.hidden = NO;
}

- (void)scadenzaTolta
{
    self.scadenzaMessa = NO;
    self.togliScadenza.hidden = YES;
    self.scadenza.date = [NSDate date];
}

/// La data come la vuole il core, "AAAA-MM-GG", oppure vuota.
- (NSString *)scadenzaScritta
{
    if (!self.scadenzaMessa) {
        return @"";
    }
    NSDateFormatter *formato = [NSDateFormatter new];
    formato.dateFormat = @"yyyy-MM-dd";
    formato.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    return [formato stringFromDate:self.scadenza.date];
}

- (void)mostraScadenza:(NSString *)scritta
{
    if (scritta.length == 0) {
        [self scadenzaTolta];
        return;
    }
    NSDateFormatter *formato = [NSDateFormatter new];
    formato.dateFormat = @"yyyy-MM-dd";
    formato.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

    NSDate *quando = [formato dateFromString:scritta];
    if (quando == nil) {
        [self scadenzaTolta];
        return;
    }
    self.scadenza.date = quando;
    self.scadenzaMessa = YES;
    self.togliScadenza.hidden = NO;
}

#pragma mark - Foto della carta

- (void)scegliFotoFronte
{
    [self chiediFotoPer:1];
}

- (void)scegliFotoRetro
{
    [self chiediFotoPer:2];
}

- (void)chiediFotoPer:(NSInteger)lato
{
    BOOL cePosto = (lato == 1 ? self.fotoFronte : self.fotoRetro) != nil;

    UIAlertController *scelte = [UIAlertController
        alertControllerWithTitle:nil message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [scelte addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"da_fotocamera", nil)
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *azione) {
            (void)azione;
            [self prendiFotoDa:UIImagePickerControllerSourceTypeCamera per:lato];
        }]];
    }
    [scelte addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"da_galleria", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *azione) {
        (void)azione;
        [self prendiFotoDa:UIImagePickerControllerSourceTypePhotoLibrary per:lato];
    }]];

    if (cePosto) {
        [scelte addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"togli_foto", nil)
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *azione) {
            (void)azione;
            [self mostraFoto:nil per:lato];
        }]];
    }
    [scelte addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"annulla", nil)
                                              style:UIAlertActionStyleCancel handler:nil]];

    // Su iPad un foglio di scelte senza ancora non si apre: la si aggancia al
    // riquadro toccato.
    scelte.popoverPresentationController.sourceView =
        lato == 1 ? self.riquadroFronte : self.riquadroRetro;
    [self presentViewController:scelte animated:YES completion:nil];
}

- (void)prendiFotoDa:(UIImagePickerControllerSourceType)sorgente per:(NSInteger)lato
{
    self.fotoPer = lato;

    UIImagePickerController *selettore = [UIImagePickerController new];
    selettore.sourceType = sorgente;
    selettore.delegate = self;
    [self presentViewController:selettore animated:YES completion:nil];
}

- (void)mostraFoto:(UIImage *)immagine per:(NSInteger)lato
{
    UIButton *riquadro = lato == 1 ? self.riquadroFronte : self.riquadroRetro;
    NSString *testo = lato == 1 ? NSLocalizedString(@"foto_fronte", nil)
                                : NSLocalizedString(@"foto_retro", nil);
    if (lato == 1) {
        self.fotoFronte = immagine;
    } else {
        self.fotoRetro = immagine;
    }
    [riquadro setBackgroundImage:immagine forState:UIControlStateNormal];
    [riquadro setTitle:immagine != nil ? @"" : testo forState:UIControlStateNormal];
}

#pragma mark - Tastiera

/// I tre modi per chiudere la tastiera sono tutti di sistema: il tasto di invio
/// del campo, un tocco fuori dai campi, il trascinamento del modulo verso il
/// basso. Una barra con Fine sopra i tasti non serve, perché il modo per
/// chiudere il lavoro sta già in alto, dove Contatti e Calendario mettono
/// Annulla e Fine. Serve invece sulle tastiere senza tasto di invio, come il
/// tastierino numerico: se un giorno il campo Codice diventa numerico, la barra
/// torna obbligatoria.
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
        [self mostraErrore:errore.localizedDescription];
        return;
    }

    self.nome.text = carta.etichetta;
    self.codice.text = carta.codice;
    self.simbologiaScelta = carta.simbologia;
    [self aggiornaSimbologia];
    self.note.text = carta.note;
    self.saldo.text = carta.saldo;
    [self mostraScadenza:carta.scadenza];

    self.nomeFotoFronte = carta.fotoFronte;
    self.nomeFotoRetro = carta.fotoRetro;
    [self mostraFoto:[OCFoto leggi:carta.fotoFronte] per:1];
    [self mostraFoto:[OCFoto leggi:carta.fotoRetro] per:2];

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
        [self mostraErrore:NSLocalizedString(@"manca_etichetta", nil)];
        return;
    }
    if (valore.length == 0) {
        [self mostraErrore:NSLocalizedString(@"manca_codice", nil)];
        return;
    }

    // Automatico non è una simbologia: è l'app che ne sceglie una al posto
    // dell'utente. Qui si scioglie, guardando il codice come faceva l'app prima
    // che l'elenco esistesse, e nel file finisce la simbologia vera: una carta
    // salvata sa sempre come si disegna.
    //
    // Se quella che si ricava dal codice non lo contiene si ripiega sul QR, che
    // tiene tutto: il contenuto di un QR in un Code 128 non entra, e Automatico
    // non deve mai finire in un errore, perché è la voce di chi non vuole
    // scegliere.
    NSInteger simbologia = self.simbologiaScelta;
    if (simbologia == OCSimbologiaAuto) {
        simbologia = [OCCore simbologiaIndovinata:valore qrcode:NO];
        if (![OCCore codiceSta:valore simbologia:simbologia]) {
            simbologia = OPENCARD_SIM_QR;
        }
    }
    // Una simbologia scelta a mano invece può non contenere il codice, e finora
    // la carta si salvava lo stesso: il codice si scopriva mancante aprendola.
    // Si dice qui, prima di salvare.
    if (![OCCore codiceSta:valore simbologia:simbologia]) {
        NSArray<NSString *> *nomi = [OCCore nomiSimbologie];
        [self mostraErrore:[NSString stringWithFormat:
                            NSLocalizedString(@"simbologia_non_ci_sta", nil),
                            nomi[simbologia]]];
        return;
    }

    BOOL qrcode = [OCCore simbologiaQuadrata:simbologia];
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
        [self mostraErrore:errore.localizedDescription];
        return;
    }

    // La stella si scrive a parte, perché non passa da inserisci e aggiorna:
    // quelle due lasciano stare il campo apposta, così modificare una carta
    // non le toglie la preferenza.
    if (![OCCore impostaPreferita:quale accesa:self.stella.isOn errore:&errore]) {
        [self mostraErrore:errore.localizedDescription];
        return;
    }

    // Come la stella: inserisci e aggiorna lasciano stare questi campi, così
    // modificare l'etichetta di una carta non le cancella la nota.
    if (![OCCore impostaSimbologia:quale simbologia:simbologia errore:&errore]) {
        [self mostraErrore:errore.localizedDescription];
        return;
    }
    if (![OCCore impostaDettagli:quale
                            note:self.note.text ?: @""
                        scadenza:[self scadenzaScritta]
                           saldo:self.saldo.text ?: @""
                          errore:&errore]) {
        [self mostraErrore:errore.localizedDescription];
        return;
    }
    if (![self salvaLeFotoDi:quale errore:&errore]) {
        [self mostraErrore:errore.localizedDescription];
        return;
    }

    void (^avvisa)(void) = self.suSalvataggio;
    [self dismissViewControllerAnimated:YES completion:^{
        if (avvisa != nil) {
            avvisa();
        }
    }];
}

/// Scrive i file delle due foto e mette i nomi nella carta.
///
/// Si fa dopo l'inserimento e non prima: il nome del file contiene l'id, e una
/// carta nuova l'id ce l'ha solo dopo che il core gliel'ha dato.
- (BOOL)salvaLeFotoDi:(NSInteger)quale errore:(NSError **)errore
{
    NSString *fronte = @"";
    NSString *retro = @"";

    if (self.fotoFronte != nil) {
        fronte = [OCFoto salva:self.fotoFronte id:quale fronte:YES] ?: @"";
        if (fronte.length == 0) {
            if (errore != NULL) {
                *errore = [NSError errorWithDomain:@"srl.denovo.opencard" code:-1
                    userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"foto_non_salvata", nil)}];
            }
            return NO;
        }
    } else if (self.nomeFotoFronte.length > 0) {
        [OCFoto cancella:self.nomeFotoFronte];
    }

    if (self.fotoRetro != nil) {
        retro = [OCFoto salva:self.fotoRetro id:quale fronte:NO] ?: @"";
        if (retro.length == 0) {
            if (errore != NULL) {
                *errore = [NSError errorWithDomain:@"srl.denovo.opencard" code:-1
                    userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"foto_non_salvata", nil)}];
            }
            return NO;
        }
    } else if (self.nomeFotoRetro.length > 0) {
        [OCFoto cancella:self.nomeFotoRetro];
    }

    return [OCCore impostaFoto:quale fronte:fronte retro:retro errore:errore];
}

/// La domanda è la stessa del cestino nell'elenco, con lo stesso titolo e lo
/// stesso nome fra virgolette: chi cancella deve leggere la stessa cosa da
/// qualunque parte sia arrivato.
- (void)confermaEliminazione
{
    NSString *etichetta = [self.nome.text stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";

    UIAlertController *domanda = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"elimina_titolo", nil)
                         message:[NSString stringWithFormat:NSLocalizedString(@"elimina_domanda", nil), etichetta]
                  preferredStyle:UIAlertControllerStyleAlert];

    [domanda addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"annulla", nil)
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [domanda addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"elimina", nil)
                                                style:UIAlertActionStyleDestructive
                                              handler:^(UIAlertAction *azione) {
        NSError *errore = nil;
        if (![OCCore elimina:self.identificativo errore:&errore]) {
            [self mostraErrore:errore.localizedDescription];
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

/// Il messaggio di errore, o niente se la stringa è vuota.
///
/// Riporta anche il modulo in cima: Salva sta nella barra e si preme da
/// qualsiasi punto del modulo, quindi il messaggio può essere fuori schermo.
- (void)mostraErrore:(NSString *)messaggio
{
    self.avvisoSimbologia = NO;
    self.errore.text = messaggio;
    self.errore.hidden = messaggio.length == 0;
    if (messaggio.length > 0) {
        [self.scorrevole setContentOffset:CGPointZero animated:YES];
    }
}

#pragma mark - Acquisizione del codice

- (void)accetta:(NSString *)letto simbologia:(NSInteger)letta
{
    self.codice.text = letto;
    // Il lettore ha misurato che codice era: si scrive quello nell'elenco, così
    // chi ha inquadrato la tessera vede subito cosa ha preso e non deve
    // decidere niente. Resta cambiabile a mano.
    //
    // Se il formato non è fra quelli che sappiamo disegnare si resta su
    // Automatico, e la simbologia la sceglie il salvataggio.
    self.simbologiaScelta = letta;
    [self aggiornaSimbologia];
    [self mostraErrore:@""];
}

- (void)daFotocamera
{
    OCScannerViewController *scanner = [OCScannerViewController new];
    __weak typeof(self) debole = self;
    scanner.suLettura = ^(NSString *codice, NSInteger simbologia) {
        [debole accetta:codice simbologia:simbologia];
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
    // Anche i PDF: le tessere arrivano spesso per email come allegato, e
    // stamparle per poi fotografarle è un giro assurdo.
    UIDocumentPickerViewController *selettore = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.image", @"com.adobe.pdf"]
                       inMode:UIDocumentPickerModeImport];
    selettore.delegate = self;
    [self presentViewController:selettore animated:YES completion:nil];
}

/// La prima pagina di un PDF disegnata come immagine, o nil se non è un PDF.
///
/// Si rende a tre volte la misura della pagina: un codice a barre stampato
/// piccolo, reso alla misura naturale, esce con le barre troppo sottili perché
/// il lettore le distingua.
- (UIImage *)paginaDaPdf:(NSData *)contenuto
{
    CGDataProviderRef fornitore = CGDataProviderCreateWithCFData((__bridge CFDataRef)contenuto);
    if (fornitore == NULL) {
        return nil;
    }
    CGPDFDocumentRef documento = CGPDFDocumentCreateWithProvider(fornitore);
    CGDataProviderRelease(fornitore);

    if (documento == NULL) {
        return nil;
    }
    CGPDFPageRef pagina = CGPDFDocumentGetPage(documento, 1);
    if (pagina == NULL) {
        CGPDFDocumentRelease(documento);
        return nil;
    }

    CGRect riquadro = CGPDFPageGetBoxRect(pagina, kCGPDFMediaBox);
    CGFloat ingrandimento = 3;
    CGSize misura = CGSizeMake(riquadro.size.width * ingrandimento,
                               riquadro.size.height * ingrandimento);

    UIGraphicsImageRendererFormat *formato = [UIGraphicsImageRendererFormat defaultFormat];
    formato.scale = 1;
    UIGraphicsImageRenderer *disegnatore =
        [[UIGraphicsImageRenderer alloc] initWithSize:misura format:formato];

    UIImage *immagine = [disegnatore imageWithActions:^(UIGraphicsImageRendererContext *contesto) {
        CGContextRef ct = contesto.CGContext;
        // Fondo bianco: un PDF trasparente su fondo nero non si legge.
        CGContextSetFillColorWithColor(ct, [UIColor whiteColor].CGColor);
        CGContextFillRect(ct, CGRectMake(0, 0, misura.width, misura.height));

        // Il PDF ha l'origine in basso a sinistra, la grafica in alto.
        CGContextTranslateCTM(ct, 0, misura.height);
        CGContextScaleCTM(ct, ingrandimento, -ingrandimento);
        CGContextTranslateCTM(ct, -riquadro.origin.x, -riquadro.origin.y);
        CGContextDrawPDFPage(ct, pagina);
    }];

    CGPDFDocumentRelease(documento);
    return immagine;
}

- (void)imagePickerController:(UIImagePickerController *)selettore
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)informazioni
{
    UIImage *immagine = informazioni[UIImagePickerControllerOriginalImage];
    NSInteger per = self.fotoPer;
    self.fotoPer = 0;

    [selettore dismissViewControllerAnimated:YES completion:^{
        // Stesso selettore, due mestieri: o si legge un codice dall'immagine,
        // o l'immagine è la foto della tessera.
        if (per == 0) {
            [self leggiDaImmagine:immagine];
        } else {
            [self mostraFoto:immagine per:per];
        }
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)selettore
{
    self.fotoPer = 0;
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
    if (immagine == nil && contenuto != nil) {
        immagine = [self paginaDaPdf:contenuto];
    }
    if (immagine == nil) {
        [self mostraErrore:NSLocalizedString(@"immagine_non_letta", nil)];
        return;
    }
    [self leggiDaImmagine:immagine];
}

/// Legge il codice da un'immagine già esistente. Vision è di sistema e
/// riconosce gli stessi formati della fotocamera.
- (void)leggiDaImmagine:(UIImage *)immagine
{
    if (immagine.CGImage == NULL) {
        [self mostraErrore:NSLocalizedString(@"immagine_non_letta", nil)];
        return;
    }

    VNDetectBarcodesRequest *richiesta = [[VNDetectBarcodesRequest alloc]
        initWithCompletionHandler:^(VNRequest *fatta, NSError *guasto) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (guasto != nil) {
                [self mostraErrore:[NSString stringWithFormat:NSLocalizedString(@"lettura_non_riuscita", nil),
                                    guasto.localizedDescription]];
                return;
            }

            for (VNBarcodeObservation *trovato in fatta.results) {
                if (trovato.payloadStringValue.length == 0) {
                    continue;
                }
                [self accetta:trovato.payloadStringValue
                   simbologia:OCSimbologiaDiVision(trovato.symbology)];
                return;
            }
            [self mostraErrore:NSLocalizedString(@"nessun_codice_nell_immagine", nil)];
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
