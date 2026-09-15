#!/usr/bin/env python3
"""Scrive i file di lingua di Android e di iPhone partendo da un JSON per lingua.

Le stringhe stanno una volta sola in `src/lingue/<lingua>.json`, con i
segnaposto scritti in forma neutra:

    {1:testo}    diventa  %1$s   su Android e  %1$@   su iPhone
    {1:intero}   diventa  %1$d   su Android e  %1$ld  su iPhone

Il plurale sta in due chiavi, `<nome>_uno` e `<nome>_altro`: da qui esce un
blocco <plurals> su Android e una voce nello .stringsdict su iPhone.

Da lanciare dalla radice del progetto:

    python3 src/lingue/genera.py            scrive i file
    python3 src/lingue/genera.py --controlla   dice solo se sono aggiornati

Il secondo modo serve alla compilazione e ai controlli: esce con 1 se un file
generato non corrisponde al JSON, cioè se qualcuno ha modificato a mano un
`strings.xml` o un `Localizable.strings`.
"""

import json
import plistlib
import re
import sys
from pathlib import Path

RADICE = Path(__file__).resolve().parent.parent.parent
LINGUE = Path(__file__).resolve().parent

LINGUA_BASE = "en"          # finisce in res/values e in en.lproj
SUFFISSO_UNO = "_uno"
SUFFISSO_ALTRO = "_altro"

# Quasi tutte le stringhe sono uguali sulle due piattaforme. Le poche che devono
# dire cose diverse, perché parlano di iCloud o del permesso di rete di Android,
# portano il suffisso e finiscono solo nei file della loro piattaforma.
SUFFISSO_ANDROID = "_android"
SUFFISSO_IPHONE = "_ios"

# L'orologio (modulo wear) ha poche frasi sue, e non gli servono quelle del
# telefono: prende app_name e le chiavi con questo suffisso, che gli altri due
# non vedono.
SUFFISSO_OROLOGIO = "_wear"

SEGNAPOSTO = re.compile(r"\{(\d+):(testo|intero)\}")

INTESTAZIONE = "generato da src/lingue/genera.py: non modificarlo a mano"


def leggi(lingua):
    """Il JSON di una lingua, nell'ordine in cui è scritto."""
    with open(LINGUE / f"{lingua}.json", encoding="utf-8") as f:
        return json.load(f)


def lingue_presenti():
    return sorted(p.stem for p in LINGUE.glob("*.json"))


def per_piattaforma(voci, suffisso_da_tenere):
    """Le voci di una piattaforma: le comuni più le sue, senza quelle dell'altra."""
    altro = SUFFISSO_IPHONE if suffisso_da_tenere == SUFFISSO_ANDROID else SUFFISSO_ANDROID
    return {c: t for c, t in voci.items()
            if not c.endswith(altro) and not c.endswith(SUFFISSO_OROLOGIO)}


def per_orologio(voci):
    return {c: t for c, t in voci.items() if c == "app_name" or c.endswith(SUFFISSO_OROLOGIO)}


def dividi_plurali(voci):
    """Separa le stringhe normali dai plurali.

    Torna (semplici, plurali): `semplici` è una lista di coppie, `plurali` una
    lista di (nome, uno, altro). Un plurale con una sola delle due forme è un
    errore, perché su Android e su iPhone servono tutte e due.
    """
    semplici, plurali, visti = [], [], {}
    for chiave, testo in voci.items():
        if chiave.endswith(SUFFISSO_UNO):
            visti.setdefault(chiave[: -len(SUFFISSO_UNO)], {})["uno"] = testo
        elif chiave.endswith(SUFFISSO_ALTRO):
            visti.setdefault(chiave[: -len(SUFFISSO_ALTRO)], {})["altro"] = testo
        else:
            semplici.append((chiave, testo))
    for nome, forme in visti.items():
        if "uno" not in forme or "altro" not in forme:
            manca = SUFFISSO_ALTRO if "uno" in forme else SUFFISSO_UNO
            raise SystemExit(f"ERRORE: al plurale «{nome}» manca la chiave {nome}{manca}")
        plurali.append((nome, forme["uno"], forme["altro"]))
    return semplici, plurali


def per_android(testo):
    testo = SEGNAPOSTO.sub(lambda m: f"%{m.group(1)}${'s' if m.group(2) == 'testo' else 'd'}", testo)
    testo = testo.replace("\\", "\\\\")
    testo = testo.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    testo = testo.replace("'", "\\'").replace('"', '\\"')
    return testo.replace("\n", "\\n")


def per_iphone(testo):
    testo = SEGNAPOSTO.sub(lambda m: f"%{m.group(1)}${'@' if m.group(2) == 'testo' else 'ld'}", testo)
    testo = testo.replace("\\", "\\\\").replace('"', '\\"')
    return testo.replace("\n", "\\n")


