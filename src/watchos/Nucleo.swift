// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

import CoreGraphics
import Foundation

/// Una carta come serve all'orologio: nome, codice e come disegnarlo.
struct Carta: Identifiable, Equatable {
    let id: Int
    let etichetta: String
    let codice: String
    /// Uno dei valori di `opencard_simbologia`, da 0 a 17.
    let simbologia: Int
    /// "#RRGGBB": quello scelto a mano o quello che spetta all'id.
    let colore: String
    let preferita: Bool

    /// Vero per i codici che si disegnano su più righe o come quadrato. Una
    /// fascia orizzontale di un codice a barre è il codice intero, di questi no.
    var aPiuRighe: Bool {
        [OPENCARD_SIM_QR, OPENCARD_SIM_AZTEC, OPENCARD_SIM_DATAMATRIX,
         OPENCARD_SIM_PDF417, OPENCARD_SIM_MICROQR]
            .map { Int($0.rawValue) }
            .contains(simbologia)
    }
}

struct GuastoNucleo: Error, CustomStringConvertible {
    let description: String
}

/// Il core in C. Come sul telefono, tutte le operazioni sui dati passano da un
/// thread solo, `coda`: quello che arriva dal telefono e quello che legge la
/// schermata non si pestano.
enum Nucleo {
    static let coda = DispatchQueue(label: "srl.denovo.opencard.dati")

    /// Da chiamare una volta, su `coda`, prima di tutto il resto.
    static func apri() throws {
        let cartella = try FileManager.default.url(for: .applicationSupportDirectory,
                                                   in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
        guard opencard_store_init(cartella.path) == OPENCARD_OK else {
            throw GuastoNucleo(description: "cartella dei dati non valida")
        }
        // La chiave prima di qualsiasi lettura: un file cifrato senza chiave
        // sembra rotto.
        if let chiave = ChiaveDati.dammi() {
            chiave.withUnsafeBytes { grezzi in
                opencard_store_chiave(grezzi.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        guard opencard_init_db() == OPENCARD_OK else {
            throw GuastoNucleo(description: "file delle carte non aperto")
        }
    }

    /// Tutte le carte, con le preferite in cima come sul Wear OS.
    static func tutte() throws -> [Carta] {
        var lista = opencard_lista()
        var guasto = opencard_errore()
        guard opencard_get_all(&lista, &guasto) == OPENCARD_OK else {
            throw errore(guasto)
        }
        defer { opencard_lista_free(&lista) }

        var carte: [Carta] = []
        for indice in 0..<lista.n {
            var carta = lista.carte[indice]
            var colore = [CChar](repeating: 0, count: Int(OPENCARD_COLOR_MAX))
            opencard_card_color(&carta, &colore, colore.count)
            carte.append(Carta(id: Int(carta.id),
                               etichetta: testo(carta.label),
                               codice: testo(carta.code),
                               simbologia: Int(carta.simbologia.rawValue),
                               colore: stringa(colore),
                               preferita: carta.favorite != 0))
        }
        return carte.filter { $0.preferita } + carte.filter { !$0.preferita }
    }

    /// Il codice disegnato dal core, pixel per pixel, senza sfumature.
    static func immagine(_ carta: Carta) throws -> CGImage {
        var pixel: UnsafeMutablePointer<UInt8>?
        var larghezza: Int32 = 0
        var altezza: Int32 = 0
        var messaggio = [CChar](repeating: 0, count: 128)

        let esito = opencard_render_bitmap_simbologia(
            carta.codice, opencard_simbologia(rawValue: UInt32(carta.simbologia)),
            &pixel, &larghezza, &altezza, &messaggio, messaggio.count)
        guard esito == 0, let pixel else {
            throw GuastoNucleo(description: stringa(messaggio))
        }
        defer { opencard_free_bitmap(pixel) }

        let dati = Data(bytes: pixel, count: Int(larghezza) * Int(altezza) * 3)
        guard let fornitore = CGDataProvider(data: dati as CFData),
              let immagine = CGImage(width: Int(larghezza), height: Int(altezza),
                                     bitsPerComponent: 8, bitsPerPixel: 24,
                                     bytesPerRow: Int(larghezza) * 3,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                     provider: fornitore, decode: nil,
                                     shouldInterpolate: false, intent: .defaultIntent) else {
            throw GuastoNucleo(description: "immagine non creata")
        }
        return immagine
    }

    /// Il codice a blocchi di tre, per leggerlo a occhio.
    static func raggruppato(_ codice: String) -> String {
        var uscita = [CChar](repeating: 0, count: codice.utf8.count * 2 + 4)
        guard opencard_grouped_code(codice, &uscita, uscita.count) >= 0 else { return codice }
        return stringa(uscita)
    }

    /// Le carte arrivate dal telefono, nel formato del backup, al posto di
    /// quelle che c'erano: l'orologio non modifica mai una carta, quindi non ha
    /// niente da perdere. Torna quante sono.
    @discardableResult
    static func ripristina(_ dati: Data) throws -> Int {
        guard !dati.isEmpty else { throw GuastoNucleo(description: "backup vuoto") }

        var lista = opencard_lista()
        var guasto = opencard_errore()
        let letto = dati.withUnsafeBytes { grezzi in
            opencard_backup_leggi(grezzi.bindMemory(to: CChar.self).baseAddress,
                                  grezzi.count, &lista, &guasto)
        }
        guard letto == OPENCARD_OK else { throw errore(guasto) }
        defer { opencard_lista_free(&lista) }

        guard opencard_replace_all(&lista, &guasto) == OPENCARD_OK else {
            throw errore(guasto)
        }
        return lista.n
    }

    // MARK: - Stringhe C

    private static func errore(_ guasto: opencard_errore) -> GuastoNucleo {
        var copia = guasto
        var messaggio = [CChar](repeating: 0, count: 256)
        opencard_errore_testo(&copia, &messaggio, messaggio.count)
        return GuastoNucleo(description: stringa(messaggio))
    }

    private static func stringa(_ byte: [CChar]) -> String {
        byte.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// Un campo `char[N]` di una struttura C, che Swift vede come una tupla.
    /// Il core li termina sempre, ma si legge solo dentro la misura del campo.
    private static func testo<Campo>(_ campo: Campo) -> String {
        withUnsafeBytes(of: campo) { grezzi in
            let fine = grezzi.firstIndex(of: 0) ?? grezzi.count
            return String(decoding: grezzi[..<fine], as: UTF8.self)
        }
    }
}
