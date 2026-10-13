// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// OpenCard su Apple Watch: l'elenco delle carte e il codice da far leggere alla
// cassa. Le carte arrivano dal telefono, sull'orologio non si scrivono. È la
// stessa app del modulo wear di Android, in SwiftUI perché watchOS non ammette
// altro.

import SwiftUI
import WatchKit

@main
struct OpenCardOrologio: App {
    @StateObject private var carte = Carte()

    var body: some Scene {
        WindowGroup {
            ElencoView()
                .environmentObject(carte)
        }
    }
}

/// Le carte salvate sull'orologio, rilette dal core quando cambiano.
final class Carte: ObservableObject {
    @Published private(set) var elenco: [Carta] = []
    /// Vero se il file delle carte non si apre o non si legge.
    @Published private(set) var guasto = false

    private var aperto = false
    private var telefono: DalTelefono?

    init() {
        Nucleo.coda.async {
            do {
                try Nucleo.apri()
                self.aperto = true
                #if PROVA
                Self.caricaProva()
                #endif
            } catch {
                NSLog("OpenCard: dati non aperti: \(error)")
            }
            self.ricarica()
        }
        telefono = DalTelefono(self)
    }

    /// Le carte arrivate dal telefono al posto di quelle che c'erano.
    func ripristina(_ dati: Data) {
        Nucleo.coda.async {
            guard self.aperto else { return }
            do {
                try Nucleo.ripristina(dati)
            } catch {
                NSLog("OpenCard: carte dal telefono non lette: \(error)")
                return
            }
            self.ricarica()
        }
    }

    func ricarica() {
        Nucleo.coda.async {
            let letto = self.aperto ? Result { try Nucleo.tutte() } : .failure(GuastoNucleo(description: "chiuso"))
            DispatchQueue.main.async {
                switch letto {
                case .success(let carte):
                    self.elenco = carte
                    self.guasto = false
                case .failure(let errore):
                    NSLog("OpenCard: carte non lette: \(errore)")
                    self.guasto = true
                }
            }
        }
    }

    #if PROVA
    /// Solo nelle build per il simulatore: un backup messo dallo script nella
    /// cartella dei dati entra al primo avvio, al posto del telefono che non c'è.
    private static func caricaProva() {
        guard let cartella = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                          in: .userDomainMask,
                                                          appropriateFor: nil, create: false) else { return }
        let file = cartella.appendingPathComponent("prova-backup.json")
        guard let dati = try? Data(contentsOf: file) else { return }
        do {
            let quante = try Nucleo.ripristina(dati)
            try FileManager.default.removeItem(at: file)
            NSLog("OpenCard: prova caricata, \(quante) carte")
        } catch {
            NSLog("OpenCard: prova non caricata: \(error)")
        }
    }
    #endif
}

/// L'elenco delle carte, ognuna sul suo colore. Un tocco apre il codice.
struct ElencoView: View {
    @EnvironmentObject private var carte: Carte
    @Stato private var percorso: [Int] = []

    var body: some View {
        NavigationStack(path: $percorso) {
            Group {
                if carte.guasto {
                    Avviso(testo: "errore_dati_wear")
                } else if carte.elenco.isEmpty {
                    Avviso(testo: "nessuna_carta_wear")
                } else {
                    List(carte.elenco) { carta in
                        NavigationLink(value: carta.id) {
                            Text(carta.etichetta)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(esadecimale: carta.colore))
                        )
                    }
                }
            }
            .navigationTitle("OpenCard")
            .navigationDestination(for: Int.self) { id in
                if let carta = carte.elenco.first(where: { $0.id == id }) {
                    CodiceView(carta: carta)
                }
            }
        }
        #if PROVA
        // Nel simulatore non si tocca lo schermo: OPENCARD_CARTA=<id> apre una
        // carta appena l'elenco è pronto, per fotografare la schermata.
        .onChange(of: carte.elenco) { elenco in
            if let valore = ProcessInfo.processInfo.environment["OPENCARD_CARTA"],
               let id = Int(valore), percorso.isEmpty, elenco.contains(where: { $0.id == id }) {
                percorso = [id]
            }
        }
        #endif
    }
}

private struct Avviso: View {
    let testo: LocalizedStringKey

    var body: some View {
        ScrollView {
            Text(testo)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
        }
    }
}

