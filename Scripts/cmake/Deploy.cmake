#  ==============================================================================
#
#  This file is part of the iPlug 2 library. Copyright (C) the iPlug 2 developers.
#
#  See LICENSE.txt for more info.
#
#  ==============================================================================

# Plugin deployment configuration for iPlug2
# Supports symlink and copy deployment to standard system directories

#------------------------------------------------------------------------
# Options
#------------------------------------------------------------------------
option(IPLUG_DEPLOY_PLUGINS "Deploy built plugins to system directories" ON)

set(IPLUG_DEPLOY_METHOD "COPY" CACHE STRING "Deployment method: SYMLINK or COPY")
set_property(CACHE IPLUG_DEPLOY_METHOD PROPERTY STRINGS "SYMLINK" "COPY")

# User-overridable paths (empty = use platform default)
set(IPLUG_VST2_DEPLOY_PATH "" CACHE PATH "Override default VST2 deployment path")
set(IPLUG_VST3_DEPLOY_PATH "" CACHE PATH "Override default VST3 deployment path")
set(IPLUG_CLAP_DEPLOY_PATH "" CACHE PATH "Override default CLAP deployment path")
set(IPLUG_AU_DEPLOY_PATH "" CACHE PATH "Override default AU deployment path")
set(IPLUG_AAX_DEPLOY_PATH "" CACHE PATH "Override default AAX deployment path")
set(IPLUG_APP_DEPLOY_PATH "" CACHE PATH "Override default APP deployment path")
set(IPLUG_REAPEREXT_DEPLOY_PATH "" CACHE PATH "Override default REAPER extension deployment path")

#------------------------------------------------------------------------
# iplug_get_default_deploy_path
# Get the default deployment path for a plugin format
# Sets IPLUG_DEPLOY_PATH_${format} in parent scope
#
# @param format  Plugin format: VST2, VST3, CLAP, AU, AAX, APP, REAPEREXT
#------------------------------------------------------------------------
function(iplug_get_default_deploy_path format)
  # Check for user override first
  if(NOT "${IPLUG_${format}_DEPLOY_PATH}" STREQUAL "")
    set(IPLUG_DEPLOY_PATH_${format} "${IPLUG_${format}_DEPLOY_PATH}" PARENT_SCOPE)
    return()
  endif()

  if(APPLE)
    if(format STREQUAL "VST2")
      set(default_path "$ENV{HOME}/Library/Audio/Plug-Ins/VST")
    elseif(format STREQUAL "VST3")
      set(default_path "$ENV{HOME}/Library/Audio/Plug-Ins/VST3")
    elseif(format STREQUAL "CLAP")
      set(default_path "$ENV{HOME}/Library/Audio/Plug-Ins/CLAP")
    elseif(format STREQUAL "AU" OR format STREQUAL "AUv2")
      set(default_path "$ENV{HOME}/Library/Audio/Plug-Ins/Components")
    elseif(format STREQUAL "AAX")
      set(default_path "/Library/Application Support/Avid/Audio/Plug-Ins")
    elseif(format STREQUAL "APP")
      set(default_path "$ENV{HOME}/Applications")
    elseif(format STREQUAL "REAPEREXT")
      set(default_path "$ENV{HOME}/Library/Application Support/REAPER/UserPlugins")
    else()
      message(WARNING "[iPlug2] Unknown plugin format: ${format}")
      return()
    endif()
  elseif(WIN32)
    if(format STREQUAL "VST2")
      set(default_path "$ENV{PROGRAMFILES}/VstPlugins")
    elseif(format STREQUAL "VST3")
      set(default_path "$ENV{LOCALAPPDATA}/Programs/Common/VST3")
    elseif(format STREQUAL "CLAP")
      set(default_path "$ENV{LOCALAPPDATA}/Programs/Common/CLAP")
    elseif(format STREQUAL "AU" OR format STREQUAL "AUv2")
      # AU not supported on Windows
      return()
    elseif(format STREQUAL "AAX")
      set(default_path "$ENV{PROGRAMFILES}/Common Files/Avid/Audio/Plug-Ins")
    elseif(format STREQUAL "APP")
      # Leave APP in build directory on Windows
      set(default_path "")
    elseif(format STREQUAL "REAPEREXT")
      set(default_path "$ENV{APPDATA}/REAPER/UserPlugins")
    else()
      message(WARNING "[iPlug2] Unknown plugin format: ${format}")
      return()
    endif()
  elseif(UNIX AND NOT APPLE AND NOT EMSCRIPTEN)
    # Linux
    if(format STREQUAL "VST2")
      set(default_path "$ENV{HOME}/.vst")
    elseif(format STREQUAL "VST3")
      set(default_path "$ENV{HOME}/.vst3")
    elseif(format STREQUAL "CLAP")
      set(default_path "$ENV{HOME}/.clap")
    elseif(format STREQUAL "AU" OR format STREQUAL "AUv2")
      # AU not supported on Linux
      return()
    elseif(format STREQUAL "APP")
      # Leave APP in build directory on Linux
      set(default_path "")
    else()
      message(WARNING "[iPlug2] Unknown plugin format: ${format}")
      return()
    endif()
  endif()

  set(IPLUG_DEPLOY_PATH_${format} "${default_path}" PARENT_SCOPE)
