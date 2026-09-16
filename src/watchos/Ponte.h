// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
//
// Il core in C visto da Swift. Il compilatore legge questi header e le funzioni
// si chiamano da Swift così come sono: il ponte a mano che su Android fa il JNI
// qui non serve.

#include "store.h"
#include "backup.h"
#include "codegen.h"
