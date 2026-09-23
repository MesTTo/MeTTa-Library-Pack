# Purpose: link lib_regex's private PCRE2 binding into a SWI-Prolog that links
#   foreign code statically, as the extension native_install/2 activates there.
# Assumes: included from the package tools/wasm-host/build.sh stages into
#   swipl-devel's packages/, after PrologPackage.cmake, with PCRE2 under the
#   build's find root, which is where SWI's own pcre package finds it.
# Guarantees: plugin_metta_pcre links the binding against the pcre2-8 library
#   native_build.pl hands swipl-ld (-lpcre2-8), found the way
#   packages/pcre/cmake/FindPCRE.cmake finds it; a build without PCRE2 stops
#   here rather than shipping a host whose lib_regex has no native half.
find_path(METTA_PCRE2_INCLUDE_DIR NAMES pcre2.h REQUIRED)
find_library(METTA_PCRE2_LIBRARY NAMES pcre2-8 REQUIRED)
swipl_plugin(
    metta_pcre
    MODULE metta_pcre
    C_SOURCES ${CMAKE_CURRENT_LIST_DIR}/../vendor/pcre4pl.c
    C_LIBS ${METTA_PCRE2_LIBRARY})
target_include_directories(
    plugin_metta_pcre BEFORE PRIVATE
    ${METTA_PCRE2_INCLUDE_DIR})
