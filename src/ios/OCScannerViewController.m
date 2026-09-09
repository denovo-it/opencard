// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import "OCScannerViewController.h"

#import <AVFoundation/AVFoundation.h>

#import "OCCore.h"
#import "OCTema.h"

#include "store.h"

@interface OCScannerViewController () <AVCaptureMetadataOutputObjectsDelegate>
@property (nonatomic, strong) AVCaptureSession *sessione;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *anteprima;
@property (nonatomic, strong) UILabel *avviso;
/// Una lettura sola: senza questo si tornerebbe indietro più volte.
@property (nonatomic, assign) BOOL giaLetto;
/// I testi letti finora, senza doppioni e nell'ordine in cui sono arrivati.
@property (nonatomic, strong) NSMutableArray<NSString *> *pezzi;
/// Quanti codici mancano, mentre si raccoglie.
@property (nonatomic, strong) UILabel *progresso;
/// L'ultimo messaggio mostrato, per non ripeterlo a ogni fotogramma.
@property (nonatomic, copy, nullable) NSString *ultimoAvviso;
/// Il codice che sta accumulando conferme, e la sua simbologia.
@property (nonatomic, copy, nullable) NSString *candidato;
@property (nonatomic, copy, nullable) NSString *candidatoTipo;
/// Quante volte di fila è arrivato uguale, e quando è comparso la prima.
@property (nonatomic, assign) NSInteger conferme;
@property (nonatomic, assign) NSTimeInterval primaLettura;
/// Quando è partita la scansione, per l'avviso a chi non conclude.
@property (nonatomic, assign) NSTimeInterval inizioScansione;
@end

/// La simbologia del core che corrisponde a un formato di AVFoundation.
///
/// Il lettore sa già che codice ha letto, e dirlo è meglio che ricavarlo dal
/// testo: dalle cifre non si distingue un ITF da un EAN-13, e un Code 39
/// diventerebbe Code 128, cioè barre diverse da quelle stampate sulla tessera.
///
/// Un formato che non sappiamo disegnare torna `OCSimbologiaAuto`: la scelta
/// resta all'app, che ci arriva dal codice come faceva prima.
static NSInteger OCSimbologiaDelTipo(AVMetadataObjectType tipo)
{
    static NSDictionary<AVMetadataObjectType, NSNumber *> *tabella = nil;
    static dispatch_once_t unaVolta;
    dispatch_once(&unaVolta, ^{
        tabella = @{
            AVMetadataObjectTypeCode128Code: @(OPENCARD_SIM_CODE128),
            AVMetadataObjectTypeQRCode: @(OPENCARD_SIM_QR),
            AVMetadataObjectTypeAztecCode: @(OPENCARD_SIM_AZTEC),
            AVMetadataObjectTypeCode39Code: @(OPENCARD_SIM_CODE39),
            AVMetadataObjectTypeCode93Code: @(OPENCARD_SIM_CODE93),
            AVMetadataObjectTypeDataMatrixCode: @(OPENCARD_SIM_DATAMATRIX),
            AVMetadataObjectTypeEAN8Code: @(OPENCARD_SIM_EAN8),
            AVMetadataObjectTypeEAN13Code: @(OPENCARD_SIM_EAN13),
            AVMetadataObjectTypeITF14Code: @(OPENCARD_SIM_ITF),
            AVMetadataObjectTypeInterleaved2of5Code: @(OPENCARD_SIM_ITF),
            AVMetadataObjectTypePDF417Code: @(OPENCARD_SIM_PDF417),
            AVMetadataObjectTypeUPCECode: @(OPENCARD_SIM_UPCE),
        };
    });
    NSNumber *quale = tipo != nil ? tabella[tipo] : nil;
    return quale != nil ? quale.integerValue : OCSimbologiaAuto;
}

/// Letture identiche di fila che rendono buono un codice.
static const NSInteger OCScannerConferme = 3;
/// Distanza minima fra la prima e l'ultima, in secondi.
static const NSTimeInterval OCScannerAttesaMinima = 0.3;
/// Dopo quanto si dice all'utente di tenere fermo il telefono.
static const NSTimeInterval OCScannerAvviso = 2.5;

