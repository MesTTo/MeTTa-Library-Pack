# Purpose: link lib_string's native half into a SWI-Prolog that links foreign
#   code statically, as the extension native_install/2 activates on that host.
# Assumes: included from the package tools/wasm-host/build.sh stages into
#   swipl-devel's packages/, after PrologPackage.cmake, in a project with CXX.
# Guarantees: plugin_lib_string compiles string_native.cpp with the flags
#   native_build.pl hands swipl-ld (-std=c++11 and the vendor headers) and with
#   C++ exceptions caught. The adapter turns every PL_* failure into a thrown
#   Pending, and emscripten keeps catching disabled unless both the compile and
#   the link ask for it, so without -fexceptions a type error would abort the
#   instance [source: lib/lib_string/support/string_native.cpp:boundary].
#   Every program that links libswipl links with -fexceptions for that reason.
swipl_plugin(
    lib_string
    MODULE lib_string
    C_SOURCES ${CMAKE_CURRENT_LIST_DIR}/string_native.cpp)
target_include_directories(
    plugin_lib_string BEFORE PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}/../vendor)
target_compile_options(plugin_lib_string PRIVATE -std=c++11 -fexceptions)
target_link_options(libswipl INTERFACE -fexceptions)
