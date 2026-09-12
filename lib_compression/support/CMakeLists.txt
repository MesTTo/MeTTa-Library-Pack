# Purpose: compile the pinned archive provider and its private SWI binding.
# Owns resources: the calling native build recipe owns this temporary build tree.
# Decides: archive symbols stay local to the resulting SWI object.
# [tested: test_archive_legacy_zip_names; commit=7b42d5ee5cecb82709617b7ed08dfa2c1441f268].
cmake_minimum_required(VERSION 3.18)
project(metta_compression C)

set(vendor "${CMAKE_CURRENT_SOURCE_DIR}/../vendor")
set(snapshot "${vendor}/libarchive-3.8.5.tar.gz")
file(SHA256 "${snapshot}" archive_sha256)
if(NOT archive_sha256 STREQUAL "8b3e4d4ac48fe36d0ef45d01ab1f740a247b4383a4c7c1dfdd565cfa7107af66")
  message(FATAL_ERROR "libarchive source archive does not match its pinned SHA-256")
endif()
file(ARCHIVE_EXTRACT INPUT "${snapshot}" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}")
set(provider "${CMAKE_CURRENT_BINARY_DIR}/libarchive-dd897a78c662a2c7a003e7ec158cea7909557bee")
configure_file("${vendor}/archive_read_support_format_zip.c"
               "${provider}/libarchive/archive_read_support_format_zip.c" COPYONLY)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
foreach(feature TEST TAR CPIO CAT UNZIP INSTALL)
  set(ENABLE_${feature} OFF CACHE BOOL "" FORCE)
endforeach()
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_RULE_MESSAGES OFF CACHE BOOL "" FORCE)

# The host archive runtime can be installed without its LZ4 development headers.
# These matching public headers let CMake find the existing shared library.
find_path(LZ4_INCLUDE_DIR lz4.h)
if(NOT LZ4_INCLUDE_DIR)
  set(LZ4_INCLUDE_DIR "${vendor}/lz4" CACHE PATH "" FORCE)
endif()
find_library(LZ4_LIBRARY NAMES lz4 liblz4 liblz4.so.1)
add_subdirectory("${provider}" provider-build)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
  target_compile_options(archive_static PRIVATE
    -fvisibility=hidden -U__LIBARCHIVE_ENABLE_VISIBILITY)
endif()

# swipl-ld beside the active interpreter chooses the binding's SWI headers/ABI.
# CMake supplies the native provider's resolved transitive linker inputs.
get_target_property(dependencies archive_static LINK_LIBRARIES)
set(link_args)
foreach(dependency IN LISTS dependencies)
  if(TARGET "${dependency}")
    list(APPEND link_args "$<TARGET_LINKER_FILE:${dependency}>")
  elseif(IS_ABSOLUTE "${dependency}" AND dependency MATCHES "\\.so\\.[0-9]")
    get_filename_component(library_directory "${dependency}" DIRECTORY)
    get_filename_component(library_filename "${dependency}" NAME)
    list(APPEND link_args "-L${library_directory}" "-l:${library_filename}")
  elseif(IS_ABSOLUTE "${dependency}" OR dependency MATCHES "^-")
    list(APPEND link_args "${dependency}")
  elseif(NOT dependency MATCHES "-NOTFOUND$")
    list(APPEND link_args "-l${dependency}")
  endif()
endforeach()
add_custom_command(OUTPUT "${NATIVE_STAGE}"
  COMMAND "${SWIPL_LD}" -shared -O2 -DLIBARCHIVE_STATIC
          -o "${NATIVE_STAGE}" "${NATIVE_SOURCE}"
          "$<TARGET_FILE:archive_static>" ${link_args}
  DEPENDS archive_static "${NATIVE_SOURCE}"
  VERBATIM USES_TERMINAL)
add_custom_target(native_object DEPENDS "${NATIVE_STAGE}")