@implementation OCScannerViewController

/// Tutti i formati che una tessera può avere. Sono gli stessi che riconosce
/// la versione Android.
+ (NSArray<AVMetadataObjectType> *)formati
{
    return @[
        AVMetadataObjectTypeQRCode,
        AVMetadataObjectTypeEAN13Code,
        AVMetadataObjectTypeEAN8Code,
        AVMetadataObjectTypeUPCECode,
        AVMetadataObjectTypeCode128Code,
        AVMetadataObjectTypeCode39Code,
        AVMetadataObjectTypeCode93Code,
        AVMetadataObjectTypeITF14Code,
        AVMetadataObjectTypeInterleaved2of5Code,
        AVMetadataObjectTypePDF417Code,
        AVMetadataObjectTypeDataMatrixCode,
        AVMetadataObjectTypeAztecCode,
    ];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.title = self.raccolta ? NSLocalizedString(@"trasferimento_ricevi", nil) : NSLocalizedString(@"inquadra_codice", nil);
    self.pezzi = [NSMutableArray array];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                             target:self
                             action:@selector(chiudi)];

    self.avviso = [UILabel new];
    self.avviso.numberOfLines = 0;
    self.avviso.textAlignment = NSTextAlignmentCenter;
    self.avviso.textColor = [UIColor whiteColor];
    self.avviso.font = [UIFont systemFontOfSize:16];
    self.avviso.hidden = YES;
    self.avviso.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.avviso];

    [NSLayoutConstraint activateConstraints:@[
        [self.avviso.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.avviso.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.avviso.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
    ]];

    // La riga in basso serve a tutti e due i modi: il conteggio dei pezzi
    // mentre si raccoglie, l'invito a tenere fermo il telefono mentre si legge
    // una tessera. Nel secondo caso nasce nascosta.
    [self preparaProgresso];
    if (!self.raccolta) {
        self.progresso.hidden = YES;
    }

    [self chiediPermesso];
}

/// Il conteggio dei codici, in basso e su fondo scuro: sopra l'anteprima della
/// fotocamera un testo senza fondo non si legge.
- (void)preparaProgresso
{
    self.progresso = [UILabel new];
    self.progresso.text = NSLocalizedString(@"trasferimento_attesa", nil);
    self.progresso.numberOfLines = 0;
    self.progresso.textAlignment = NSTextAlignmentCenter;
    self.progresso.textColor = [UIColor whiteColor];
    self.progresso.font = [UIFont systemFontOfSize:18];
    self.progresso.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    self.progresso.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.progresso];

    [NSLayoutConstraint activateConstraints:@[
        [self.progresso.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.progresso.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.progresso.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.progresso.heightAnchor constraintGreaterThanOrEqualToConstant:64],
    ]];
}

- (void)chiediPermesso
{
    AVAuthorizationStatus stato = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];

    switch (stato) {
        case AVAuthorizationStatusAuthorized:
            [self preparaFotocamera];
            break;
        case AVAuthorizationStatusNotDetermined: {
            // Le graffe delimitano lo scope: senza, il blocco vivrebbe fino al
            // case successivo e il compilatore rifiuta il salto.
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                     completionHandler:^(BOOL concesso) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (concesso) {
                        [self preparaFotocamera];
                    } else {
                        [self mostraRifiuto];
                    }
                });
            }];
            break;
        }
        default:
            [self mostraRifiuto];
            break;
    }
}

- (void)mostraRifiuto
{
    // Senza fotocamera la carta si aggiunge lo stesso, scrivendo il codice a
    // mano o leggendolo da una foto: si torna indietro e basta.
    self.avviso.text = NSLocalizedString(@"fotocamera_negata", nil);
    self.avviso.hidden = NO;
}

