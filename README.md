# OpenCard

Tutte le tue tessere fedeltà e codici usa-e-getta sul telefono e sullo smartwatch, senza registrazione,
senza pubblicità e funzionante offline.

## Dove si scarica

L'app è pubblicata sui due store ed è gratis:

<p align="center">
  <a href="https://apps.apple.com/it/app/opencard/id6805435861"><img src="immagini/badge-app-store-it.png" alt="Scarica su App Store" height="65"></a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://play.google.com/store/apps/details?id=srl.denovo.opencard"><img src="immagini/badge-google-play-it.png" alt="Disponibile su Google Play" height="65"></a>
</p>

- App Store: `https://apps.apple.com/it/app/opencard/id6805435861`
- Google Play: `https://play.google.com/store/apps/details?id=srl.denovo.opencard`

Su Google Play c'è anche l'app per gli smartwatch Wear OS, come Samsung Galaxy
Watch e Google Pixel Watch: si installa dal Play Store dell'orologio e le carte
arrivano dal telefono. L'app per Apple Watch è in arrivo.

## Requisiti

- **Android 6.0** (API 23) o successivo. L'app è compilata contro l'API 36 e
  contiene il codice nativo per `arm64-v8a` e `armeabi-v7a`.
- **iOS 15.0** o successivo, solo iPhone. Sono gli stessi modelli di iOS 13,
  dall'iPhone 6s e dal primo SE in su, con il sistema aggiornato.
- **Wear OS 3** (API 30) o successivo per l'app dell'orologio, collegato a un
  telefono Android con OpenCard: il telefono manda le carte all'orologio via
  Bluetooth, senza passare da internet.
- **Apple Watch**: in arrivo.

## Struttura

```
src/                   codice C comune
  codegen.[ch]         generazione di QR e barcode con zint
  store.[ch]           persistenza delle carte in JSON
  backup.[ch]          esportazione e lettura dei backup
  third-party/         cJSON (MIT)
  android/             ramo Android: Kotlin, JNI, Gradle
    app/               l'app del telefono
    wear/              l'app per gli smartwatch Wear OS
    condiviso/         il codice Kotlin comune a telefono e orologio
  ios/                 ramo iOS: Objective-C
```

Il core dipende da [zint](https://github.com/zint/zint) 2.13 (BSD-3-Clause),
atteso in `src/third-party/zint/`, e da zlib. Il progetto Android lo compila
da solo con CMake e l'NDK.

La logica condivisa tra Android e iOS si trova nella cartella principale `src/`.
Nelle due sottocartelle si trovano le differenti implementazioni verso l'hardware
che gestiscono le schermate, la fotocamera, la luminosità dello schermo e
il selettore di file, che sono necessariamente doppie.

## I dati

Le carte vengono salvate in un file JSON leggibile, nella directory dei dati dell'app.
Liberamente accessibile, si può copiare e spostare senza altri strumenti ed è human
friendly.

## Marchi e immagini

Il logo Denovo, il marchio OpenCard e le icone **non si trovano in questo
repository**: sono segni distintivi di Denovo srl e la licenza AGPL riguarda il
codice sorgente, non i marchi. Al loro posto, per consentire la fruibilità, sono
presenti dei segnaposto neutri con gli stessi nomi e le stesse misure, quindi l'app
si compila e funziona anche senza.

Chi compila la propria versione inserisce le proprie immagini, con gli stessi
nomi di file dei segnaposto.

I due riquadri degli store qui sopra sono di Google e di Apple. Sono i file
ufficiali, non modificati, e servono solo a collegare le schede dell'app: anche
loro restano fuori dall'AGPL, che riguarda il codice.

Google Play e il logo Google Play sono marchi di Google LLC. Apple e il logo
Apple sono marchi di Apple Inc., registrati negli Stati Uniti e in altri paesi.
App Store è un marchio di servizio di Apple Inc.

## Licenza

AGPL-3.0-or-later, licenza commerciale su richiesta. Vedi `LICENSE` e
`LICENSING.md`.
