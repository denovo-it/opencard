# OpenCard

Tutte le tue tessere fedeltà e codici usa-e-getta sul telefono, senza account, senza
pubblicità e funzionante offline.

## Requisiti

- **Android 7.0** (API 24) o successivo. L'app è compilata contro l'API 36 e
  contiene il codice nativo per `arm64-v8a` e `armeabi-v7a`.
- **iOS 13.0** o successivo, solo iPhone.

## Struttura

```
src/                   codice C comune
  codegen.[ch]         generazione di QR e barcode con zint
  store.[ch]           persistenza delle carte in JSON
  backup.[ch]          esportazione e lettura dei backup
  third-party/         cJSON (MIT)
  android/             ramo Android: Kotlin, JNI, Gradle
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

## Licenza

AGPL-3.0-or-later, licenza commerciale su richiesta. Vedi `LICENSE` e
`LICENSING.md`.
