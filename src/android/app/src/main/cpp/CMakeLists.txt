cmake_minimum_required(VERSION 3.22)
project(opencardcore C)

# Il core sta cinque livelli sopra: è comune alle due piattaforme e non
# appartiene al progetto Android.
set(CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../..")
set(ZINT_DIR "${CORE_DIR}/third-party/zint")

if(NOT EXISTS "${ZINT_DIR}/backend")
    message(FATAL_ERROR
        "Manca zint in ${ZINT_DIR}: serve zint 2.13.0, "
        "git clone --depth 1 --branch 2.13.0 https://github.com/zint/zint.git")
endif()

# zint compilato dentro il progetto, senza libpng: nell'NDK non c'è, e il core
# restituisce il bitmap in memoria invece di scrivere un file.
file(GLOB ZINT_SORGENTI "${ZINT_DIR}/backend/*.c")
list(FILTER ZINT_SORGENTI EXCLUDE REGEX "png\\.c$")

add_library(opencardcore SHARED
    jni_bridge.c
    "${CORE_DIR}/codegen.c"
    "${CORE_DIR}/store.c"
    "${CORE_DIR}/backup.c"
    "${CORE_DIR}/transfer.c"
    "${CORE_DIR}/third-party/cJSON.c"
    ${ZINT_SORGENTI}
)

target_include_directories(opencardcore PRIVATE
    "${CORE_DIR}"
    "${ZINT_DIR}/backend"
)

target_compile_definitions(opencardcore PRIVATE ZINT_NO_PNG=1)

set_target_properties(opencardcore PROPERTIES C_STANDARD 99)

# Pagine di memoria da 16 KB. L'NDK r27 allinea i segmenti a 4 KB, e Google Play
# rifiuta le app che puntano ad Android 15 o superiore con codice a 64 bit
# allineato così. Dalla r28 è il comportamento predefinito e questa riga non
# fa danno. Si verifica dentro l'APK, non nei sorgenti:
#   readelf -lW lib/arm64-v8a/libopencardcore.so | awk '/LOAD/{print $NF}'
target_link_options(opencardcore PRIVATE "-Wl,-z,max-page-size=16384")

# zlib sta nell'NDK: la usa il passaggio delle carte con i QR, che senza
# compressione ci starebbe cinque volte più stretto.
target_link_libraries(opencardcore m z)
