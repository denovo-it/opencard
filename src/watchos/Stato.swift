// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

import SwiftUI

/// Al posto di `@State`. Dall'SDK di Xcode 27 `@State` è una macro, e il
/// plugin che la espande gira solo su macOS: con quella sintassi le schermate
/// non si compilano da Linux. Lo `State` vero resta un property wrapper, e
/// questo lo avvolge e basta: stessa cosa, senza la macro.
@propertyWrapper
struct Stato<Value>: DynamicProperty {
    private var stato: State<Value>

    init(wrappedValue: Value) {
        stato = State(wrappedValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { stato.wrappedValue }
        nonmutating set { stato.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { stato.projectedValue }
}

extension Stato where Value: ExpressibleByNilLiteral {
    init() {
        self.init(wrappedValue: nil)
    }
}
