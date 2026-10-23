// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Denovo srl <info@denovo.srl>
// Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.

#import <UIKit/UIKit.h>

@interface OCSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;

/// Dopo un cambio di lingua: l'interfaccia rinasce con i testi nuovi e torna
/// sulle impostazioni, come fa Android con recreate().
- (void)rifaiInterfacciaSulleImpostazioni;
@end
