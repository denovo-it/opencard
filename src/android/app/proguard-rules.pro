# Le classi che il ponte JNI costruisce dal lato C non sono mai istanziate da
# Kotlin: senza queste regole R8 le toglierebbe e l\'app cadrebbe al primo codice.
-keep class srl.denovo.opencard.Carta { *; }
-keep class srl.denovo.opencard.ImmagineCodice { *; }
-keep class srl.denovo.opencard.OpenCardException { *; }
-keep class srl.denovo.opencard.Core { *; }

# ML Kit registra i suoi componenti per nome: il manifest elenca le classi
# registrar e ML Kit le istanzia con Class.forName(...).newInstance(). Le regole
# che la libreria si porta dietro tengono il nome della classe ma non il
# costruttore, e R8 di AGP 9 lo toglie: il registro resta vuoto, il fornitore
# del lettore non c'è, e l'app muore nel costruttore di ScannerActivity con un
# NullPointerException su getClass(), che è il controllo di null che R8 inietta.
# Verificato dentro l'APK con dexdump: senza questa regola BarcodeRegistrar non
# ha metodi diretti.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}
