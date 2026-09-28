// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Ponte fra il core in C e Objective-C.
//
// Qui dentro non c'è logica: si traducono soltanto stringhe, array e strutture.
// Il formato dei dati e dei backup è deciso dal core, quindi un backup fatto su
// Android si rilegge qui senza conversioni, e viceversa.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Una carta come la tiene il core.
@interface OCCarta : NSObject
@property (nonatomic, assign) NSInteger identificativo;
@property (nonatomic, copy) NSString *etichetta;
@property (nonatomic, copy) NSString *codice;
@property (nonatomic, assign) BOOL qrcode;
/// Colore da usare: quello scelto a mano, oppure quello che spetta all'id.
@property (nonatomic, copy) NSString *colore;
/// Vero se il colore l'ha scelto l'utente, non l'id.
@property (nonatomic, assign) BOOL coloreScelto;
@property (nonatomic, assign) BOOL usaEGetta;
/// Preferita: compare anche nella scheda con la stella.
@property (nonatomic, assign) BOOL preferita;
/// Che codice è: uno dei valori di `opencard_simbologia`, da 0 a 17.
/// Il core la tiene allineata a `qrcode`, quindi le due non si contraddicono.
@property (nonatomic, assign) NSInteger simbologia;
/// I quattro campi in più. Stringa vuota vuol dire non compilato.
@property (nonatomic, copy) NSString *note;
/// "AAAA-MM-GG" oppure vuota.
@property (nonatomic, copy) NSString *scadenza;
@property (nonatomic, copy) NSString *saldo;
/// Nomi di file, non byte: le foto stanno in una cartella a parte.
@property (nonatomic, copy) NSString *fotoFronte;
@property (nonatomic, copy) NSString *fotoRetro;
@end

/// Nessuna scelta dell'utente: la simbologia la decide l'app.
///
/// Non è un valore che il core conosce e non finisce mai nel file: al
/// salvataggio diventa la simbologia letta dal lettore, o quella che si ricava
/// dal codice. Nel file una carta ha sempre scritto come si disegna.
static const NSInteger OCSimbologiaAuto = -1;

@interface OCCore : NSObject

/// Va chiamata una volta all'avvio, prima di tutto il resto.
+ (BOOL)apriConErrore:(NSError **)errore;

+ (BOOL)primoAvvio;
+ (void)segnaPrimoAvvioFatto;

+ (nullable NSArray<OCCarta *> *)tutteLeCarte:(NSError **)errore;
+ (nullable NSArray<OCCarta *> *)carteDelGruppo:(BOOL)usaEGetta errore:(NSError **)errore;
+ (nullable OCCarta *)cartaConId:(NSInteger)identificativo errore:(NSError **)errore;

/// Le carte con la stella, dei due gruppi insieme. Vuota se non ce ne sono, e
/// allora la scheda con la stella non si mostra.
+ (nullable NSArray<OCCarta *> *)cartePreferite:(NSError **)errore;

/// Accende o spegne la stella, lasciando il resto della carta com'è.
+ (BOOL)impostaPreferita:(NSInteger)identificativo
                 accesa:(BOOL)accesa
                 errore:(NSError **)errore;
+ (NSInteger)prossimoId;

/// La carta del modulo, tutta insieme, in una scrittura sola. Con `nuova` va
/// in fondo con il suo id, da chiedere prima a `prossimoId` perché il nome
/// delle foto lo contiene; senza, prende il posto della carta con quell'id.
/// Colore vuoto vuol dire il colore dell'id.
+ (BOOL)salva:(NSInteger)identificativo
       nuova:(BOOL)nuova
   etichetta:(NSString *)etichetta
      codice:(NSString *)codice
  simbologia:(NSInteger)simbologia
      colore:(NSString *)colore
   usaEGetta:(BOOL)usaEGetta
   preferita:(BOOL)preferita
        note:(NSString *)note
    scadenza:(NSString *)scadenza
       saldo:(NSString *)saldo
  fotoFronte:(NSString *)fotoFronte
   fotoRetro:(NSString *)fotoRetro
      errore:(NSError **)errore;

+ (BOOL)elimina:(NSInteger)identificativo errore:(NSError **)errore;

/// Riscrive l'ordine di un gruppo lasciando l'altro dov'è.
+ (BOOL)riordina:(BOOL)usaEGetta identificativi:(NSArray<NSNumber *> *)ids errore:(NSError **)errore;

/// Colore che spetta a un id, quando l'utente non ne sceglie uno.
+ (NSString *)colorePerId:(NSInteger)identificativo;

/// Il codice spezzato in blocchi di tre, per leggerlo e confrontarlo.
+ (NSString *)codiceRaggruppato:(NSString *)codice;

/// Immagine del codice, disegnata dal core.
+ (nullable UIImage *)immaginePerCodice:(NSString *)codice
                                 qrcode:(BOOL)qrcode
                                 errore:(NSError **)errore;