/// Il codice della carta, da far leggere alla cassa.
///
/// A differenza di Wear OS la luminosità non si può alzare: watchOS non lo
/// permette alle app. E l'app non può nemmeno restare davanti più a lungo:
/// `isFrontmostTimeoutExtended` è deprecata da watchOS 7 («No longer
/// supported»); quando l'orologio torna al quadrante lo decide l'utente nelle
/// impostazioni.
///
/// La barra in alto è nascosta, per lasciare lo schermo al codice: si torna
/// all'elenco con un tocco sullo schermo. Il lettore della cassa non tocca, e
/// senza la freccia indietro lo scorrimento dal bordo non lo trova nessuno. L'ora in alto a destra invece
/// resta, watchOS non la toglie (`persistentSystemOverlays` non la nasconde):
/// il codice le passa accanto.
struct CodiceView: View {
    let carta: Carta

    @Environment(\.displayScale) private var scalaSchermo
    @Environment(\.dismiss) private var chiudi
    @Stato private var immagine: CGImage?
    @Stato private var guasto = false

    /// Zona bianca ai lati dei codici a barre, in moduli: 10, come Code 128,
    /// Code 39 e ITF. Gli stessi valori di `CodiceActivity` su Wear OS.
    static let quieteBarre = 10
    /// Zona bianca intorno ai codici quadrati e a più righe, in moduli: 4, come il QR.
    static let quieteQuadrati = 4
    /// Distanza dal bordo dello schermo, in punti: gli angoli sono arrotondati.
    static let margine: CGFloat = 8
    /// Verso della rotazione: la cima del codice va verso la mano, così nome e
    /// numero si leggono dritti tendendo il braccio verso il lettore. Sul polso
    /// sinistro è orario, sul destro antiorario. La corona non conta: quando la
    /// si sposta, watchOS gira lo schermo da solo.
    static var gradi: Double {
        #if PROVA
        // Nel simulatore il polso non si cambia: OPENCARD_POLSO=destro.
        if ProcessInfo.processInfo.environment["OPENCARD_POLSO"] == "destro" { return -90 }
        #endif
        return WKInterfaceDevice.current().wristLocation == .right ? -90 : 90
    }

    /// Le fasce sopra e sotto il codice, in punti: il nome sopra, il numero
    /// sotto. Dritto, quella del nome sta in alto accanto all'ora. Ruotato,
    /// quella che finisce sul lato destro, dove c'è l'ora, è larga quanto
    /// basta per tenerne lontano il codice.
    static func fasce(ruotato: Bool) -> (nome: CGFloat, numero: CGFloat) {
        guard ruotato else { return (28, 18) }
        return gradi > 0 ? (52, 18) : (18, 52)
    }

    var body: some View {
        GeometryReader { spazio in
            let schermo = spazio.size
            let ruotato = immagine.map { ruota($0, schermo: schermo) } ?? false
            contenuto(in: ruotato ? CGSize(width: schermo.height, height: schermo.width) : schermo,
                      ruotato: ruotato)
                .rotationEffect(.degrees(ruotato ? Self.gradi : 0))
                .frame(width: schermo.width, height: schermo.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { chiudi() }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: disegna)
    }

    private func contenuto(in spazio: CGSize, ruotato: Bool) -> some View {
        VStack(spacing: 2) {
            Text(carta.etichetta)
                .font(.footnote)
                .lineLimit(1)
                .frame(height: Self.fasce(ruotato: ruotato).nome, alignment: ruotato ? .center : .top)
                // Dritto, il nome sta sulla riga dell'ora: a sinistra, e si
                // accorcia prima di arrivarci, come i titoli di watchOS.
                .frame(maxWidth: .infinity, alignment: ruotato ? .center : .leading)
                .padding(.trailing, ruotato ? 0 : 52)
            if let immagine {
                codice(immagine, in: Self.perIlCodice(spazio, ruotato: ruotato))
                    .frame(maxHeight: .infinity)
            } else if guasto {
                Text("errore_dati_wear")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer()
            }
            Text(Nucleo.raggruppato(carta.codice))
                .font(.caption2)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: Self.fasce(ruotato: ruotato).numero)
        }
        .padding(Self.margine)
        .frame(width: spazio.width, height: spazio.height)
    }

    private func disegna() {
        let carta = carta
        Nucleo.coda.async {
            let letta = try? Nucleo.immagine(carta)
            DispatchQueue.main.async {
                immagine = letta
                guasto = letta == nil
            }
        }
    }

    /// Lo spazio per il codice e la sua zona bianca, in punti.
    static func perIlCodice(_ schermo: CGSize, ruotato: Bool) -> CGSize {
        let altezze = fasce(ruotato: ruotato)
        let testi = altezze.nome + altezze.numero + 4
        return CGSize(width: max(schermo.width - 2 * margine, 20),
                      height: max(schermo.height - 2 * margine - testi, 20))
    }

