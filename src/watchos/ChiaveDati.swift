// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

import Foundation
import Security

/// La chiave con cui il file delle carte sta cifrato sull'orologio: 32 byte nel
/// portachiavi, come `OCChiaveDati` sul telefono.
///
/// Una differenza voluta: qui la chiave è ThisDeviceOnly e non entra nei
/// backup. Sul telefono deve seguire il backup, perché le carte stanno solo lì;
/// le carte dell'orologio sono una copia di quelle del telefono, e un orologio
/// nuovo le riceve di nuovo.
enum ChiaveDati {
    private static let byte = 32

    private static var ricerca: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "srl.denovo.opencard",
            kSecAttrAccount as String: "opencard-dati",
        ]
    }

    /// La chiave, creata la prima volta. `nil` se il portachiavi non risponde:
    /// allora il core scrive in chiaro, come sul telefono.
    static func dammi() -> Data? {
        leggi() ?? crea()
    }

    private static func leggi() -> Data? {
        var domanda = ricerca
        domanda[kSecReturnData as String] = true
        domanda[kSecMatchLimit as String] = kSecMatchLimitOne

        var trovato: CFTypeRef?
        guard SecItemCopyMatching(domanda as CFDictionary, &trovato) == errSecSuccess,
              let chiave = trovato as? Data, chiave.count == byte else {
            return nil
        }
        return chiave
    }

    private static func crea() -> Data? {
        var chiave = Data(count: byte)
        let esito = chiave.withUnsafeMutableBytes { grezzi in
            SecRandomCopyBytes(kSecRandomDefault, byte, grezzi.baseAddress!)
        }
        guard esito == errSecSuccess else { return nil }

        var nuova = ricerca
        nuova[kSecValueData as String] = chiave
        nuova[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        nuova[kSecAttrSynchronizable as String] = false
        guard SecItemAdd(nuova as CFDictionary, nil) == errSecSuccess else { return nil }
        return chiave
    }
}
