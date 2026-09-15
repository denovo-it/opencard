import java.util.Properties

plugins {
    id("com.android.application")
}

// Firma di release: la stessa chiave di caricamento del telefono, scelta con
// -PkeystoreProps=keystore-upload.properties come fa bundle-play.sh --wear.
// Senza il file si compila comunque, firmato debug: basta per l'orologio
// collegato con adb.
val keystoreProps = Properties().apply {
    val nome = (project.findProperty("keystoreProps") as String?) ?: "keystore.properties"
    val f = rootProject.file(nome)
    if (f.exists()) f.inputStream().use { load(it) }
}

// L'app per l'orologio, Wear OS. Stesso applicationId e, quando andrà su
// Play, stessa chiave del telefono: è la stessa scheda con due artefatti.
// Fa una cosa sola, mostra il codice della carta scelta; le carte gliele
// manda il telefono (Orologio.kt nel modulo app, DalTelefono.kt qui).
android {
    namespace = "srl.denovo.opencard"
    compileSdk = 36

    // Lo stesso NDK del telefono, per lo stesso motivo: la .so è la stessa.
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "srl.denovo.opencard"
        // Wear OS 3, cioè Galaxy Watch4 e Pixel Watch in poi. Gli orologi
        // fermi a Wear OS 2 non ricevono più app dal 2024.
        minSdk = 30
        targetSdk = 36

        // Stesso formato del telefono, YYYYMMDDnn, ma il progressivo parte da
        // 51: Play vuole un versionCode diverso per ogni APK della stessa
        // scheda, e così i due non si pestano mai nella stessa giornata.
        versionCode = 2026091554
        versionName = "1.0.4"

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }

        externalNativeBuild {
            cmake {
                arguments += "-DANDROID_STL=none"
            }
        }
    }

    // Lo stesso core, lo stesso ponte, lo stesso CMake del telefono: si
    // compila una seconda volta, per questo APK.
    externalNativeBuild {
        cmake {
            path = file("../app/src/main/cpp/CMakeLists.txt")
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

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        fatal += "NewApi"
        disable += "HighAppVersionCode"
    }

    // Il ponte con il core, la chiave del file e i nomi dei messaggi: gli
    // stessi file del telefono, vedi app/build.gradle.kts.
    sourceSets.getByName("main") {
        kotlin.srcDir("../condiviso/java")
    }
}

// Le stringhe escono da src/lingue/genera.py anche qui: le chiavi con il
// suffisso _wear finiscono solo in questo modulo. Il controllo è lo stesso
// del telefono.
val controllaLingue = tasks.register<Exec>("controllaLingue") {
    workingDir = file("../../..")
    commandLine("python3", "src/lingue/genera.py", "--controlla")
    inputs.dir("../../../src/lingue").withPropertyName("lingue")
    inputs.dir("src/main/res").withPropertyName("risorse")
}

tasks.named("preBuild") {
    dependsOn(controllaLingue)
}

dependencies {
    // L'elenco curvo e la cornice che tiene il testo dentro il cerchio.
    implementation("androidx.wear:wear:1.3.0")
    // I messaggi dal telefono.
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
}