endfunction()

#------------------------------------------------------------------------
# _iplug_create_plugin_link (internal)
# Create symlink from built plugin to destination
#
# @param target       The CMake target
# @param source_path  Full path to built plugin (or generator expression)
# @param dest_dir     Destination directory
# @param plugin_name  Name of the plugin file/bundle
#------------------------------------------------------------------------
function(_iplug_create_plugin_link target source_path dest_dir plugin_name)
  set(dest_path "${dest_dir}/${plugin_name}")

  if(WIN32)
    # Windows symlink handling
    # Note: Requires Developer Mode or admin privileges on Windows 10+
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E echo "[iPlug2] Creating symlink: ${dest_path}"
      COMMAND ${CMAKE_COMMAND} -E make_directory "${dest_dir}"
      COMMAND ${CMAKE_COMMAND} -E rm -rf "${dest_path}"
      COMMAND ${CMAKE_COMMAND} -E create_symlink "${source_path}" "${dest_path}"
      COMMENT "[iPlug2] Deploying ${plugin_name} (symlink)"
    )
  else()
    # macOS/Linux symlink using ln for better compatibility with bundles
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E echo "[iPlug2] Creating symlink: ${dest_path}"
      COMMAND ${CMAKE_COMMAND} -E make_directory "${dest_dir}"
      COMMAND rm -rf "${dest_path}"
      COMMAND ln -sfv "${source_path}" "${dest_path}"
      COMMENT "[iPlug2] Deploying ${plugin_name} (symlink)"
    )
  endif()
endfunction()

#------------------------------------------------------------------------
# _iplug_copy_plugin (internal)
# Copy built plugin to destination
#
# @param target       The CMake target
# @param source_path  Full path to built plugin (or generator expression)
# @param dest_dir     Destination directory
# @param plugin_name  Name of the plugin file/bundle
# @param is_bundle    TRUE if plugin is a directory/bundle, FALSE if single file
#------------------------------------------------------------------------
#------------------------------------------------------------------------
# _iplug_sign_bundle (internal, macOS only)
# Ad-hoc sign a deployed bundle so its Resources are sealed, then verify with
# the check the HOST makes rather than the one the signer makes about itself.
#------------------------------------------------------------------------
function(_iplug_sign_bundle target dest_path plugin_name)
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND codesign --force --sign - "${dest_path}"
    COMMAND codesign --verify --strict "${dest_path}"
    COMMENT "[iPlug2] Signing ${plugin_name} (ad-hoc, seals Resources)"
    VERBATIM
  )
endfunction()

