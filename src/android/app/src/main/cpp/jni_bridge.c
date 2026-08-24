/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Denovo srl <info@denovo.srl>
 * Parte di OpenCard. Rilasciato sotto AGPL v3; licenza commerciale su richiesta.
 *
 * Ponte fra il core in C e Kotlin.
 *
 * Qui dentro non c'è logica: si traducono soltanto stringhe, array e oggetti.
 * Ogni funzione che può fallire lancia OpenCardException con il messaggio già
 * pronto per l'utente, così il lato Kotlin non deve conoscere i codici.
 */

#include <jni.h>
#include <stdlib.h>
#include <string.h>

#include "codegen.h"
#include "backup.h"
#include "store.h"
#include "transfer.h"

#define CLASSE_CARTA     "srl/denovo/opencard/Carta"
#define CLASSE_ECCEZIONE "srl/denovo/opencard/OpenCardException"
#define CLASSE_IMMAGINE  "srl/denovo/opencard/ImmagineCodice"

/* Una stringa del core come jstring.
 *
 * Non si usa NewStringUTF: quella vuole il modified UTF-8 di Java, e sui
 * caratteri da quattro byte (le emoji) il comportamento non è definito.
 * Si passa dall'UTF-16, che è quello che Java usa davvero. Il core
 * garantisce UTF-8 valido (opencard_utf8_ripara), ma se un byte storto
 * arriva lo stesso diventa '?', non un salto nel buio. */
static jstring stringa_verso_java(JNIEnv *env, const char *utf8)
{
    const unsigned char *s = (const unsigned char *)utf8;
    size_t n = strlen(utf8);
    jchar *sedici;
    size_t scritti = 0, i = 0;
    jstring risultato;

    /* Un carattere UTF-8 diventa al più una coppia UTF-16: n unita' bastano. */
    sedici = (jchar *)malloc((n > 0 ? n : 1) * sizeof(jchar));
    if (sedici == NULL) {
        return NULL;
    }
    while (i < n) {
        unsigned int cp = 0xFFFD;
        unsigned char testa = s[i];

        if (testa < 0x80) {
            cp = testa;
            i += 1;
        } else if ((testa & 0xE0) == 0xC0 && i + 1 < n) {
            cp = ((testa & 0x1Fu) << 6) | (s[i + 1] & 0x3Fu);
            i += 2;
        } else if ((testa & 0xF0) == 0xE0 && i + 2 < n) {
            cp = ((testa & 0x0Fu) << 12) | ((s[i + 1] & 0x3Fu) << 6)
                 | (s[i + 2] & 0x3Fu);
            i += 3;
        } else if ((testa & 0xF8) == 0xF0 && i + 3 < n) {
            cp = ((testa & 0x07u) << 18) | ((s[i + 1] & 0x3Fu) << 12)
                 | ((s[i + 2] & 0x3Fu) << 6) | (s[i + 3] & 0x3Fu);
            i += 4;
        } else {
            i += 1;
        }
        if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
            cp = 0xFFFD;
        }
        if (cp >= 0x10000) {
            sedici[scritti++] = (jchar)(0xD800 + ((cp - 0x10000) >> 10));
            sedici[scritti++] = (jchar)(0xDC00 + ((cp - 0x10000) & 0x3FF));
        } else {
            sedici[scritti++] = (jchar)cp;
        }
    }
    risultato = (*env)->NewString(env, sedici, (jsize)scritti);
    free(sedici);
    return risultato;
}

static void lancia(JNIEnv *env, const opencard_errore *errore)
{
    char messaggio[512];
    jclass classe = (*env)->FindClass(env, CLASSE_ECCEZIONE);
    jmethodID costruttore;
    jstring testo;
    jthrowable eccezione;

    opencard_errore_testo(errore, messaggio, sizeof(messaggio));
    if (messaggio[0] == '\0') {
        strcpy(messaggio, "Errore imprevisto.");
    }
    if (classe == NULL) {
        return;     /* FindClass ha già messo in coda il suo errore */
    }
    /* Non si passa da ThrowNew, che vuole il modified UTF-8: il messaggio può
     * contenere il nome di una carta, emoji comprese. */
    costruttore = (*env)->GetMethodID(env, classe, "<init>", "(Ljava/lang/String;)V");
    testo = costruttore != NULL ? stringa_verso_java(env, messaggio) : NULL;
    if (testo == NULL) {
        (*env)->ThrowNew(env, classe, "Errore imprevisto.");
        return;
    }
    eccezione = (jthrowable)(*env)->NewObject(env, classe, costruttore, testo);
    if (eccezione != NULL) {
        (*env)->Throw(env, eccezione);
    }
}

