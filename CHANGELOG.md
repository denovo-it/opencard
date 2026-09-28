## 1.0.7-dev (in lavorazione)

- Su Android la scadenza si sceglie con il calendario del telefono.
- Lo ZIP che esporta Catima si importa così com'è, senza doverne tirare fuori il CSV: prima OpenCard diceva che non era un backup. Come per il CSV, le carte si aggiungono a quelle che hai oppure prendono il loro posto.
- Nel CSV per le altre app il saldo esce diviso in numero e valuta, come lo vuole Catima: «12,50 €» arriva a Catima come 12,50 euro, mentre prima Catima lo scartava. Un saldo in punti arriva come numero.
- Eliminando una carta ne sparivano i dati ma non le foto: su iPhone restavano sempre, anche dopo «Cancella tutti i tuoi dati». Su Android restavano quando la carta si eliminava dall'elenco. Ora le foto se ne vanno con la carta. Al primo avvio l'app toglie quelle rimaste dalle versioni precedenti, che finivano anche nel backup del telefono.
- Su un telefono Android in inglese, quando il file delle carte non si apre, il messaggio compare in inglese e non più in italiano.
- Un CSV salvato con la password e riaperto con «Sostituisci» prende il posto delle carte che hai. Prima si aggiungeva e le carte restavano doppie.
- Una carta arrivata da un backup con il colore scritto male si apre in modifica: prima su Android l'app si chiudeva. Il colore torna quello assegnato dall'app.
- L'importazione rifiuta gli archivi ZIP che dichiarano per i file una dimensione diversa da quella vera. Da un backup si tolgono i nomi di foto che puntano fuori dalla cartella delle foto: la carta entra senza quella foto.
- Un backup con molte foto si riapre fino a 64 MB. Prima l'app rifiutava i file sopra i 10 MB, anche quelli che aveva appena esportato lei. Se le foto superano i 64 MB, l'esportazione lo dice subito invece di creare un file che non si riapre.
- Da Catima, una carta con il valore del codice a barre diverso dal numero della carta entra con il codice giusto. Prima OpenCard disegnava il numero della carta e alla cassa si leggeva un altro codice. Il numero della carta finisce in fondo alla nota.

## 1.0.6

- Quando una scheda ha più di 5 carte, in cima alla lista compare un campo di ricerca: scrivendo una parte dell'etichetta restano solo le carte che la contengono, senza badare a maiuscole e accenti. La X a destra svuota il campo e fa tornare tutte le carte. Mentre si cerca le carte non si spostano con la pressione prolungata.
- Sull'orologio è stata aggiornata una libreria di Android che Google Play segnalava come vecchia.

## 1.0.5

- Sull'orologio il codice non arriva più fino al bordo tondo dello schermo: è un po' più piccolo e ha il suo margine bianco tutto intorno, perché alcuni lettori alla cassa non lo leggevano. Vale per i codici a barre e per i QR.
- Un EAN-8 con tutte e 8 le cifre, come lo legge la fotocamera dalla tessera, adesso esce come EAN-8. Prima veniva disegnato come un EAN-13 con quattro zeri davanti, e alla cassa si leggeva un altro numero.

## 1.0.4

- Su Android 6 esportare le carte in un archivio, anche con password, non chiude più l'app.
- Su Android 6 il backup automatico verso il cloud di Google ora si completa.
- I QR si vedono alla loro misura, come sulla tessera, non più a tutta larghezza: alcuni lettori non leggevano un QR così grande. I codici a barre restano a tutta larghezza.
- Nella schermata della carta il codice si allarga e si stringe con due dita, QR e codici a barre.
- Importando un CSV l'app chiede se aggiungere le carte a quelle che ci sono o sostituirle: prima la domanda diceva «Sostituisci» e poi le aggiungeva.
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
