plugins {
    // Da AGP 9 il Kotlin lo compila il plugin Android: il plugin
    // org.jetbrains.kotlin.android non si applica più.
    id("com.android.application") version "9.3.0" apply false
}
