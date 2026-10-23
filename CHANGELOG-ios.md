## 1.0.8-dev (in lavorazione)

- Fra i colori della carta ci sono anche il bianco e il nero. Sulla carta bianca nome e icone si scrivono scuri. Le carte bianche e nere hanno un bordo sottile per staccarsi dallo sfondo.
- Le carte si possono vedere su due colonne: la voce «Due colonne» nel menu con i tre puntini accende e spegne la griglia. La scelta resta anche chiudendo l'app.
- Toccando il codice a barre o il QR della carta aperta, il codice si copia negli appunti, pronto da incollare in un'app o in un sito.
- La lingua scelta in Impostazioni vale subito, senza chiudere e riaprire l'app.

## 1.0.7

- OpenCard arriva su Apple Watch: le carte passano dal telefono all'orologio appena il telefono è raggiungibile e alla cassa il codice si mostra dal polso. Un tocco chiude la carta.
- Il campo di ricerca ha lo stesso aspetto delle carte: fondo pieno e angoli arrotondati come loro, al posto della capsula con l'ombra.
- Le foto delle carte si scrivono intere: se l'app si chiude mentre salva una foto, resta quella di prima. Una foto tolta dal modulo se ne va solo quando la carta è salvata.
- La scadenza si legge come 30/09/2026, sulla carta aperta e nel modulo. Prima sulla carta compariva 2026-09-30.
- Lo ZIP che esporta Catima si importa così com'è, senza doverne tirare fuori il CSV: prima OpenCard diceva che non era un backup. Come per il CSV, le carte si aggiungono a quelle che hai oppure prendono il loro posto.
- Nel CSV per le altre app il saldo esce diviso in numero e valuta, come lo vuole Catima: «12,50 €» arriva a Catima come 12,50 euro, mentre prima Catima lo scartava. Un saldo in punti arriva come numero.
- Eliminando una carta ne sparivano i dati ma non le foto, che restavano anche dopo «Cancella tutti i tuoi dati». Ora le foto se ne vanno con la carta. Al primo avvio l'app toglie quelle rimaste dalle versioni precedenti, che finivano anche nel backup del telefono.
- Un CSV salvato con la password e riaperto con «Sostituisci» prende il posto delle carte che hai. Prima si aggiungeva e le carte restavano doppie.
- L'importazione rifiuta gli archivi ZIP che dichiarano per i file una dimensione diversa da quella vera, o che estratti occuperebbero più di 128 MB. Da un backup si tolgono i nomi di foto che puntano fuori dalla cartella delle foto: la carta entra senza quella foto.
- Un backup con molte foto si riapre fino a 64 MB. Prima l'app rifiutava i file sopra i 10 MB, anche quelli che aveva appena esportato lei. Se le foto superano i 64 MB, l'esportazione lo dice subito invece di creare un file che non si riapre.
- Da Catima, una carta con il valore del codice a barre diverso dal numero della carta entra con il codice giusto. Prima OpenCard disegnava il numero della carta e alla cassa si leggeva un altro codice. Il numero della carta finisce in fondo alla nota.
- Una carta senza nome o senza codice, arrivata per esempio dal passaggio con i QR, non rende più illeggibile tutto il file delle carte: l'app la rifiuta e lo dice.
- La scadenza deve essere un giorno che esiste. Una carta salvata con una data impossibile si apre lo stesso, senza quella data.
- L'esportazione e l'importazione con la password non bloccano più lo schermo senza dire niente: mentre l'app calcola la chiave compare la rotella.
- Le foto di una carta non perdono più qualità quando si modifica la carta: prima si ricomprimevano a ogni salvataggio, anche se non erano cambiate.
- I codici GS1-128 e GS1 DataBar Expanded scritti come sulla carta, con le parentesi, «(01)98898765432106(3202)012345», si disegnano. Prima l'app diceva che il codice non era valido.

## 1.0.6

- Quando una scheda ha più di 5 carte, in cima alla lista compare un campo di ricerca: scrivendo una parte dell'etichetta restano solo le carte che la contengono, senza badare a maiuscole e accenti. La X a destra svuota il campo e fa tornare tutte le carte. Mentre si cerca le carte non si spostano con la pressione prolungata.

## 1.0.5

- Un EAN-8 con tutte e 8 le cifre, come lo legge la fotocamera dalla tessera, adesso esce come EAN-8. Prima veniva disegnato come un EAN-13 con quattro zeri davanti, e alla cassa si leggeva un altro numero.