static void lancia_memoria(JNIEnv *env)
{
    opencard_errore errore = {OPENCARD_ERR_MEMORIA, 0, {0}, 0};
    lancia(env, &errore);
}

/* Copia una stringa Java in un buffer C. Ritorna 0 se non ci riesce. */
static int stringa(JNIEnv *env, jstring sorgente, char *dest, size_t dest_size)
{
    const char *utf;

    dest[0] = '\0';
    if (sorgente == NULL) {
        return 1;
    }
    utf = (*env)->GetStringUTFChars(env, sorgente, NULL);
    if (utf == NULL) {
        return 0;
    }
    strncpy(dest, utf, dest_size - 1);
    dest[dest_size - 1] = '\0';
    (*env)->ReleaseStringUTFChars(env, sorgente, utf);
    /* GetStringUTFChars consegna il modified UTF-8 di Java: le emoji arrivano
     * come coppie surrogate da sei byte, che fuori da Java non legge nessuno.
     * Si ricodificano in UTF-8 vero prima che finiscano nel file, e un taglio
     * a metà carattere fatto dalla strncpy sparisce con loro. */
    opencard_utf8_ripara(dest);
    return 1;
}

static jobject carta_a_java(JNIEnv *env, jclass classe, jmethodID costruttore,
                            const opencard_card *card)
{
    char colore[OPENCARD_COLOR_MAX];
    jstring label, code, color;
    jobject oggetto;

    opencard_card_color(card, colore, sizeof(colore));

    /* Nome e codice possono avere caratteri fuori dall'ASCII: si convertono
     * per la strada dell'UTF-16. Il colore è sempre "#RRGGBB". */
    label = stringa_verso_java(env, card->label);
    code = stringa_verso_java(env, card->code);
    color = (*env)->NewStringUTF(env, colore);

    /* `coloreScelto` dice se il colore è stato deciso dall'utente: serve al
     * form, che altrimenti non saprebbe se mostrare la scelta o il predefinito. */
    oggetto = (*env)->NewObject(env, classe, costruttore,
                                (jint)card->id, label, code,
                                (jboolean)(card->is_qrcode ? JNI_TRUE : JNI_FALSE),
                                color,
                                (jboolean)(card->color[0] != '\0' ? JNI_TRUE : JNI_FALSE),
                                (jboolean)(card->disposable ? JNI_TRUE : JNI_FALSE),
                                (jboolean)(card->favorite ? JNI_TRUE : JNI_FALSE));

    (*env)->DeleteLocalRef(env, label);
    (*env)->DeleteLocalRef(env, code);
    (*env)->DeleteLocalRef(env, color);
    return oggetto;
}

static jobjectArray lista_a_java(JNIEnv *env, const opencard_lista *lista)
{
    jclass classe = (*env)->FindClass(env, CLASSE_CARTA);
    jmethodID costruttore;
    jobjectArray array;
    size_t i;

    if (classe == NULL) {
        return NULL;
    }
    costruttore = (*env)->GetMethodID(env, classe, "<init>",
                                      "(ILjava/lang/String;Ljava/lang/String;ZLjava/lang/String;ZZZ)V");
    if (costruttore == NULL) {
        return NULL;
    }
    array = (*env)->NewObjectArray(env, (jsize)lista->n, classe, NULL);
    if (array == NULL) {
        return NULL;
    }
    for (i = 0; i < lista->n; i++) {
        jobject oggetto = carta_a_java(env, classe, costruttore, &lista->carte[i]);
        if (oggetto == NULL) {
            return NULL;
        }
        (*env)->SetObjectArrayElement(env, array, (jsize)i, oggetto);
        (*env)->DeleteLocalRef(env, oggetto);
    }
    return array;
}

