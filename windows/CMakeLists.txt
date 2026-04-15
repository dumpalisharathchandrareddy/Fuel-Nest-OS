cmake_minimum_required(VERSION 3.14)
project(fuelos LANGUAGES CXX)

set(BINARY_NAME "fuelos")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/install")
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")

# Only the install-step results are published
set(CMAKE_INSTALL_DEFAULT_COMPONENT_NAME "app")

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build
add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle target, as it's
# far simpler.

# TODO: Investigate making a one-step install that codesigns, notarizes, and
# publishes the package to Mac App Store.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")

# Make the "install" step default, as it's required to run.
install(CODE "set(BUILD_BUNDLE_DIR \"${BUILD_BUNDLE_DIR}\")" COMPONENT app)
install(CODE [[
  file(TO_CMAKE_PATH "${BUILD_BUNDLE_DIR}" _build_bundle_dir)
  set(_suffix "")
  set(_suffix "${_suffix}")
  execute_process(
    COMMAND ${CMAKE_COMMAND} --install ${CMAKE_BINARY_DIR} --prefix ${_build_bundle_dir} --component app
  )
]] COMPONENT app)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT app)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT app)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT app)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT app)
endif()

install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/flutter/ephemeral/cpp_client_wrapper/"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/flutter_assets"
  COMPONENT app
  FILES_MATCHING PATTERN "*.dat" PATTERN "*.bin")
