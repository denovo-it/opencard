import java.util.Properties

plugins {
    id("com.android.application")
}

// Firma di release: se il file delle proprieta' non c'e' si compila comunque,
// firmato debug. Il file non sta nel repository.
//
// Due chiavi, e non e' un capriccio: l'APK che va sul sito continua a essere
// firmato con la chiave della beta, altrimenti chi ce l'ha non puo' aggiornare;
// il bundle per Play vuole una chiave vera, perche' Play rifiuta i certificati
// di debug. Si sceglie con -PkeystoreProps=keystore-upload.properties.
val keystoreProps = Properties().apply {
    val nome = (project.findProperty("keystoreProps") as String?) ?: "keystore.properties"
    val f = rootProject.file(nome)
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "srl.denovo.opencard"
    compileSdk = 36

    // Fissato: AGP 9 sceglierebbe da se' il suo predefinito, e un NDK diverso
    // da quello provato qui vuol dire ricompilare zint e il core al buio.
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "srl.denovo.opencard"
        minSdk = 24
        targetSdk = 36

        // Formato YYYYMMDDnn: nn e' il progressivo della giornata. Deve solo
        // crescere, e a colpo d'occhio dice quando e' stata costruita.
        versionCode = 2026082102
        versionName = "1.0.1"

        // Niente split per ABI: senza runtime da trascinarsi dietro l'APK e'
        // piccolo, e un file solo si distribuisce meglio.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }

        externalNativeBuild {
            cmake {
                arguments += "-DANDROID_STL=none"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        if (keystoreProps.isNotEmpty()) {
            create("release") {
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (keystoreProps.isNotEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

}

// Il changelog viaggia dentro l'app e la schermata informazioni lo mostra. Si
// copia dalla radice a ogni build invece di tenerne una copia a mano nelle
// assets: la copia a mano resta indietro e l'app racconta le note della
// versione precedente senza che il build dica niente. Su iOS lo fanno gia' i
// suoi script.
//
// Da AGP 9 una cartella generata non si aggancia piu' con
// sourceSets["main"].assets.srcDir(...): l'API delle sorgenti rifiuta i
// Provider, perche' da fuori non si distingue una cartella generata da una
// scritta a mano. Si passa dalla Variant API, che oltre a funzionare porta con
// se' la dipendenza dal task senza doverla appendere a preBuild.
abstract class CopiaChangelog : DefaultTask() {
    @get:InputFile
    abstract val sorgente: RegularFileProperty

    @get:OutputDirectory
    abstract val destinazione: DirectoryProperty

    @TaskAction
    fun esegui() {
        val cartella = destinazione.get().asFile
        cartella.mkdirs()
        sorgente.get().asFile.copyTo(cartella.resolve("CHANGELOG.md"), overwrite = true)
    }
}

val copiaChangelog = tasks.register<CopiaChangelog>("copiaChangelog") {
    sorgente.set(file("../../../CHANGELOG.md"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(
            copiaChangelog,
            CopiaChangelog::destinazione,
        )
    }
}

// L'APK non si costruisce piu': dal 14 agosto 2026 si distribuisce solo dal Play
// Store, e l'artefatto e' il bundle. Un APK accanto al
// bundle serve solo a far caricare in console qualcosa di diverso da quello che
// e' stato provato. Chi lancia assembleRelease a mano se lo ritrova comunque,
// perche' e' un task di serie di AGP, ma non lo usa nessuno script.
dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    implementation("androidx.viewpager2:viewpager2:1.1.0")
    implementation("com.google.android.material:material:1.12.0")

    val camerax = "1.5.0"
    implementation("androidx.camera:camera-core:$camerax")
    implementation("androidx.camera:camera-camera2:$camerax")
    implementation("androidx.camera:camera-lifecycle:$camerax")
    implementation("androidx.camera:camera-view:$camerax")

    implementation("com.google.mlkit:barcode-scanning:17.3.0")
}
