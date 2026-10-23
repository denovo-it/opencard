// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// L'unico Swift dell'app per iPhone: WidgetCenter esiste solo in Swift, e
// OCWidget.m lo raggiunge da qui, cercando la classe per nome.

import Foundation
import WidgetKit

@objc(OCWidgetCentro)
final class OCWidgetCentro: NSObject {
    @objc static func ricarica() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
