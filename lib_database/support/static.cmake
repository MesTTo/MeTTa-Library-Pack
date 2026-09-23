# Purpose: link lib_database's stream-owned lock into a SWI-Prolog that links
#   foreign code statically, as the extension native_install/2 activates there.
# Assumes: included from the package tools/wasm-host/build.sh stages into
#   swipl-devel's packages/, after PrologPackage.cmake.
# Guarantees: plugin_lib_database compiles lock.c as native_build.pl hands it
#   to swipl-ld, with no flags.
swipl_plugin(
    lib_database
    MODULE lib_database
    C_SOURCES ${CMAKE_CURRENT_LIST_DIR}/lock.c)
