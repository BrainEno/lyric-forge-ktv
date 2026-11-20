cmake_minimum_required(VERSION 3.20)
project(lyricforge_separator LANGUAGES CXX)

# Two independent targets:
#   lfsep_tests          - CLI, WAV and protocol tests; needs nothing but a
#                          C++20 compiler (fake engine, no ONNX Runtime).
#   lyricforge-separator - the real tool; needs Eigen (EIGEN_DIR) and an
#                          ONNX Runtime package (ORT_INCLUDE_DIR, ORT_LIBRARY).
option(LFSEP_BUILD_TESTS "Build the self-contained unit tests" ON)
option(LFSEP_BUILD_CLI "Build lyricforge-separator (needs Eigen and ORT)" OFF)
option(LFSEP_WITH_DIRECTML "Enable the DirectML execution provider" OFF)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
  add_compile_options(/W3 /EHsc /utf-8 /bigobj /permissive- /O2)
  add_compile_definitions(_CRT_SECURE_NO_WARNINGS NOMINMAX)
else()
  add_compile_options(-Wall -Wextra -O2)
endif()

set(LFSEP_CORE_SOURCES
  src/app.cpp
  src/cli_options.cpp
  src/report.cpp
  src/wav_io.cpp
)

add_library(lfsep_core STATIC ${LFSEP_CORE_SOURCES})
target_include_directories(lfsep_core PUBLIC src)

if(LFSEP_BUILD_TESTS)
  enable_testing()
  add_executable(lfsep_tests tests/separator_tests.cpp)
  target_link_libraries(lfsep_tests PRIVATE lfsep_core)
  add_test(NAME lfsep_tests COMMAND lfsep_tests)
endif()

if(LFSEP_BUILD_CLI)
  set(DEMUCS_ONNX_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/demucs_onnx/src")
  if(NOT EIGEN_DIR)
    message(FATAL_ERROR "Set EIGEN_DIR to an Eigen 3.4 source tree")
  endif()
  if(NOT ORT_INCLUDE_DIR OR NOT ORT_LIBRARY)
    message(FATAL_ERROR "Set ORT_INCLUDE_DIR and ORT_LIBRARY")
  endif()

  add_executable(lyricforge-separator
    src/main.cpp
    src/engine_demucs_onnx.cpp
    ${DEMUCS_ONNX_DIR}/dsp.cpp
    ${DEMUCS_ONNX_DIR}/model_apply.cpp
    ${DEMUCS_ONNX_DIR}/model_inference.cpp
  )
  target_include_directories(lyricforge-separator PRIVATE
    src
    ${DEMUCS_ONNX_DIR}
    ${EIGEN_DIR}
    ${ORT_INCLUDE_DIR}
  )
  if(DIRECTML_INCLUDE_DIR)
    target_include_directories(lyricforge-separator PRIVATE ${DIRECTML_INCLUDE_DIR})
  endif()
  target_link_libraries(lyricforge-separator PRIVATE lfsep_core ${ORT_LIBRARY})
  if(LFSEP_WITH_DIRECTML)
    target_compile_definitions(lyricforge-separator PRIVATE LFSEP_WITH_DIRECTML)
  endif()
  # Eigen's Tensor module and the vendored core are third-party code.
  if(MSVC)
    set_source_files_properties(
      ${DEMUCS_ONNX_DIR}/dsp.cpp
      ${DEMUCS_ONNX_DIR}/model_apply.cpp
      ${DEMUCS_ONNX_DIR}/model_inference.cpp
      PROPERTIES COMPILE_OPTIONS "/W1")
  else()
    set_source_files_properties(
      ${DEMUCS_ONNX_DIR}/dsp.cpp
      ${DEMUCS_ONNX_DIR}/model_apply.cpp
      ${DEMUCS_ONNX_DIR}/model_inference.cpp
      PROPERTIES COMPILE_OPTIONS "-w")
    # Find libonnxruntime next to the executable when bundled.
    set_target_properties(lyricforge-separator PROPERTIES
      BUILD_RPATH "$ORIGIN" INSTALL_RPATH "$ORIGIN")
  endif()
endif()
