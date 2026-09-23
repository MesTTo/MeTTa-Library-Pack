# Purpose: link lib_compression's private archive binding into a SWI-Prolog
#   that links foreign code statically, as the extension native_install/2
#   activates there.
# Assumes: included from the package tools/wasm-host/build.sh stages into
#   swipl-devel's packages/, after PrologPackage.cmake, and libarchive was built
#   and installed by this directory's CMakeLists.txt without NATIVE_STAGE, from
#   the same pinned source and ZIP correction the shared object links.
# Guarantees: plugin_lib_compression compiles archive_locale.c, which includes
#   the vendored binding, with -DLIBARCHIVE_STATIC as the native recipe does.
#   It links LibArchive_LIBRARIES when the configure line names them, which is
#   how a static libarchive brings the codec libraries it rests on, and
#   otherwise what find_package(LibArchive) finds; a build without libarchive
#   stops here rather than shipping a host whose lib_compression cannot read
#   an archive.
if(NOT (LibArchive_LIBRARIES AND LibArchive_INCLUDE_DIRS))
  find_package(LibArchive 3.0.0 REQUIRED)
endif()
swipl_plugin(
    lib_compression
    MODULE lib_compression
    C_SOURCES ${CMAKE_CURRENT_LIST_DIR}/archive_locale.c
    C_LIBS ${LibArchive_LIBRARIES})
target_compile_definitions(plugin_lib_compression PRIVATE LIBARCHIVE_STATIC)