## 1.0.4

- I QR si vedono alla loro misura, come sulla tessera, non più a tutta larghezza: alcuni lettori non leggevano un QR così grande. I codici a barre restano a tutta larghezza.
- Nella schermata della carta il codice si allarga e si stringe con due dita, QR e codici a barre.
- Importando un CSV l'app chiede se aggiungere le carte a quelle che ci sono o sostituirle: prima la domanda diceva «Sostituisci» e poi le aggiungeva.

## 1.0.3

- I tipi di codice passano da 5 a 18: Aztec, Data Matrix, PDF417, Micro QR e gli altri si scelgono da un elenco quando si aggiunge una carta. L'elenco parte da Automatico, e chi non sa che codice ha in mano non deve sceglierlo: inquadrando la tessera il tipo lo riconosce il lettore, e scrivendo il codice a mano lo decide l'app.
- Ogni carta può avere una nota, una scadenza e un saldo. Restano vuoti finché non servono.
- Scegliendo un tipo di codice che non può contenere quel codice, l'app lo dice subito, appena si sceglie, e poi si rifiuta di salvare: prima la carta si salvava e non mostrava niente. L'avviso compare anche aprendo una carta che è già in quello stato. Con Automatico non capita mai: se il codice non sta in un codice a barre viene disegnato come QR.
- Quando manca l'etichetta o il codice, Salva dice perché non salva: il messaggio è passato in cima al modulo, sotto i due pulsanti. In fondo alla schermata restava fuori dallo schermo e sembrava che Salva non funzionasse.
- La scadenza si sceglie dal calendario, senza scriverla a mano.
- Ogni carta può avere la foto del fronte e del retro, per leggere quello che sulla tessera è stampato e nel codice non c'è. Si passa da una faccia all'altra scorrendo di lato o con le due frecce, e toccandola si apre a schermo pieno, dove si ingrandisce con due dita.
- Il backup su file adesso è un archivio con dentro le carte e le foto, e si può chiudere con una password.
- Le carte si esportano anche in CSV, il formato che leggono le altre app, e un CSV di Catima si importa qui.
- I codici del passaggio fra telefoni si salvano su un PDF, uno per pagina, da usare quando l'altro telefono non c'è.
- In fondo a Impostazioni c'è «Cancella tutti i tuoi dati», in rosso: toglie da questo telefono le carte, le loro foto e i file temporanei, con una domanda prima. Prima era «Azzera le carte» e stava nel menu dell'elenco, in mezzo alle cose che si usano tutti i giorni.
- Una tessera si aggiunge anche da un PDF, oltre che dalla fotocamera, da una foto e a mano.
- La scheda «Usa & getta» compare solo quando c'è almeno una carta dentro, come già faceva quella con la stella, e la fila delle schede sparisce quando ne resta una sola.
- L'app parla anche inglese: la lingua la sceglie il telefono, e da Impostazioni si può cambiare a mano. La lingua nuova arriva chiudendo e riaprendo l'app.
- In inglese sono in inglese anche i messaggi di errore: prima l'app parlava inglese finché qualcosa non andava storto, e a quel punto rispondeva in italiano.
- Nella schermata Informazioni c'è l'indirizzo della pagina di OpenCard sul sito, accanto al codice sorgente.
- Il file delle carte sul telefono adesso è cifrato: chi lo tira fuori da un telefono spento, o da un backup, trova byte a caso.
- In Impostazioni, sotto Privacy, c'è scritto cosa succede alle carte quando il telefono fa il backup: rientrano in quello di iCloud.

## 1.0.2

- Prima versione pubblica di OpenCard.
- Le tessere fedeltà e i codici usa e getta stanno in un'app sola: la carta si aggiunge inquadrandola con la fotocamera o scrivendo il codice a mano.
- Aprendo una carta il codice compare grande, con lo schermo al massimo della luminosità, pronto per la cassa.
- Le carte passano da un telefono all'altro con dei QR, senza rete e senza account.
- Le carte si esportano in un backup su file e si rimettono a posto da lì.
- Nella schermata informazioni ci sono l'indirizzo del codice sorgente, pubblico su GitHub con licenza AGPL v3, e sotto Legale quello della privacy policy.
- Nessun dato raccolto, niente pubblicità.
- Serve la versione 15 del sistema, dall'iPhone 6s in su.
