## 1.0.4

- Su Android 6 esportare le carte in un archivio, anche con password, non chiude più l'app.
- Su Android 6 il backup automatico verso il cloud di Google ora si completa.
- I QR si vedono alla loro misura, come sulla tessera, non più a tutta larghezza: alcuni lettori non leggevano un QR così grande. I codici a barre restano a tutta larghezza.
- Nella schermata della carta il codice si allarga e si stringe con due dita, QR e codici a barre.
- Le carte arrivano anche sull'orologio: su Galaxy Watch e sugli altri Wear OS l'app mostra il codice della carta scelta, e le carte gliele manda il telefono via Bluetooth, senza passare da internet.

## 1.0.3

- I tipi di codice passano da 5 a 18: Aztec, Data Matrix, PDF417, Micro QR e gli altri si scelgono da un elenco quando si aggiunge una carta. L'elenco parte da Automatico, e chi non sa che codice ha in mano non deve sceglierlo: inquadrando la tessera il tipo lo riconosce il lettore, e scrivendo il codice a mano lo decide l'app.
- Ogni carta può avere una nota, una scadenza e un saldo. Restano vuoti finché non servono.
- Su Android una carta si mette sulla schermata iniziale: si sceglie quando si appoggia il widget, mostra il nome sul colore della carta e con un tocco la apre. Il numero non compare, perché la schermata iniziale la vede chiunque guardi il telefono.
- Un codice lungo disegnato come codice a barre adesso si vede. Capitava con le carte lette da un QR e poi cambiate in codice a barre: l'immagine veniva costruita così larga che parecchi telefoni Android non la mostravano affatto, e al posto delle barre restava il solo testo del codice.
- Scegliendo un tipo di codice che non può contenere quel codice, l'app lo dice subito, appena si sceglie, e poi si rifiuta di salvare: prima la carta si salvava e non mostrava niente. L'avviso compare anche aprendo una carta che è già in quello stato. Con Automatico non capita mai: se il codice non sta in un codice a barre viene disegnato come QR.
- Quando manca l'etichetta o il codice, Salva dice perché non salva: il messaggio è passato in cima al modulo, sotto i due pulsanti. In fondo alla schermata restava fuori dallo schermo e sembrava che Salva non funzionasse.
- Su Android 15 e 16 la fascia in alto con l'ora è di nuovo arancione, e l'ora e le icone si leggono anche col tema chiaro.
- La scadenza si sceglie dal calendario, senza scriverla a mano.
- Ogni carta può avere la foto del fronte e del retro, per leggere quello che sulla tessera è stampato e nel codice non c'è. Si passa da una faccia all'altra scorrendo di lato o con le due frecce, e toccandola si apre a schermo pieno, dove si ingrandisce con due dita.
- Il backup su file adesso è un archivio con dentro le carte e le foto, e si può chiudere con una password.
- Le carte si esportano anche in CSV, il formato che leggono le altre app, e un CSV di Catima si importa qui.
- I codici del passaggio fra telefoni si salvano su un PDF, uno per pagina, da usare quando l'altro telefono non c'è.
- In fondo a Impostazioni c'è «Cancella tutti i tuoi dati», in rosso: toglie da questo telefono le carte, le loro foto e i file temporanei, con una domanda prima. Prima era «Azzera le carte» e stava nel menu dell'elenco, in mezzo alle cose che si usano tutti i giorni.
- Una tessera si aggiunge anche da un PDF, oltre che dalla fotocamera, da una foto e a mano.
- La scheda «Usa & getta» compare solo quando c'è almeno una carta dentro, come già faceva quella con la stella, e la fila delle schede sparisce quando ne resta una sola.
- L'app parla anche inglese: la lingua la sceglie il telefono, e da Impostazioni si può cambiare a mano. Su iPhone la lingua nuova arriva chiudendo e riaprendo l'app.
- In inglese sono in inglese anche i messaggi di errore: prima l'app parlava inglese finché qualcosa non andava storto, e a quel punto rispondeva in italiano.
- Funziona da Android 6 in su, prima serviva Android 7.
- Nella schermata Informazioni c'è l'indirizzo della pagina di OpenCard sul sito, accanto al codice sorgente.
- Il file delle carte sul telefono adesso è cifrato: chi lo tira fuori da un telefono spento, o da un backup, trova byte a caso.
- Da Impostazioni si sceglie se le carte entrano nel backup del telefono verso il cloud di Google. Di partenza è spento, e quello che esce è un elenco che il telefono nuovo rilegge al primo avvio.
- Sempre lì, sotto Privacy, c'è scritto cosa succede alle carte quando il telefono fa il backup: su iPhone rientrano in quello di iCloud, su Android il backup automatico verso Google parte spento e si accende da Impostazioni.

## 1.0.2

- Su iPhone e iPad il marchio in cima alla schermata delle carte resta dentro la barra: si ingrandiva fino a coprire l'elenco.
- Su iPhone e iPad la tastiera si chiude dal modulo di inserimento: si trascina il modulo verso il basso, si tocca fuori dai campi, oppure si usa il tasto della tastiera, che porta dall'etichetta al codice e poi chiude.
- Su iPhone e iPad la carta appena salvata compare subito nell'elenco, senza cambiare scheda e tornare indietro.
- Su iPhone serve iOS 15: sono gli stessi modelli di prima, dall'iPhone 6s in su, ma con il sistema aggiornato.
- I testi dell'app usano le lettere accentate: si legge «è» dove prima c'era «e'».
- Se il codice di una foto non viene letto, l'app riprova con l'immagine intera: le tessere fotografate da lontano adesso passano.

## 1.0.1

- Nella schermata informazioni c'è l'indirizzo del codice sorgente: OpenCard è pubblico su GitHub con licenza AGPL v3.
- Sempre nella schermata informazioni, sotto Legale, c'è l'indirizzo della privacy policy: dice cosa fa l'app con la fotocamera e con i dati delle carte.
- Su Android, le foto scelte dalla galleria vengono lette con meno memoria, così sui telefoni più piccoli l'app non viene chiusa dal sistema mentre legge un codice.

## 1.0.0

- Prima versione pubblica di OpenCard.
- Le tessere fedeltà e i codici usa e getta stanno in un'app sola: la carta si aggiunge inquadrandola con la fotocamera o scrivendo il codice a mano.
- Aprendo una carta il codice compare grande, con lo schermo al massimo della luminosità, pronto per la cassa.
- Le carte passano da un telefono all'altro con dei QR, senza rete e senza account.
- Le carte si esportano in un backup su file e si rimettono a posto da lì.
- Nessun dato raccolto, niente pubblicità.