function(_iplug_copy_plugin target source_path dest_dir plugin_name is_bundle)
  set(dest_path "${dest_dir}/${plugin_name}")

  if(is_bundle)
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E echo "[iPlug2] Copying plugin: ${dest_path}"
      COMMAND ${CMAKE_COMMAND} -E make_directory "${dest_dir}"
      COMMAND ${CMAKE_COMMAND} -E rm -rf "${dest_path}"
      COMMAND ${CMAKE_COMMAND} -E copy_directory "${source_path}" "${dest_path}"
      COMMENT "[iPlug2] Deploying ${plugin_name} (copy)"
    )

    # SEAL THE DEPLOYED BUNDLE'S RESOURCES (macOS only).
    #
    # The linker's ad-hoc signature carries no CodeResources, so any bundle with
    # a Contents/Resources folder fails SecStaticCodeCheckValidity with -67056,
    # "code has no resources but signature indicates they must be present".
    # Ableton Live's VST3 scanner calls exactly that API and logs the result as
    # "not a plugin" -- the plug-in is simply invisible, with no error the user
    # can see. AU and CLAP host paths do not validate, which is why this
    # presents as "works everywhere except Live".
    #
    # This has to happen on the DEPLOYED copy rather than the built one: a
    # bundle signature seals Info.plist, and the Ninja plist fixup that several
    # house products run writes into the deployed bundle after this copy. Signing
    # the source and letting the copy carry the signature would be undone by
    # that write. Signing here, last, is what survives it -- and re-signing is
    # idempotent, so a product that adds its own later step can sign again
    # harmlessly.
    #
    # `--force` replaces the linker's signature rather than failing on it.
    # Verification uses the CONSUMER's check, not the signer's own exit code:
    # the entire defect is a signature codesign was happy to produce and only
    # the Security API rejected.
    # IT MUST BE THE LAST POST_BUILD STEP, and that is not automatic. The seal
    # covers Info.plist (tamper with it and the check returns -67030), while
    # several house products append a Ninja plist fixup that writes into the
    # DEPLOYED bundle after this function has run. Signing at this point in the
    # file appears to work only because that fixup currently copies byte-identical
    # content, leaving the hashes unchanged -- the moment the two differ, the
    # deployed bundle is signed-then-modified and vanishes from Live again, which
    # is the very failure this exists to prevent.
    #
    # cmake_language(DEFER) queues the command until the end of the calling
    # directory's processing, which is after the product's own POST_BUILD steps
    # have been added; POST_BUILD commands run in the order they were added, so
    # deferring puts the signature last. DEFER needs CMake 3.19 and this project
    # declares 3.14, hence the guarded fallback.
    if(APPLE)
      if(NOT CMAKE_VERSION VERSION_LESS 3.19)
        # DEFER CALL re-evaluates its arguments in the DEFERRED scope, where
        # these locals no longer exist -- passing "${target}" straight through
        # silently arrives empty and add_custom_command then fails with
        # "TARGET requires a value". EVAL CODE expands them now and bakes the
        # results in as bracket-quoted literals, which is the documented way to
        # defer a call with values rather than names.
        cmake_language(EVAL CODE
          "cmake_language(DEFER CALL _iplug_sign_bundle [[${target}]] [[${dest_path}]] [[${plugin_name}]])")
      else()
        # Pre-3.19: sign here and accept the ordering caveat above rather than
        # shipping unsigned bundles. Say so, because a silent weaker guarantee
        # is how this class of defect survives.
        message(STATUS "[iPlug2] CMake < 3.19: signing ${plugin_name} before any product post-build steps; a product that rewrites the deployed bundle afterwards must re-sign it.")
        _iplug_sign_bundle("${target}" "${dest_path}" "${plugin_name}")
      endif()
    endif()
  else()
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E echo "[iPlug2] Copying plugin: ${dest_path}"
      COMMAND ${CMAKE_COMMAND} -E make_directory "${dest_dir}"
      COMMAND ${CMAKE_COMMAND} -E rm -f "${dest_path}"
      COMMAND ${CMAKE_COMMAND} -E copy "${source_path}" "${dest_path}"
      COMMENT "[iPlug2] Deploying ${plugin_name} (copy)"
    )
  endif()
endfunction()