- (void)preparaFotocamera
{
    AVCaptureDevice *fotocamera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (fotocamera == nil) {
        self.avviso.text = NSLocalizedString(@"fotocamera_non_disponibile", nil);
        self.avviso.hidden = NO;
        return;
    }

    NSError *errore = nil;
    AVCaptureDeviceInput *ingresso = [AVCaptureDeviceInput deviceInputWithDevice:fotocamera
                                                                          error:&errore];
    if (ingresso == nil) {
        self.avviso.text = errore.localizedDescription;
        self.avviso.hidden = NO;
        return;
    }

    self.sessione = [AVCaptureSession new];
    if (![self.sessione canAddInput:ingresso]) {
        self.avviso.text = NSLocalizedString(@"fotocamera_non_disponibile", nil);
        self.avviso.hidden = NO;
        return;
    }
    [self.sessione addInput:ingresso];

    AVCaptureMetadataOutput *uscita = [AVCaptureMetadataOutput new];
    if (![self.sessione canAddOutput:uscita]) {
        self.avviso.text = NSLocalizedString(@"fotocamera_non_disponibile", nil);
        self.avviso.hidden = NO;
        return;
    }
    [self.sessione addOutput:uscita];
    [uscita setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];

    // I formati vanno impostati dopo aver aggiunto l'uscita alla sessione:
    // prima, l'elenco di quelli disponibili è vuoto e l'assegnazione fallisce.
    NSMutableArray<AVMetadataObjectType> *accettati = [NSMutableArray array];
    for (AVMetadataObjectType tipo in [OCScannerViewController formati]) {
        if ([uscita.availableMetadataObjectTypes containsObject:tipo]) {
            [accettati addObject:tipo];
        }
    }
    uscita.metadataObjectTypes = accettati;

    self.anteprima = [AVCaptureVideoPreviewLayer layerWithSession:self.sessione];
    self.anteprima.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.anteprima.frame = self.view.bounds;
    [self.view.layer insertSublayer:self.anteprima atIndex:0];

    // La sessione si avvia fuori dal thread dell'interfaccia: bloccherebbe il
    // disegno per qualche decimo di secondo.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self.sessione startRunning];
    });
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.anteprima.frame = self.view.bounds;
}

- (void)viewWillDisappear:(BOOL)animato
{
    [super viewWillDisappear:animato];
    if (self.sessione.isRunning) {
        [self.sessione stopRunning];
    }
}

