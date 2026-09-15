# Le classi che il ponte JNI costruisce dal lato C non sono mai istanziate da
# Kotlin: senza queste regole R8 le toglierebbe e l'app cadrebbe al primo codice.
# Sono le stesse quattro del telefono, e per lo stesso motivo.
-keep class srl.denovo.opencard.Carta { *; }
-keep class srl.denovo.opencard.ImmagineCodice { *; }
-keep class srl.denovo.opencard.OpenCardException { *; }
-keep class srl.denovo.opencard.Core { *; }