#------------------------------------------------------------------------
# iplug_deploy_target
# Deploy a plugin target to its system directory
# Creates symlink or copies based on IPLUG_DEPLOY_METHOD
#
# @param target       The CMake target for the plugin
# @param format       Plugin format: VST3, CLAP, AU, APP
# @param project_name The plugin name (used for the bundle/file name)
#------------------------------------------------------------------------
function(iplug_deploy_target target format project_name)
  if(NOT IPLUG_DEPLOY_PLUGINS)
    return()
  endif()

  # Get deployment path
  iplug_get_default_deploy_path(${format})
  set(deploy_path "${IPLUG_DEPLOY_PATH_${format}}")

  if("${deploy_path}" STREQUAL "")
    message(STATUS "[iPlug2] No deployment path for ${format} on this platform, skipping")
    return()
  endif()

  # Determine plugin file/bundle name, extension, and whether it's a bundle or single file
  # is_bundle: TRUE for directory bundles (macOS bundles, VST3 bundles), FALSE for single files
  set(is_bundle TRUE)
  if(format STREQUAL "VST2")
    if(APPLE)
      set(plugin_name "${project_name}.vst")
    else()
      set(plugin_name "${project_name}.dll")
      set(is_bundle FALSE)
    endif()
  elseif(format STREQUAL "VST3")
    set(plugin_name "${project_name}.vst3")
    # VST3 is a bundle on all platforms
  elseif(format STREQUAL "CLAP")
    set(plugin_name "${project_name}.clap")
    # CLAP is a bundle on macOS, single file on Windows/Linux
    if(NOT APPLE)
      set(is_bundle FALSE)
    endif()
  elseif(format STREQUAL "AU" OR format STREQUAL "AUv2")
    set(plugin_name "${project_name}.component")
  elseif(format STREQUAL "AAX")
    set(plugin_name "${project_name}.aaxplugin")
    # AAX is always a bundle
  elseif(format STREQUAL "APP")
    if(APPLE)
      set(plugin_name "${project_name}.app")
    else()
      set(plugin_name "${project_name}")
      set(is_bundle FALSE)
    endif()
  elseif(format STREQUAL "REAPEREXT")
    if(APPLE)
      set(plugin_name "${project_name}.dylib")
    else()
      set(plugin_name "${project_name}.dll")
    endif()
    set(is_bundle FALSE)
  else()
    message(WARNING "[iPlug2] Unknown format ${format} for deployment")
    return()
  endif()

  # Get source path - handle both Xcode and Ninja/Make generators
  if(CMAKE_GENERATOR MATCHES "Xcode")
    # Xcode: use generator expression that resolves at build time
    # REAPEREXT is a dylib (not a bundle), so use TARGET_FILE instead
    if(format STREQUAL "REAPEREXT")
      set(source_path "$<TARGET_FILE:${target}>")
    else()
      set(source_path "$<TARGET_BUNDLE_DIR:${target}>")
    endif()
  else()
    # Ninja/Make: plugin is in CMAKE_BINARY_DIR/out
    set(source_path "${CMAKE_BINARY_DIR}/out/${plugin_name}")
  endif()

  message(STATUS "[iPlug2] Will deploy ${target} to ${deploy_path} using ${IPLUG_DEPLOY_METHOD}")

  # Create deployment command based on method
  if(IPLUG_DEPLOY_METHOD STREQUAL "COPY")
    _iplug_copy_plugin(${target} "${source_path}" "${deploy_path}" "${plugin_name}" ${is_bundle})
  else()
    # Default to SYMLINK
    _iplug_create_plugin_link(${target} "${source_path}" "${deploy_path}" "${plugin_name}")
  endif()
endfunction()

#------------------------------------------------------------------------
# iplug_deploy_all
# Deploy all plugin formats for a project
# Call this after all targets are configured
#
# @param project_name  The project name (used to find targets)
# @param FORMATS       List of formats to deploy (VST3, CLAP, AU, APP)
#------------------------------------------------------------------------
function(iplug_deploy_all project_name)
  cmake_parse_arguments(PARSE_ARGV 1 DEPLOY "" "" "FORMATS")

  if(NOT DEPLOY_FORMATS)
    # Default to all common formats
    set(DEPLOY_FORMATS VST3 CLAP)
    if(APPLE)
      list(APPEND DEPLOY_FORMATS AU APP)
    endif()
  endif()

  foreach(format ${DEPLOY_FORMATS})
    # Construct target name based on common naming convention
    string(TOLOWER ${format} format_lower)
    set(target_name "${project_name}-${format_lower}")

    # Handle AU special case (target is -au, format is AU or AUv2)
    if(format STREQUAL "AUv2")
      set(target_name "${project_name}-au")
    endif()

    if(TARGET ${target_name})
      iplug_deploy_target(${target_name} ${format} ${project_name})
    else()
      message(STATUS "[iPlug2] Target ${target_name} not found, skipping deployment")
    endif()
  endforeach()
endfunction()