- (void)captureOutput:(AVCaptureOutput *)uscita
    didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)oggetti
              fromConnection:(AVCaptureConnection *)collegamento
{
    if (self.giaLetto) {
        return;
    }

    if (self.raccolta) {
        [self raccogli:oggetti];
        return;
    }

    for (AVMetadataObject *oggetto in oggetti) {
        if (![oggetto isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) {
            continue;
        }
        AVMetadataMachineReadableCodeObject *codice = (AVMetadataMachineReadableCodeObject *)oggetto;
        if (codice.stringValue.length == 0) {
            continue;
        }
        [self conferma:codice];
        return;
    }
}

/// Una lettura sola non basta.
///
/// Col telefono in movimento il lettore restituisce numeri plausibili ma
/// sbagliati, e su una tessera un numero sbagliato non si vede: si scopre alla
/// cassa. Si prende per buono un codice solo quando arriva tre volte di fila
/// identico, stesso testo e stessa simbologia, e quando fra la prima e la terza
/// lettura sono passati almeno 300 ms.
///
/// I 300 ms non sono un'attesa aggiunta, sono un pavimento: senza, tre
/// fotogrammi dello stesso istante di sfocatura passerebbero il controllo,
/// perché sono lo stesso errore contato tre volte. Col codice fermo la
/// conferma arriva in poco più di quel terzo di secondo.
///
/// Stessa taratura della versione Android: se cambia di là, cambia anche qui.
- (void)conferma:(AVMetadataMachineReadableCodeObject *)codice
{
    // systemUptime e non CACurrentMediaTime: sta in Foundation, che è già
    // collegata, mentre l'altra vorrebbe QuartzCore in tutti e quattro gli
    // script di build. Serve un orologio che non torni indietro, e questo lo è.
    NSTimeInterval adesso = [[NSProcessInfo processInfo] systemUptime];

    // L'avviso prima di tutto: serve proprio quando le letture continuano a
    // cambiare e non si conferma niente, cioè quando da qui si esce subito.
    if (self.inizioScansione == 0) {
        self.inizioScansione = adesso;
    } else if (adesso - self.inizioScansione >= OCScannerAvviso) {
        [self mostraTieniFermo];
    }

    if (![codice.stringValue isEqualToString:self.candidato] ||
        ![codice.type isEqualToString:self.candidatoTipo]) {
        self.candidato = codice.stringValue;
        self.candidatoTipo = codice.type;
        self.conferme = 1;
        self.primaLettura = adesso;
        return;
    }

    self.conferme += 1;
    if (self.conferme >= OCScannerConferme &&
        adesso - self.primaLettura >= OCScannerAttesaMinima) {
        self.giaLetto = YES;
        if (self.suLettura != nil) {
            self.suLettura(codice.stringValue, OCSimbologiaDelTipo(codice.type));
        }
        [self chiudi];
    }
}

- (void)mostraTieniFermo
{
    NSString *testo = NSLocalizedString(@"scanner_tieni_fermo", nil);
    if ([testo isEqualToString:self.ultimoAvviso]) {
        return;
    }
    self.ultimoAvviso = testo;
    self.progresso.hidden = NO;
    self.progresso.text = testo;
}

/// Un giro di codici letti dal fotogramma.
///
/// Chi mostra fa girare i codici da solo, quindi qui si accumula e basta: i
/// doppioni li scarta il confronto, e quello che non è di OpenCard lo ignora
/// il core senza dire niente. Il conteggio lo tiene il core, l'unico a sapere
/// quanti pezzi ha il passaggio.
- (void)raccogli:(NSArray<__kindof AVMetadataObject *> *)oggetti
{
    BOOL novita = NO;

    for (AVMetadataObject *oggetto in oggetti) {
        if (![oggetto isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) {
            continue;
        }
        NSString *testo = ((AVMetadataMachineReadableCodeObject *)oggetto).stringValue;
        if (testo.length == 0 || [self.pezzi containsObject:testo]) {
            continue;
        }
        [self.pezzi addObject:testo];
        novita = YES;
    }
    if (!novita) {
        return;
    }

    NSError *errore = nil;
    NSInteger ricevuti = 0, totale = 0;

    if (![OCCore statoRaccolta:self.pezzi ricevuti:&ricevuti totale:&totale errore:&errore]) {
        // Pezzi di due passaggi diversi, o un formato che questa versione non
        // conosce: si riparte da zero, altrimenti i codici buoni che arrivano
        // dopo restano attaccati ai vecchi e non si completa mai.
        [self.pezzi removeAllObjects];
        NSString *messaggio = errore.localizedDescription;
        if (![messaggio isEqualToString:self.ultimoAvviso]) {
            self.ultimoAvviso = messaggio;
            self.progresso.text = messaggio;
        }
        return;
    }
    if (totale == 0) {
        return;
    }

    self.ultimoAvviso = nil;
    self.progresso.text = [NSString stringWithFormat:NSLocalizedString(@"trasferimento_raccolta", nil),
                                                     (long)ricevuti, (long)totale];

    // Si tocca l'interfaccia senza cambiare coda: l'uscita dei metadati è
    // già consegnata sulla coda principale, vedi preparaFotocamera.
    // Qui non si chiude da sola: chiude chi ha aperto, che subito dopo deve
    // fare una domanda. Presentare una domanda mentre una schermata si sta
    // chiudendo la fa sparire senza dire niente.
    if (ricevuti >= totale && !self.giaLetto) {
        self.giaLetto = YES;
        if (self.suRaccolta != nil) {
            self.suRaccolta([self.pezzi copy]);
        }
    }
}

- (void)chiudi
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end