/// Dove sta il file delle carte. Serve a chi deve svuotare i temporanei senza
/// rischiare di portarsi via i dati, nel caso limite in cui finiscano li'.
+ (NSString *)directoryDati;

/// Nome proposto per il file di backup.
+ (NSString *)nomeBackup;

/// Che file è, per scegliere la domanda prima di importarlo: i valori sono
/// quelli di `opencard_tipo_file` in backup.h.
typedef NS_ENUM(NSInteger, OCTipoFile) {
    OCTipoFileJson = 0,
    OCTipoFileArchivio = 1,
    OCTipoFileCsv = 2,
    OCTipoFileCifrato = 3,
};

+ (OCTipoFile)tipoFile:(NSData *)dati;

/// Il file da salvare con tutte le carte: l'archivio con le foto, oppure il
/// CSV di Catima. Con la password non vuota esce chiuso, foto comprese.
+ (nullable NSData *)esportaCsv:(BOOL)csv password:(NSString *)password errore:(NSError **)errore;

/// Importa un file salvato da OpenCard, un backup JSON o un CSV di Catima. Il
/// CSV si aggiunge, oppure con `sostituisci` prende il posto delle carte; gli
/// altri le sostituiscono sempre. Torna quante carte sono entrate, -1 se fallisce.
+ (NSInteger)importa:(NSData *)dati
            password:(NSString *)password
         sostituisci:(BOOL)sostituisci
              errore:(NSError **)errore;

#pragma mark - Simbologia

/// I nomi dei 18 tipi di codice da mostrare, nell'ordine dei valori di
/// `opencard_simbologia`: l'indice nell'array è il numero da salvare.
+ (NSArray<NSString *> *)nomiSimbologie;

/// Quale codice sembra, guardando il testo. È quella che l'app propone quando
/// si aggiunge una carta, e che il core usa per i file scritti prima della 1.0.3.
+ (NSInteger)simbologiaIndovinata:(NSString *)codice qrcode:(BOOL)qrcode;

/// Il tipo di codice che sceglie Automatico: quello del codice, o il QR se non ci sta.
+ (NSInteger)simbologiaAutomatica:(NSString *)codice;

/// Se un codice si può disegnare in una simbologia, senza disegnarlo.
///
/// Il modulo lo chiede prima di salvare: una scelta che non porta da nessuna
/// parte va detta subito, non scoperta più tardi aprendo la carta e trovando il
/// posto del codice vuoto.
+ (BOOL)codiceSta:(NSString *)codice simbologia:(NSInteger)simbologia;

/// Immagine del codice disegnata con la simbologia scritta nella carta.
+ (nullable UIImage *)immaginePerCodice:(NSString *)codice
                             simbologia:(NSInteger)simbologia
                                 errore:(NSError **)errore;

#pragma mark - Cifratura

/// La chiave con cui il file delle carte sta cifrato sul telefono, 32 byte.
/// Va data subito dopo l'apertura e prima di leggere qualsiasi cosa; `nil` la
/// toglie e il file torna a scriversi in chiaro.
+ (void)impostaChiaveDati:(nullable NSData *)chiave;

/// Se le carte entrano nel backup del telefono, iCloud compreso.
///
/// Su iPhone la risposta di partenza è sì, al contrario di Android: il backup
/// di iCloud è cifrato e legato all'account di chi possiede il telefono, e chi
/// cambia iPhone ritrova le carte senza esportarle a mano. Si spegne da
/// Impostazioni, e allora la cartella dei dati esce dal backup.
+ (BOOL)carteNelBackup;
+ (void)metticiLeCarteNelBackup:(BOOL)dentro;

/// Butta via tutte le carte in una scrittura sola.
+ (BOOL)azzeraTutto:(NSError **)errore;

#pragma mark - Passaggio delle carte con i QR

/// I testi dei QR da mostrare, in ordine, con dentro tutte le carte.
/// Come sono fatti sta in src/transfer.h.
+ (nullable NSArray<NSString *> *)codiciDaMostrare:(NSError **)errore;

/// A che punto è la raccolta, dati i QR letti finora: `ricevuti` e `totale`.
/// Totale a 0 vuol dire che fra i codici letti non ce n'è ancora uno di
/// OpenCard, e non è un errore: la fotocamera inquadra di tutto.
+ (BOOL)statoRaccolta:(NSArray<NSString *> *)letti
             ricevuti:(NSInteger *)ricevuti
               totale:(NSInteger *)totale
               errore:(NSError **)errore;

/// Le carte contenute nei QR letti, senza scrivere niente.
+ (nullable NSArray<OCCarta *> *)carteRicevute:(NSArray<NSString *> *)letti
                                        errore:(NSError **)errore;

/// Scrive le carte ricevute e dice quante ne ha scritte, -1 se fallisce.
/// `azzera` acceso butta via quelle che c'erano.
+ (NSInteger)applicaRicevute:(NSArray<NSString *> *)letti
                      azzera:(BOOL)azzera
                      errore:(NSError **)errore;

@end

NS_ASSUME_NONNULL_END