    /// La zona bianca da aggiungere, in moduli, in orizzontale e in verticale.
    /// EAN e UPC escono dal core con la loro; i codici a barre non ne hanno
    /// bisogno sopra e sotto.
    private var quiete: (x: Int, y: Int) {
        if carta.aPiuRighe { return (Self.quieteQuadrati, Self.quieteQuadrati) }
        let propria = opencard_simbologia_quiete_propria(
            opencard_simbologia(rawValue: UInt32(carta.simbologia))) != 0
        return (propria ? 0 : Self.quieteBarre, 0)
    }

    /// Quanti pixel dello schermo per modulo, zona bianca compresa: il numero
    /// intero più grande che entra. Un modulo è sempre fatto dello stesso
    /// numero di pixel, quindi il codice resta netto a qualsiasi misura.
    /// Un codice a barre troppo alto si accorcia, perché una sua fascia basta
    /// al lettore; uno a più righe deve entrare tutto.
    private func pixelPerModulo(_ immagine: CGImage, in spazio: CGSize) -> Int {
        let modulo = CGFloat(Self.modulo(immagine))
        let moduliLarghi = CGFloat(immagine.width) / modulo + CGFloat(2 * quiete.x)
        let moduliAlti = CGFloat(immagine.height) / modulo + CGFloat(2 * quiete.y)
        var pixel = floor(spazio.width * scalaSchermo / moduliLarghi)
        if carta.aPiuRighe {
            pixel = min(pixel, floor(spazio.height * scalaSchermo / moduliAlti))
        }
        return max(Int(pixel), 1)
    }

    /// Vero se il codice, girato di 90 gradi, esce con moduli più grossi. Vale
    /// per quelli larghi e bassi: sul lato lungo dello schermo un EAN-13 passa
    /// da 2 a 4 pixel per modulo. Un QR, quadrato, resta dritto.
    private func ruota(_ immagine: CGImage, schermo: CGSize) -> Bool {
        let girato = CGSize(width: schermo.height, height: schermo.width)
        return pixelPerModulo(immagine, in: Self.perIlCodice(girato, ruotato: true))
            > pixelPerModulo(immagine, in: Self.perIlCodice(schermo, ruotato: false))
    }

    private func codice(_ immagine: CGImage, in spazio: CGSize) -> some View {
        let pixel = pixelPerModulo(immagine, in: spazio)
        let fattore = CGFloat(pixel) / CGFloat(Self.modulo(immagine))
        let bordoX = CGFloat(quiete.x * pixel) / scalaSchermo
        let bordoY = CGFloat(quiete.y * pixel) / scalaSchermo
        let larghezza = CGFloat(immagine.width) * fattore / scalaSchermo
        let altezza = min(CGFloat(immagine.height) * fattore / scalaSchermo,
                          spazio.height - 2 * bordoY)

        return Image(decorative: immagine, scale: scalaSchermo / fattore)
            .interpolation(.none)
            .frame(width: larghezza, height: altezza, alignment: .center)
            .clipped()
            .padding(.horizontal, bordoX)
            .padding(.vertical, bordoY)
            // Con la closure il bianco resta dietro il codice: `background(Color.white)`
            // si allargava a tutto lo schermo, nome e numero compresi.
            .background { Color.white }
    }

    /// Quanti pixel del disegno fa un modulo. Di solito 8, ma per i codici
    /// molto lunghi il core scende di scala: si ricava dalla riga centrale,
    /// dove ogni tratto bianco o nero è largo un numero intero di moduli.
    static func modulo(_ immagine: CGImage) -> Int {
        guard let dati = immagine.dataProvider?.data,
              let byte = CFDataGetBytePtr(dati) else { return 8 }
        let passo = immagine.bitsPerPixel / 8
        let riga = byte + (immagine.height / 2) * immagine.bytesPerRow
        var risultato = 0
        var corsa = 0
        var nero = riga[0] < 128
        for x in 0..<immagine.width {
            let questo = riga[x * passo] < 128
            if questo == nero {
                corsa += 1
            } else {
                risultato = mcd(risultato, corsa)
                corsa = 1
                nero = questo
            }
        }
        risultato = mcd(risultato, corsa)
        return max(risultato, 1)
    }

    private static func mcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : mcd(b, a % b)
    }
}

extension Color {
    /// Da "#RRGGBB", come lo scrive il core.
    init(esadecimale: String) {
        var valore: UInt64 = 0
        Scanner(string: String(esadecimale.drop(while: { $0 == "#" }))).scanHexInt64(&valore)
        self.init(red: Double((valore >> 16) & 0xFF) / 255,
                  green: Double((valore >> 8) & 0xFF) / 255,
                  blue: Double(valore & 0xFF) / 255)
    }
}
