// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// OpenCard su Apple Watch: l'elenco delle carte e il codice da far leggere alla
// cassa. Le carte arrivano dal telefono, sull'orologio non si scrivono. È la
// stessa app del modulo wear di Android, in SwiftUI perché watchOS non ammette
// altro.

import SwiftUI

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
    @State private var percorso: [Int] = []

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
/// permette alle app.
struct CodiceView: View {
    let carta: Carta

    @Environment(\.displayScale) private var scalaSchermo
    @State private var immagine: CGImage?
    @State private var guasto = false

    var body: some View {
        GeometryReader { spazio in
            VStack(spacing: 2) {
                Text(carta.etichetta)
                    .font(.footnote)
                    .lineLimit(1)
                if let immagine {
                    codice(immagine, in: spazio.size)
                } else if guasto {
                    Text("errore_dati_wear")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                Text(Nucleo.raggruppato(carta.codice))
                    .font(.caption2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: spazio.size.width, height: spazio.size.height)
        }
        .onAppear(perform: disegna)
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

    /// Il codice alla misura più grande che non lo sfoca.
    ///
    /// Il core disegna 4 pixel per modulo. Sullo schermo ogni pixel del disegno
    /// diventa un numero intero di pixel, oppure, se il codice è più largo dello
    /// schermo, 2 o 1 pixel per modulo: dividere per 2 o per 4 non spezza un
    /// modulo a metà. Un codice a barre troppo alto si accorcia, perché una sua
    /// fascia basta al lettore; uno a più righe deve entrare tutto.
    private func codice(_ immagine: CGImage, in spazio: CGSize) -> some View {
        // Spazio per il nome sopra e il numero sotto.
        let disponibile = CGSize(width: spazio.width, height: max(spazio.height - 44, 20))
        let fattore = Self.fattore(larghezza: immagine.width, altezza: immagine.height,
                                   spazio: disponibile, scala: scalaSchermo,
                                   aPiuRighe: carta.aPiuRighe)
        let larghezza = CGFloat(immagine.width) * fattore / scalaSchermo
        let altezza = CGFloat(immagine.height) * fattore / scalaSchermo

        return Image(decorative: immagine, scale: scalaSchermo / fattore)
            .interpolation(.none)
            .frame(width: larghezza, height: min(altezza, disponibile.height), alignment: .center)
            .clipped()
    }

    static func fattore(larghezza: Int, altezza: Int, spazio: CGSize, scala: CGFloat,
                        aPiuRighe: Bool) -> CGFloat {
        let pixelLarghi = spazio.width * scala
        let pixelAlti = spazio.height * scala
        let adatto: (CGFloat) -> Bool = { fattore in
            CGFloat(larghezza) * fattore <= pixelLarghi
                && (!aPiuRighe || CGFloat(altezza) * fattore <= pixelAlti)
        }
        let intero = floor(min(pixelLarghi / CGFloat(larghezza),
                               aPiuRighe ? pixelAlti / CGFloat(altezza) : .infinity))
        if intero >= 1 { return intero }
        for fattore: CGFloat in [0.5, 0.25] where adatto(fattore) {
            return fattore
        }
        return 0.25
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
