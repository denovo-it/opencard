// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

import Foundation
import WatchConnectivity

/// Le carte dal telefono, con WatchConnectivity: da dispositivo a dispositivo,
/// via Bluetooth o Wi-Fi diretto, nessun server. È quello che fa
/// `DalTelefono.kt` su Wear OS. Le chiavi dei messaggi sono le stesse di
/// `OCOrologio.m` sull'iPhone.
///
/// Il telefono manda tutte le carte nel contesto della sessione a ogni
/// scrittura del file: l'orologio le trova anche se era spento. All'apertura
/// le chiede comunque, se il telefono è a portata.
final class DalTelefono: NSObject, WCSessionDelegate {
    /// Telefono -> orologio: il backup in chiaro, come byte UTF-8.
    private static let carte = "carte"
    /// Orologio -> telefono: vuol dire «mandamele».
    private static let richiesta = "richiesta"

    private unowned let destinazione: Carte

    init(_ destinazione: Carte) {
        self.destinazione = destinazione
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ sessione: WCSession, activationDidCompleteWith stato: WCSessionActivationState,
                 error: Error?) {
        guard stato == .activated else {
            if let error { NSLog("OpenCard: sessione col telefono non attiva: \(error)") }
            return
        }
        // Quello che il telefono ha mandato mentre l'orologio non ascoltava.
        ricevi(sessione.receivedApplicationContext)
        chiedi(sessione)
    }

    func session(_ sessione: WCSession, didReceiveApplicationContext contesto: [String: Any]) {
        ricevi(contesto)
    }

    /// Chiede le carte al telefono. Senza telefono a portata non succede
    /// niente, e l'elenco resta com'era.
    private func chiedi(_ sessione: WCSession) {
        guard sessione.isReachable else { return }
        sessione.sendMessage([Self.richiesta: true], replyHandler: ricevi) { errore in
            NSLog("OpenCard: carte non chieste al telefono: \(errore)")
        }
    }

    private func ricevi(_ messaggio: [String: Any]) {
        guard let dati = messaggio[Self.carte] as? Data else { return }
        destinazione.ripristina(dati)
    }
}
