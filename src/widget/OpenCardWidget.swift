// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Il widget di iPhone: le carte con la stella sulla schermata iniziale. Il
// piccolo ne mostra una, il medio fino a 4, il grande fino a 8. Ogni carta è
// il suo nome sul suo colore, come nell'elenco dell'app: il numero non ci va,
// perché la schermata iniziale la vede chiunque guardi il telefono. Un tocco
// apre la carta nell'app.
//
// Il widget gira in un processo suo e non apre il file cifrato delle carte:
// legge widget.json, che l'app scrive nel contenitore condiviso a ogni
// modifica (OCWidget.m) con id, nome e colore delle carte con la stella.

import SwiftUI
import WidgetKit

/// Una carta come la scrive l'app per il widget.
struct CartaWidget: Decodable, Identifiable {
    let id: Int
    let nome: String
    let colore: String
    /// Colore chiaro: il nome va scritto scuro.
    let chiaro: Bool
    /// Bianco e nero hanno un bordo grigio, per staccarsi dallo sfondo.
    let bordo: Bool
}

struct ElencoWidget: Decodable {
    let carte: [CartaWidget]
}

/// Il contenitore che app e widget hanno in comune: lo stesso nome nei
/// due profili, in OCWidget.m e qui.
let gruppo = "group.srl.denovo.opencard"

func leggiCarte() -> [CartaWidget] {
    guard let cartella = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: gruppo),
          let dati = try? Data(contentsOf: cartella.appendingPathComponent("widget.json")),
          let elenco = try? JSONDecoder().decode(ElencoWidget.self, from: dati)
    else { return [] }
    return elenco.carte
}

struct Momento: TimelineEntry {
    let date: Date
    let carte: [CartaWidget]
}

struct Fornitore: TimelineProvider {
    func placeholder(in contesto: Context) -> Momento {
        Momento(date: Date(), carte: [])
    }

    func getSnapshot(in contesto: Context, completion: @escaping (Momento) -> Void) {
        completion(Momento(date: Date(), carte: leggiCarte()))
    }

    /// Un momento solo, e niente aggiornamenti a orario: è l'app a chiedere
    /// di rifare il widget quando le carte cambiano.
    func getTimeline(in contesto: Context, completion: @escaping (Timeline<Momento>) -> Void) {
        completion(Timeline(entries: [Momento(date: Date(), carte: leggiCarte())], policy: .never))
    }
}

/// opencard://carta/<id>, che l'app apre sulla carta.
func indirizzo(_ carta: CartaWidget) -> URL {
    URL(string: "opencard://carta/\(carta.id)")!
}

func colore(_ esadecimale: String) -> Color {
    let cifre = esadecimale.hasPrefix("#") ? String(esadecimale.dropFirst()) : esadecimale
    let valore = UInt32(cifre, radix: 16) ?? 0xE6642B
    return Color(red: Double((valore >> 16) & 0xFF) / 255,
                 green: Double((valore >> 8) & 0xFF) / 255,
                 blue: Double(valore & 0xFF) / 255)
}

/// Il nome della carta, scuro sui colori chiari.
struct NomeCarta: View {
    let carta: CartaWidget
    let grande: Bool

    var body: some View {
        Text(carta.nome)
            .font(grande ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundColor(carta.chiaro ? Color(red: 0.13, green: 0.13, blue: 0.14) : .white)
            .lineLimit(grande ? 3 : 2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

/// Una carta della griglia: il nome sul colore, angoli arrotondati come
/// nell'elenco dell'app.
struct Tessera: View {
    let carta: CartaWidget

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
        NomeCarta(carta: carta, grande: false)
            .padding(10)
            .background(forma.fill(colore(carta.colore)))
            .overlay(forma.stroke(Color(red: 0.60, green: 0.63, blue: 0.65), lineWidth: carta.bordo ? 1 : 0))
    }
}

struct VistaWidget: View {
    @Environment(\.widgetFamily) private var famiglia
    let momento: Momento

    var body: some View {
        sfondo(contenuto)
    }

    @ViewBuilder
    private var contenuto: some View {
        if momento.carte.isEmpty {
            Text(NSLocalizedString("vuoto_widget", comment: ""))
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if famiglia == .systemSmall {
            // Il piccolo è la carta: il colore lo fa il fondo, e non ha zone
            // da toccare, tutto il widget apre la carta.
            NomeCarta(carta: momento.carte[0], grande: true)
                .widgetURL(indirizzo(momento.carte[0]))
        } else {
            griglia
        }
    }

    /// Due colonne, una fila ogni due carte: 4 nel medio, 8 nel grande.
    private var griglia: some View {
        let quante = famiglia == .systemLarge ? 8 : 4
        let carte = Array(momento.carte.prefix(quante))
        let file = stride(from: 0, to: carte.count, by: 2).map { Array(carte[$0..<min($0 + 2, carte.count)]) }
        let righe = famiglia == .systemLarge ? 4 : 2
        return VStack(spacing: 8) {
            ForEach(0..<righe, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { c in
                        if r < file.count, c < file[r].count {
                            Link(destination: indirizzo(file[r][c])) {
                                Tessera(carta: file[r][c])
                            }
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
    }

    /// Il colore della carta nel piccolo, quello del sistema altrimenti.
    private var coloreFondo: Color {
        if famiglia == .systemSmall, let prima = momento.carte.first {
            return colore(prima.colore)
        }
        return Color(UIColor.systemBackground)
    }

    /// Da iOS 17 il fondo del widget va dichiarato, altrimenti il sistema
    /// mostra un avviso al posto del widget; prima bastava il margine.
    @ViewBuilder
    private func sfondo<V: View>(_ vista: V) -> some View {
        if #available(iOS 17.0, *) {
            vista.containerBackground(for: .widget) { coloreFondo }
        } else {
            vista.padding(12).background(coloreFondo)
        }
    }
}

@main
struct OpenCardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "carte-con-la-stella", provider: Fornitore()) { momento in
            VistaWidget(momento: momento)
        }
        .configurationDisplayName(NSLocalizedString("nome_widget", comment: ""))
        .description(NSLocalizedString("descrizione_widget", comment: ""))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