JNIEXPORT void JNICALL
Java_srl_denovo_opencard_Core_storeInit(JNIEnv *env, jclass classe, jstring directory)
{
    char percorso[1024];
    opencard_errore errore = {OPENCARD_OK, 0, {0}, 0};

    (void)classe;
    if (!stringa(env, directory, percorso, sizeof(percorso))) {
        return;
    }
    if (opencard_store_init(percorso) != OPENCARD_OK) {
        errore.codice = OPENCARD_ERR_ARGOMENTI;
        lancia(env, &errore);
        return;
    }
    if (opencard_init_db() != OPENCARD_OK) {
        errore.codice = OPENCARD_ERR_IO;
        lancia(env, &errore);
    }
}

JNIEXPORT jboolean JNICALL
Java_srl_denovo_opencard_Core_isFirstRun(JNIEnv *env, jclass classe)
{
    (void)env; (void)classe;
    return opencard_is_first_run() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_srl_denovo_opencard_Core_markFirstRunDone(JNIEnv *env, jclass classe)
{
    (void)env; (void)classe;
    opencard_mark_first_run_done();
}

JNIEXPORT jobjectArray JNICALL
Java_srl_denovo_opencard_Core_getGruppo(JNIEnv *env, jclass classe, jboolean disposable)
{
    opencard_lista lista;
    opencard_errore errore;
    jobjectArray risultato;

    (void)classe;
    if (opencard_get_gruppo(disposable == JNI_TRUE ? 1 : 0, &lista, &errore) != OPENCARD_OK) {
        lancia(env, &errore);
        return NULL;
    }
    risultato = lista_a_java(env, &lista);
    opencard_lista_free(&lista);
    return risultato;
}

JNIEXPORT jobjectArray JNICALL
Java_srl_denovo_opencard_Core_getAll(JNIEnv *env, jclass classe)
{
    opencard_lista lista;
    opencard_errore errore;
    jobjectArray risultato;

    (void)classe;
    if (opencard_get_all(&lista, &errore) != OPENCARD_OK) {
        lancia(env, &errore);
        return NULL;
    }
    risultato = lista_a_java(env, &lista);
    opencard_lista_free(&lista);
    return risultato;
}

JNIEXPORT jobject JNICALL
Java_srl_denovo_opencard_Core_get(JNIEnv *env, jclass classe, jint id)
{
    opencard_card card;
    opencard_errore errore;
    jclass classe_carta;
    jmethodID costruttore;

    (void)classe;
    if (opencard_get((int)id, &card, &errore) != OPENCARD_OK) {
        lancia(env, &errore);
        return NULL;
    }
    classe_carta = (*env)->FindClass(env, CLASSE_CARTA);
    if (classe_carta == NULL) {
        return NULL;
    }
    costruttore = (*env)->GetMethodID(env, classe_carta, "<init>",
                                      "(ILjava/lang/String;Ljava/lang/String;ZLjava/lang/String;ZZZ)V");
    if (costruttore == NULL) {
        return NULL;
    }
    return carta_a_java(env, classe_carta, costruttore, &card);
}

JNIEXPORT jint JNICALL
Java_srl_denovo_opencard_Core_nextId(JNIEnv *env, jclass classe)
{
    (void)env; (void)classe;
    return (jint)opencard_next_id();
}

JNIEXPORT jint JNICALL
Java_srl_denovo_opencard_Core_insert(JNIEnv *env, jclass classe, jstring label,
                                     jstring code, jboolean isQrcode, jstring color,
                                     jboolean disposable)
{
    char buffer_label[OPENCARD_LABEL_MAX];
    char buffer_code[OPENCARD_CODE_MAX];
    char buffer_color[OPENCARD_COLOR_MAX];
    opencard_errore errore;
    int nuovo_id = 0;

    (void)classe;
    if (!stringa(env, label, buffer_label, sizeof(buffer_label)) ||
        !stringa(env, code, buffer_code, sizeof(buffer_code)) ||
        !stringa(env, color, buffer_color, sizeof(buffer_color))) {
        return 0;
    }
    if (opencard_insert(buffer_label, buffer_code, isQrcode == JNI_TRUE,
                        buffer_color, disposable == JNI_TRUE, &nuovo_id, &errore)
        != OPENCARD_OK) {
        lancia(env, &errore);
        return 0;
    }
    return (jint)nuovo_id;
}

JNIEXPORT void JNICALL
Java_srl_denovo_opencard_Core_update(JNIEnv *env, jclass classe, jint id, jstring label,
                                     jstring code, jboolean isQrcode, jstring color,
                                     jboolean disposable)
{
    char buffer_label[OPENCARD_LABEL_MAX];
    char buffer_code[OPENCARD_CODE_MAX];
    char buffer_color[OPENCARD_COLOR_MAX];
    opencard_errore errore;

    (void)classe;
    if (!stringa(env, label, buffer_label, sizeof(buffer_label)) ||
        !stringa(env, code, buffer_code, sizeof(buffer_code)) ||
        !stringa(env, color, buffer_color, sizeof(buffer_color))) {
        return;
    }
    if (opencard_update((int)id, buffer_label, buffer_code, isQrcode == JNI_TRUE,
                        buffer_color, disposable == JNI_TRUE, &errore) != OPENCARD_OK) {
        lancia(env, &errore);
    }
}

JNIEXPORT void JNICALL
Java_srl_denovo_opencard_Core_delete(JNIEnv *env, jclass classe, jint id)
{
    opencard_errore errore;

    (void)classe;
    if (opencard_delete((int)id, &errore) != OPENCARD_OK) {
        lancia(env, &errore);
    }
}

JNIEXPORT void JNICALL
Java_srl_denovo_opencard_Core_reorder(JNIEnv *env, jclass classe, jboolean disposable,
                                      jintArray ids)
{
    opencard_errore errore;
    jsize n;
    jint *elementi;
    int *copia;
    jsize i;

    (void)classe;
    if (ids == NULL) {
        return;
    }
    n = (*env)->GetArrayLength(env, ids);
    elementi = (*env)->GetIntArrayElements(env, ids, NULL);
    if (elementi == NULL) {
        return;
    }
    copia = (int *)malloc((size_t)(n > 0 ? n : 1) * sizeof(int));
    if (copia == NULL) {
        (*env)->ReleaseIntArrayElements(env, ids, elementi, JNI_ABORT);
        return;
    }
    for (i = 0; i < n; i++) {
        copia[i] = (int)elementi[i];
    }
    (*env)->ReleaseIntArrayElements(env, ids, elementi, JNI_ABORT);

    if (opencard_reorder(disposable == JNI_TRUE ? 1 : 0, copia, (size_t)n, &errore)
        != OPENCARD_OK) {
        lancia(env, &errore);
    }
    free(copia);
}

JNIEXPORT jstring JNICALL
Java_srl_denovo_opencard_Core_colorForId(JNIEnv *env, jclass classe, jint id)
{
    char colore[OPENCARD_COLOR_MAX];

    (void)classe;
    opencard_color_for_id((int)id, colore, sizeof(colore));
    return (*env)->NewStringUTF(env, colore);
}

JNIEXPORT jstring JNICALL
Java_srl_denovo_opencard_Core_groupedCode(JNIEnv *env, jclass classe, jstring code)
{
    char ingresso[OPENCARD_CODE_MAX];
    char uscita[OPENCARD_CODE_MAX * 2];

    (void)classe;
    if (!stringa(env, code, ingresso, sizeof(ingresso))) {
        return NULL;
    }
    if (opencard_grouped_code(ingresso, uscita, sizeof(uscita)) < 0) {
        return stringa_verso_java(env, ingresso);
    }
    return stringa_verso_java(env, uscita);
}

JNIEXPORT jobject JNICALL
Java_srl_denovo_opencard_Core_renderCode(JNIEnv *env, jclass classe, jstring code,
                                         jboolean isQrcode)
{
    const char *ingresso;
    char *testo;
    unsigned char *pixel = NULL;
    char messaggio[128];
    int larghezza = 0, altezza = 0;
    int esito;
    jclass classe_immagine;
    jmethodID costruttore;
    jintArray colori;
    jint *buffer;
    long totale, i;

    (void)classe;
    /* Il testo si prende com'è, senza copiarlo in un buffer di lunghezza
     * fissa: i QR del passaggio fra due telefoni arrivano a 1425 caratteri,
     * quasi tre volte OPENCARD_CODE_MAX, e tagliarli qui darebbe un QR che chi
     * riceve scarta in silenzio. Il codice di una tessera resta corto lo
     * stesso, il limite lo mette già il form. La copia serve per riparare il
     * modified UTF-8 di Java: senza, un QR con un'emoji nel testo verrebbe
     * disegnato con byte che nessun altro lettore riconosce. */
    if (code == NULL) {
        return NULL;
    }
    ingresso = (*env)->GetStringUTFChars(env, code, NULL);
    if (ingresso == NULL) {
        return NULL;
    }
    testo = strdup(ingresso);
    (*env)->ReleaseStringUTFChars(env, code, ingresso);
    if (testo == NULL) {
        lancia_memoria(env);
        return NULL;
    }
    opencard_utf8_ripara(testo);
    esito = opencard_render_bitmap(testo,
                                   isQrcode == JNI_TRUE ? OPENCARD_QRCODE : OPENCARD_BARCODE,
                                   &pixel, &larghezza, &altezza, messaggio, sizeof(messaggio));
    free(testo);
    if (esito != 0) {
        jclass eccezione = (*env)->FindClass(env, CLASSE_ECCEZIONE);
        if (eccezione != NULL) {
            (*env)->ThrowNew(env, eccezione,
                             messaggio[0] != '\0' ? messaggio : "Codice non generabile.");
        }
        return NULL;
    }

    totale = (long)larghezza * (long)altezza;
    colori = (*env)->NewIntArray(env, (jsize)totale);
    if (colori == NULL) {
        opencard_free_bitmap(pixel);
        return NULL;
    }
    buffer = (jint *)malloc((size_t)totale * sizeof(jint));
    if (buffer == NULL) {
        opencard_free_bitmap(pixel);
        /* Kotlin dichiara il ritorno non nullo: un NULL senza eccezione
         * diventerebbe un crash senza spiegazione alla prima lettura. */
        lancia_memoria(env);
        return NULL;
    }
    /* Da RGB a ARGB, che è il formato che si aspetta Bitmap. */
    for (i = 0; i < totale; i++) {
        unsigned char r = pixel[i * 3];
        unsigned char g = pixel[i * 3 + 1];
        unsigned char b = pixel[i * 3 + 2];
        buffer[i] = (jint)(0xFF000000u | ((unsigned)r << 16) | ((unsigned)g << 8) | b);
    }
    (*env)->SetIntArrayRegion(env, colori, 0, (jsize)totale, buffer);
    free(buffer);
    opencard_free_bitmap(pixel);

    classe_immagine = (*env)->FindClass(env, CLASSE_IMMAGINE);
    if (classe_immagine == NULL) {
        return NULL;
    }
    costruttore = (*env)->GetMethodID(env, classe_immagine, "<init>", "(II[I)V");
    if (costruttore == NULL) {
        return NULL;
    }
    return (*env)->NewObject(env, classe_immagine, costruttore,
                             (jint)larghezza, (jint)altezza, colori);
}

JNIEXPORT jstring JNICALL
Java_srl_denovo_opencard_Core_backupEsporta(JNIEnv *env, jclass classe, jstring quando)
{
    char istante[64];
    char *testo = NULL;
    opencard_errore errore;
    jstring risultato;

    (void)classe;
    if (!stringa(env, quando, istante, sizeof(istante))) {
        return NULL;
    }
    if (opencard_backup_esporta(istante, &testo, &errore) != OPENCARD_OK || testo == NULL) {
        lancia(env, &errore);
        return NULL;
    }
    /* Il JSON porta i nomi delle carte: stessa strada UTF-16 delle carte. */
    risultato = stringa_verso_java(env, testo);
    opencard_backup_free(testo);
    return risultato;
}

JNIEXPORT jstring JNICALL
Java_srl_denovo_opencard_Core_backupNome(JNIEnv *env, jclass classe, jstring oggi)
{
    char data[16];
    char nome[64];

    (void)classe;
    if (!stringa(env, oggi, data, sizeof(data))) {
        return NULL;
    }
    opencard_backup_nome(data, nome, sizeof(nome));
    return (*env)->NewStringUTF(env, nome);
}

/* Legge un backup e lo applica. Le due cose stanno insieme perché fra la
 * lettura e la scrittura non c'è niente da decidere: se il file è valido si
 * ripristina, altrimenti si è già alzata l'eccezione col motivo. */
JNIEXPORT jint JNICALL
Java_srl_denovo_opencard_Core_backupRipristina(JNIEnv *env, jclass classe, jbyteArray dati)
{
    opencard_lista lista;
    opencard_errore errore;
    jsize lunghezza;
    jbyte *byte;
    char *testo;
    jint quante;

    (void)classe;
    if (dati == NULL) {
        return 0;
    }
    lunghezza = (*env)->GetArrayLength(env, dati);
    byte = (*env)->GetByteArrayElements(env, dati, NULL);
    if (byte == NULL) {
        return 0;
    }
    testo = (char *)malloc((size_t)lunghezza + 1);
    if (testo == NULL) {
        (*env)->ReleaseByteArrayElements(env, dati, byte, JNI_ABORT);
        return 0;
    }
    memcpy(testo, byte, (size_t)lunghezza);
    testo[lunghezza] = '\0';
    (*env)->ReleaseByteArrayElements(env, dati, byte, JNI_ABORT);

    if (opencard_backup_leggi(testo, (size_t)lunghezza, &lista, &errore) != OPENCARD_OK) {
        free(testo);
        lancia(env, &errore);
        return 0;
    }
    free(testo);

    if (opencard_replace_all(&lista, &errore) != OPENCARD_OK) {
        opencard_lista_free(&lista);
        lancia(env, &errore);
        return 0;
    }
    quante = (jint)lista.n;
    opencard_lista_free(&lista);
    return quante;
}

/* -------------------------------- passaggio delle carte con i QR --------- */

/* I testi dei QR letti, da Java a C. Chi chiama libera con pezzi_free(). */
static const char **pezzi_da_java(JNIEnv *env, jobjectArray array, size_t *quanti)
{
    const char **pezzi;
    jsize n, i;

    *quanti = 0;
    if (array == NULL) {
        return NULL;
    }
    n = (*env)->GetArrayLength(env, array);
    pezzi = (const char **)calloc((size_t)n > 0 ? (size_t)n : 1, sizeof(char *));
    if (pezzi == NULL) {
        return NULL;
    }
    for (i = 0; i < n; i++) {
        jstring elemento = (jstring)(*env)->GetObjectArrayElement(env, array, i);
        const char *utf;

        if (elemento == NULL) {
            continue;
        }
        utf = (*env)->GetStringUTFChars(env, elemento, NULL);
        if (utf != NULL) {
            pezzi[i] = strdup(utf);
            (*env)->ReleaseStringUTFChars(env, elemento, utf);
        }
        (*env)->DeleteLocalRef(env, elemento);
    }
    *quanti = (size_t)n;
    return pezzi;
}

static void pezzi_free(const char **pezzi, size_t quanti)
{
    size_t i;

    if (pezzi == NULL) {
        return;
    }
    for (i = 0; i < quanti; i++) {
        free((void *)pezzi[i]);
    }
    free((void *)pezzi);
}

JNIEXPORT jobjectArray JNICALL
Java_srl_denovo_opencard_Core_trasfPrepara(JNIEnv *env, jclass classe)
{
    opencard_trasf_pezzi pezzi;
    opencard_errore errore;
    jobjectArray array;
    jclass classe_stringa;
    size_t i;

    (void)classe;
    if (opencard_trasf_prepara(&pezzi, &errore) != OPENCARD_OK) {
        lancia(env, &errore);
        return NULL;
    }
    classe_stringa = (*env)->FindClass(env, "java/lang/String");
    if (classe_stringa == NULL) {
        opencard_trasf_pezzi_free(&pezzi);
        return NULL;
    }
    array = (*env)->NewObjectArray(env, (jsize)pezzi.n, classe_stringa, NULL);
    if (array == NULL) {
        opencard_trasf_pezzi_free(&pezzi);
        return NULL;
    }
    for (i = 0; i < pezzi.n; i++) {
        jstring testo = (*env)->NewStringUTF(env, pezzi.pezzi[i]);
        (*env)->SetObjectArrayElement(env, array, (jsize)i, testo);
        (*env)->DeleteLocalRef(env, testo);
    }
    opencard_trasf_pezzi_free(&pezzi);
    return array;
}

/* Quanti pezzi sono arrivati e quanti ne servono: {ricevuti, totale}.
 * Totale a 0 vuol dire che fra i codici letti non ce n'è ancora uno di
 * OpenCard, che non è un errore: la fotocamera inquadra di tutto. */
JNIEXPORT jintArray JNICALL
Java_srl_denovo_opencard_Core_trasfStato(JNIEnv *env, jclass classe, jobjectArray letti)
{
    const char **pezzi;
    size_t quanti;
    opencard_errore errore;
    int ricevuti = 0, totale = 0;
    jint valori[2];
    jintArray esito;

    (void)classe;
    pezzi = pezzi_da_java(env, letti, &quanti);
    if (opencard_trasf_stato(pezzi, quanti, &ricevuti, &totale, &errore) != OPENCARD_OK) {
        pezzi_free(pezzi, quanti);
        lancia(env, &errore);
        return NULL;
    }
    pezzi_free(pezzi, quanti);

    valori[0] = (jint)ricevuti;
    valori[1] = (jint)totale;
    esito = (*env)->NewIntArray(env, 2);
    if (esito != NULL) {
        (*env)->SetIntArrayRegion(env, esito, 0, 2, valori);
    }
    return esito;
}

JNIEXPORT jobjectArray JNICALL
Java_srl_denovo_opencard_Core_trasfLeggi(JNIEnv *env, jclass classe, jobjectArray letti)
{
    const char **pezzi;
    size_t quanti;
    opencard_lista lista;
    opencard_errore errore;
    jobjectArray array;

    (void)classe;
    pezzi = pezzi_da_java(env, letti, &quanti);
    if (opencard_trasf_leggi(pezzi, quanti, &lista, &errore) != OPENCARD_OK) {
        pezzi_free(pezzi, quanti);
        lancia(env, &errore);
        return NULL;
    }
    pezzi_free(pezzi, quanti);

    array = lista_a_java(env, &lista);
    opencard_lista_free(&lista);
    return array;
}

/* Scrive le carte ricevute e restituisce quante ne ha scritte.
 * `azzera` acceso butta via quelle che c'erano. */
JNIEXPORT jint JNICALL
Java_srl_denovo_opencard_Core_trasfApplica(JNIEnv *env, jclass classe,
                                           jobjectArray letti, jboolean azzera)
{
    const char **pezzi;
    size_t quanti;
    opencard_errore errore;
    int quante = 0;

    (void)classe;
    pezzi = pezzi_da_java(env, letti, &quanti);
    if (opencard_trasf_applica(pezzi, quanti, azzera == JNI_TRUE ? 1 : 0,
                               &quante, &errore) != OPENCARD_OK) {
        pezzi_free(pezzi, quanti);
        lancia(env, &errore);
        return 0;
    }
    pezzi_free(pezzi, quanti);
    return (jint)quante;
}

/* ------------------------------------------------ carte preferite -------- */

JNIEXPORT jobjectArray JNICALL
Java_srl_denovo_opencard_Core_getPreferite(JNIEnv *env, jclass classe)
{
    opencard_lista lista;
    opencard_errore errore;
    jobjectArray array;

    (void)classe;
    if (opencard_get_preferite(&lista, &errore) != OPENCARD_OK) {
        lancia(env, &errore);
        return NULL;
    }
    array = lista_a_java(env, &lista);
    opencard_lista_free(&lista);
    return array;
}

JNIEXPORT void JNICALL
Java_srl_denovo_opencard_Core_setPreferita(JNIEnv *env, jclass classe, jint id,
                                           jboolean preferita)
{
    opencard_errore errore;

    (void)classe;
    if (opencard_set_favorite((int)id, preferita == JNI_TRUE ? 1 : 0, &errore) != OPENCARD_OK) {
        lancia(env, &errore);
    }
}
