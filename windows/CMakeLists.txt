# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "kinetic_player")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "kinetic_player_plugin")
set(KINETIC_NATIVE_MPV_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../native/mpv")
set(KINETIC_MPV_VENDOR_DIR "${CMAKE_CURRENT_SOURCE_DIR}/mpv/vendor")
set(KINETIC_MPV_MANIFEST "${CMAKE_CURRENT_SOURCE_DIR}/mpv/manifest.json")

file(MAKE_DIRECTORY "${KINETIC_MPV_VENDOR_DIR}")

set(KINETIC_MPV_DLL "${KINETIC_MPV_VENDOR_DIR}/libmpv-2.dll")
if(DEFINED ENV{KINETIC_PLAYER_LIBMPV_DLL} AND EXISTS "$ENV{KINETIC_PLAYER_LIBMPV_DLL}")
  set(KINETIC_MPV_DLL "$ENV{KINETIC_PLAYER_LIBMPV_DLL}")
endif()

if(NOT EXISTS "${KINETIC_MPV_DLL}")
  set(_mpv_url "$ENV{KINETIC_PLAYER_LIBMPV_URL}")
  if(NOT _mpv_url)
    set(_mpv_url "https://github.com/zhongfly/mpv-winbuild/releases/download/2026-10-15-a2cd83c56d/mpv-dev-lgpl-x86_64-20261015-git-a2cd83c56d.7z")
  endif()
  set(_mpv_archive "${CMAKE_CURRENT_BINARY_DIR}/libmpv-dev.7z")
  message(STATUS "kinetic_player: downloading libmpv from ${_mpv_url}")
  file(DOWNLOAD "${_mpv_url}" "${_mpv_archive}" SHOW_PROGRESS STATUS _dl_status)
  list(GET _dl_status 0 _dl_code)
  if(NOT _dl_code EQUAL 0)
    message(FATAL_ERROR
      "Failed to download libmpv. Place libmpv-2.dll in windows/mpv/vendor/ "
      "or set KINETIC_PLAYER_LIBMPV_DLL / KINETIC_PLAYER_LIBMPV_URL.")
  endif()
  if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.18")
    file(ARCHIVE_EXTRACT INPUT "${_mpv_archive}" DESTINATION "${KINETIC_MPV_VENDOR_DIR}")
  else()
    find_program(SEVENZ 7z 7za 7z.exe
      PATHS "C:/Program Files/7-Zip" "C:/Program Files (x86)/7-Zip")
    if(NOT SEVENZ)
      message(FATAL_ERROR "CMake < 3.18: install 7-Zip or extract libmpv into windows/mpv/vendor/")
    endif()
    execute_process(
      COMMAND "${SEVENZ}" x "${_mpv_archive}" -o"${KINETIC_MPV_VENDOR_DIR}" -y
      RESULT_VARIABLE _x_res)
    if(NOT _x_res EQUAL 0)
      message(FATAL_ERROR "Failed to extract libmpv archive")
    endif()
  endif()
  file(GLOB_RECURSE _found_dll "${KINETIC_MPV_VENDOR_DIR}/**/libmpv-2.dll")
  if(_found_dll)
    list(GET _found_dll 0 _src_dll)
    if(NOT _src_dll STREQUAL "${KINETIC_MPV_DLL}")
      file(COPY "${_src_dll}" DESTINATION "${KINETIC_MPV_VENDOR_DIR}")
    endif()
  endif()
endif()

if(NOT EXISTS "${KINETIC_MPV_DLL}")
  message(FATAL_ERROR
    "libmpv-2.dll not found. Put it at ${KINETIC_MPV_DLL} or set KINETIC_PLAYER_LIBMPV_DLL.")
endif()

set(KINETIC_MPV_IMPLIB "${CMAKE_CURRENT_BINARY_DIR}/mpv.lib")
find_program(MSVC_LIB lib HINTS
  ENV VCToolsInstallDir
  "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\VisualStudio\\SxS\\VS7]")
# lib.exe is on PATH in a VS developer environment (flutter build windows).
if(NOT MSVC_LIB)
  set(MSVC_LIB lib)
endif()
execute_process(
  COMMAND ${MSVC_LIB} /nologo
          /def:${CMAKE_CURRENT_SOURCE_DIR}/mpv/libmpv.def
          /machine:x64
          /out:${KINETIC_MPV_IMPLIB}
  RESULT_VARIABLE _lib_res
  OUTPUT_VARIABLE _lib_out
  ERROR_VARIABLE _lib_err)
if(NOT _lib_res EQUAL 0)
  message(WARNING "lib.exe could not create mpv.lib (${_lib_err}). Linking may fail.")
endif()

list(APPEND PLUGIN_SOURCES
  "kinetic_player_plugin.cpp"
  "${KINETIC_NATIVE_MPV_DIR}/mpv_player.cc"
  "${KINETIC_NATIVE_MPV_DIR}/png_encode.cc"
)

add_library(${PLUGIN_NAME} SHARED ${PLUGIN_SOURCES})
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  CXX_STANDARD 17)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${KINETIC_NATIVE_MPV_DIR}"
  "${KINETIC_NATIVE_MPV_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)
if(EXISTS "${KINETIC_MPV_IMPLIB}")
  target_link_libraries(${PLUGIN_NAME} PRIVATE "${KINETIC_MPV_IMPLIB}")
endif()

set(kinetic_player_bundled_libraries
  "${KINETIC_MPV_DLL}"
  PARENT_SCOPE
)