def senza_numero(testo):
    """Il segnaposto singolo dei plurali: Android vuole %d, iPhone %ld."""
    return SEGNAPOSTO.sub(lambda m: "%d" if m.group(2) == "intero" else "%s", testo)


def testo_android(voci):
    semplici, plurali = dividi_plurali(voci)
    righe = ['<?xml version="1.0" encoding="utf-8"?>', f"<!-- {INTESTAZIONE} -->", "<resources>"]
    for chiave, testo in semplici:
        righe.append(f'    <string name="{chiave}">{per_android(testo)}</string>')
    for nome, uno, altro in plurali:
        righe.append("")
        righe.append(f'    <plurals name="{nome}">')
        righe.append(f'        <item quantity="one">{per_android(senza_numero(uno))}</item>')
        righe.append(f'        <item quantity="other">{per_android(senza_numero(altro))}</item>')
        righe.append("    </plurals>")
    righe.append("</resources>")
    return "\n".join(righe) + "\n"


def testo_iphone(voci):
    semplici, _ = dividi_plurali(voci)
    righe = [f"/* {INTESTAZIONE} */", ""]
    for chiave, testo in semplici:
        righe.append(f'"{chiave}" = "{per_iphone(testo)}";')
    return "\n".join(righe) + "\n"


def stringsdict(voci):
    """Il file dei plurali di iPhone. Torna None se la lingua non ne ha."""
    _, plurali = dividi_plurali(voci)
    if not plurali:
        return None
    dizionario = {}
    for nome, uno, altro in plurali:
        dizionario[nome] = {
            "NSStringLocalizedFormatKey": "%#@quantita@",
            "quantita": {
                "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                "NSStringFormatValueTypeKey": "ld",
                "one": SEGNAPOSTO.sub("%ld", uno),
                "other": SEGNAPOSTO.sub("%ld", altro),
            },
        }
    return plistlib.dumps(dizionario, sort_keys=False)


def destinazioni(lingua, voci):
    """Coppie (percorso, contenuto) per una lingua. Il contenuto è già in byte."""
    cartella_android = "values" if lingua == LINGUA_BASE else f"values-{lingua}"
    di_android = per_piattaforma(voci, SUFFISSO_ANDROID)
    di_iphone = per_piattaforma(voci, SUFFISSO_IPHONE)
    fatti = [
        (RADICE / "src/android/app/src/main/res" / cartella_android / "strings.xml",
         testo_android(di_android).encode("utf-8")),
        (RADICE / "src/android/wear/src/main/res" / cartella_android / "strings.xml",
         testo_android(per_orologio(voci)).encode("utf-8")),
        (RADICE / "src/ios" / f"{lingua}.lproj" / "Localizable.strings",
         testo_iphone(di_iphone).encode("utf-8")),
    ]
    plurali = stringsdict(di_iphone)
    if plurali is not None:
        fatti.append((RADICE / "src/ios" / f"{lingua}.lproj" / "Localizable.stringsdict", plurali))
    return fatti


def main():
    controlla = "--controlla" in sys.argv[1:]
    lingue = lingue_presenti()
    if not lingue:
        raise SystemExit("ERRORE: in src/lingue non c'è nessun file di lingua")

    chiavi_base = None
    disallineati = []
    for lingua in lingue:
        voci = leggi(lingua)
        if lingua == LINGUA_BASE:
            chiavi_base = set(voci)
        for percorso, contenuto in destinazioni(lingua, voci):
            if controlla:
                if not percorso.exists() or percorso.read_bytes() != contenuto:
                    disallineati.append(percorso.relative_to(RADICE))
                continue
            percorso.parent.mkdir(parents=True, exist_ok=True)
            percorso.write_bytes(contenuto)
            print(f"scritto {percorso.relative_to(RADICE)} ({len(voci)} voci)")

    # Le traduzioni possono restare indietro, ma una chiave in più o scritta
    # storta non arriva da nessuna parte: meglio dirlo qui che a compilazione fatta.
    if chiavi_base is not None:
        for lingua in lingue:
            if lingua == LINGUA_BASE:
                continue
            in_piu = set(leggi(lingua)) - chiavi_base
            if in_piu:
                print(f"ATTENZIONE: {lingua}.json ha chiavi che {LINGUA_BASE}.json non ha: "
                      + ", ".join(sorted(in_piu)))

    if controlla:
        if disallineati:
            print("Questi file non corrispondono ai JSON di src/lingue:")
            for percorso in disallineati:
                print(f"  {percorso}")
            print("Rilancia: python3 src/lingue/genera.py")
            return 1
        print(f"file di lingua aggiornati ({', '.join(lingue)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
