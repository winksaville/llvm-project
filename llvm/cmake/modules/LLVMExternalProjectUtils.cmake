include(ExternalProject)

# llvm_ExternalProject_BuildCmd(out_var target)
#   Utility function for constructing command lines for external project targets
function(llvm_ExternalProject_BuildCmd out_var target bin_dir)
  cmake_parse_arguments(ARG "" "CONFIGURATION" "" ${ARGN})
  if(NOT ARG_CONFIGURATION)
    set(ARG_CONFIGURATION "$<CONFIG>")
  endif()
  if (CMAKE_GENERATOR MATCHES "Make")
    # Use special command for Makefiles to support parallelism.
    set(${out_var} "$(MAKE)" "-C" "${bin_dir}" "${target}" PARENT_SCOPE)
  else()
    set(${out_var} ${CMAKE_COMMAND} --build ${bin_dir} -v -j 11 --target ${target}
                                    --config ${ARG_CONFIGURATION} PARENT_SCOPE)
  endif()
endfunction()

# llvm_ExternalProject_Add(name source_dir ...
#   USE_TOOLCHAIN
#     Use just-built tools (see TOOLCHAIN_TOOLS)
#   EXCLUDE_FROM_ALL
#     Exclude this project from the all target
#   NO_INSTALL
#     Don't generate install targets for this project
#   ALWAYS_CLEAN
#     Always clean the sub-project before building
#   CMAKE_ARGS arguments...
#     Optional cmake arguments to pass when configuring the project
#   TOOLCHAIN_TOOLS targets...
#     Targets for toolchain tools (defaults to clang;lld)
#   DEPENDS targets...
#     Targets that this project depends on
#   EXTRA_TARGETS targets...
#     Extra targets in the subproject to generate targets for
#   PASSTHROUGH_PREFIXES prefix...
#     Extra variable prefixes (name is always included) to pass down
#   STRIP_TOOL path
#     Use provided strip tool instead of the default one.
#   )
function(llvm_ExternalProject_Add name source_dir)
  cmake_parse_arguments(ARG
    "USE_TOOLCHAIN;EXCLUDE_FROM_ALL;NO_INSTALL;ALWAYS_CLEAN"
    "SOURCE_DIR"
    "CMAKE_ARGS;TOOLCHAIN_TOOLS;RUNTIME_LIBRARIES;DEPENDS;EXTRA_TARGETS;PASSTHROUGH_PREFIXES;STRIP_TOOL"
    ${ARGN})
  canonicalize_tool_name(${name} nameCanon)
  if(NOT ARG_TOOLCHAIN_TOOLS)
    set(ARG_TOOLCHAIN_TOOLS clang lld)
    if(NOT APPLE AND NOT WIN32)
      list(APPEND ARG_TOOLCHAIN_TOOLS llvm-ar llvm-ranlib llvm-nm llvm-objcopy llvm-objdump llvm-strip)
    endif()
  endif()
  foreach(tool ${ARG_TOOLCHAIN_TOOLS})
    if(TARGET ${tool})
      list(APPEND TOOLCHAIN_TOOLS ${tool})
      list(APPEND TOOLCHAIN_BINS $<TARGET_FILE:${tool}>)
    endif()
  endforeach()

  if(NOT ARG_RUNTIME_LIBRARIES)
    set(ARG_RUNTIME_LIBRARIES compiler-rt libcxx)
  endif()
  foreach(lib ${ARG_RUNTIME_LIBRARIES})
    if(TARGET ${lib})
      list(APPEND RUNTIME_LIBRARIES ${lib})
    endif()
  endforeach()

  if(ARG_ALWAYS_CLEAN)
    set(always_clean clean)
  endif()

  list(FIND TOOLCHAIN_TOOLS clang FOUND_CLANG)
  if(FOUND_CLANG GREATER -1)
    set(CLANG_IN_TOOLCHAIN On)
  endif()

  if(RUNTIME_LIBRARIES AND CLANG_IN_TOOLCHAIN)
    list(APPEND TOOLCHAIN_BINS ${RUNTIME_LIBRARIES})
  endif()

  set(STAMP_DIR ${CMAKE_CURRENT_BINARY_DIR}/${name}-stamps/)
  set(BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR}/${name}-bins/)

  add_custom_target(${name}-clear
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${BINARY_DIR}
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${STAMP_DIR}
    COMMENT "Clobbering ${name} build and stamp directories"
    USES_TERMINAL
    )

  # Find all variables that start with a prefix and propagate them through
  get_cmake_property(variableNames VARIABLES)

  list(APPEND ARG_PASSTHROUGH_PREFIXES ${nameCanon})
  foreach(prefix ${ARG_PASSTHROUGH_PREFIXES})
    foreach(variableName ${variableNames})
      if(variableName MATCHES "^${prefix}")
        string(REPLACE ";" "|" value "${${variableName}}")
        list(APPEND PASSTHROUGH_VARIABLES
          -D${variableName}=${value})
      endif()
    endforeach()
  endforeach()

  foreach(arg ${ARG_CMAKE_ARGS})
    if(arg MATCHES "^-DCMAKE_SYSTEM_NAME=")
      string(REGEX REPLACE "^-DCMAKE_SYSTEM_NAME=(.*)$" "\\1" _cmake_system_name "${arg}")
    endif()
  endforeach()

  if(ARG_USE_TOOLCHAIN AND NOT CMAKE_CROSSCOMPILING)
    if(CLANG_IN_TOOLCHAIN)
      if(_cmake_system_name STREQUAL Windows)
        set(compiler_args -DCMAKE_C_COMPILER=${LLVM_RUNTIME_OUTPUT_INTDIR}/clang-cl
                          -DCMAKE_CXX_COMPILER=${LLVM_RUNTIME_OUTPUT_INTDIR}/clang-cl)
      else()
        set(compiler_args -DCMAKE_C_COMPILER=${LLVM_RUNTIME_OUTPUT_INTDIR}/clang
                          -DCMAKE_CXX_COMPILER=${LLVM_RUNTIME_OUTPUT_INTDIR}/clang++)
      endif()
    endif()
    if(lld IN_LIST TOOLCHAIN_TOOLS)
      if(_cmake_system_name STREQUAL Windows)
        list(APPEND compiler_args -DCMAKE_LINKER=${LLVM_RUNTIME_OUTPUT_INTDIR}/lld-link)
      else()
        list(APPEND compiler_args -DCMAKE_LINKER=${LLVM_RUNTIME_OUTPUT_INTDIR}/ld.lld)
      endif()
    endif()
    if(llvm-ar IN_LIST TOOLCHAIN_TOOLS)
      list(APPEND compiler_args -DCMAKE_AR=${LLVM_RUNTIME_OUTPUT_INTDIR}/llvm-ar)
    endif()
    if(llvm-ranlib IN_LIST TOOLCHAIN_TOOLS)
      list(APPEND compiler_args -DCMAKE_RANLIB=${LLVM_RUNTIME_OUTPUT_INTDIR}/llvm-ranlib)
    endif()
    if(llvm-nm IN_LIST TOOLCHAIN_TOOLS)
      list(APPEND compiler_args -DCMAKE_NM=${LLVM_RUNTIME_OUTPUT_INTDIR}/llvm-nm)
    endif()
    if(llvm-objdump IN_LIST TOOLCHAIN_TOOLS)
      list(APPEND compiler_args -DCMAKE_OBJDUMP=${LLVM_RUNTIME_OUTPUT_INTDIR}/llvm-objdump)
    endif()
    if(llvm-objcopy IN_LIST TOOLCHAIN_TOOLS)
      list(APPEND compiler_args -DCMAKE_OBJCOPY=${LLVM_RUNTIME_OUTPUT_INTDIR}/llvm-objcopy)
    endif()
    if(llvm-strip IN_LIST TOOLCHAIN_TOOLS AND NOT ARG_STRIP_TOOL)
      list(APPEND compiler_args -DCMAKE_STRIP=${LLVM_RUNTIME_OUTPUT_INTDIR}/llvm-strip)
    endif()
    list(APPEND ARG_DEPENDS ${TOOLCHAIN_TOOLS})
  endif()

  if(ARG_STRIP_TOOL)
    list(APPEND compiler_args -DCMAKE_STRIP=${ARG_STRIP_TOOL})
  endif()

  add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${name}-clobber-stamp
    DEPENDS ${ARG_DEPENDS}
    COMMAND ${CMAKE_COMMAND} -E touch ${BINARY_DIR}/CMakeCache.txt
    COMMAND ${CMAKE_COMMAND} -E touch ${STAMP_DIR}/${name}-mkdir
    COMMAND ${CMAKE_COMMAND} -E touch ${CMAKE_CURRENT_BINARY_DIR}/${name}-clobber-stamp
    COMMENT "Clobbering bootstrap build and stamp directories"
    )

  add_custom_target(${name}-clobber
    DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${name}-clobber-stamp)

  if(ARG_EXCLUDE_FROM_ALL)
    set(exclude EXCLUDE_FROM_ALL 1)
  endif()

  if(CMAKE_SYSROOT)
    set(sysroot_arg -DCMAKE_SYSROOT=${CMAKE_SYSROOT})
  endif()

  if(CMAKE_CROSSCOMPILING)
    set(compiler_args -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
                      -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                      -DCMAKE_LINKER=${CMAKE_LINKER}
                      -DCMAKE_AR=${CMAKE_AR}
                      -DCMAKE_RANLIB=${CMAKE_RANLIB}
                      -DCMAKE_NM=${CMAKE_NM}
                      -DCMAKE_OBJCOPY=${CMAKE_OBJCOPY}
                      -DCMAKE_OBJDUMP=${CMAKE_OBJDUMP}
                      -DCMAKE_STRIP=${CMAKE_STRIP})
    set(llvm_config_path ${LLVM_CONFIG_PATH})

    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
      string(REGEX MATCH "[0-9]+\\.[0-9]+(\\.[0-9]+)?" CLANG_VERSION
             ${PACKAGE_VERSION})
      set(resource_dir "${LLVM_LIBRARY_DIR}/clang/${CLANG_VERSION}")
      set(flag_types ASM C CXX MODULE_LINKER SHARED_LINKER EXE_LINKER)
      foreach(type ${flag_types})
        set(${type}_flag -DCMAKE_${type}_FLAGS=-resource-dir=${resource_dir})
      endforeach()
      string(REPLACE ";" "|" flag_string "${flag_types}")
      foreach(arg ${ARG_CMAKE_ARGS})
        if(arg MATCHES "^-DCMAKE_(${flag_string})_FLAGS")
          foreach(type ${flag_types})
            if(arg MATCHES "^-DCMAKE_${type}_FLAGS")
              string(REGEX REPLACE "^-DCMAKE_${type}_FLAGS=(.*)$" "\\1" flag_value "${arg}")
              set(${type}_flag "${${type}_flag} ${flag_value}")
            endif()
          endforeach()
        else()
          list(APPEND cmake_args ${arg})
        endif()
      endforeach()
      foreach(type ${flag_types})
        list(APPEND cmake_args ${${type}_flag})
      endforeach()
    endif()
  else()
    set(llvm_config_path "$<TARGET_FILE:llvm-config>")
    set(cmake_args ${ARG_CMAKE_ARGS})
  endif()

  ExternalProject_Add(${name}
    DEPENDS ${ARG_DEPENDS} llvm-config
    ${name}-clobber
    PREFIX ${CMAKE_BINARY_DIR}/projects/${name}
    SOURCE_DIR ${source_dir}
    STAMP_DIR ${STAMP_DIR}
    BINARY_DIR ${BINARY_DIR}
    ${exclude}
    CMAKE_ARGS ${${nameCanon}_CMAKE_ARGS}
               ${compiler_args}
               -DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}
               ${sysroot_arg}
               -DLLVM_BINARY_DIR=${PROJECT_BINARY_DIR}
               -DLLVM_CONFIG_PATH=${llvm_config_path}
               -DLLVM_ENABLE_WERROR=${LLVM_ENABLE_WERROR}
               -DLLVM_HOST_TRIPLE=${LLVM_HOST_TRIPLE}
               -DLLVM_HAVE_LINK_VERSION_SCRIPT=${LLVM_HAVE_LINK_VERSION_SCRIPT}
               -DPACKAGE_VERSION=${PACKAGE_VERSION}
               -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
               -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}
               -DCMAKE_EXPORT_COMPILE_COMMANDS=1
               ${cmake_args}
               ${PASSTHROUGH_VARIABLES}
    INSTALL_COMMAND ""
    STEP_TARGETS configure build
    BUILD_ALWAYS 1
    USES_TERMINAL_CONFIGURE 1
    USES_TERMINAL_BUILD 1
    USES_TERMINAL_INSTALL 1
    LIST_SEPARATOR |
    )

  if(ARG_USE_TOOLCHAIN)
    set(force_deps DEPENDS ${TOOLCHAIN_BINS})
  endif()

  llvm_ExternalProject_BuildCmd(run_clean clean ${BINARY_DIR})
  ExternalProject_Add_Step(${name} clean
    COMMAND ${run_clean}
    COMMENT "Cleaning ${name}..."
    DEPENDEES configure
    ${force_deps}
    WORKING_DIRECTORY ${BINARY_DIR}
    EXCLUDE_FROM_MAIN 1
    USES_TERMINAL 1
    )
  ExternalProject_Add_StepTargets(${name} clean)

  if(ARG_USE_TOOLCHAIN)
    add_dependencies(${name}-clean ${name}-clobber)
    set_target_properties(${name}-clean PROPERTIES
      SOURCES ${CMAKE_CURRENT_BINARY_DIR}/${name}-clobber-stamp)
  endif()

  if(NOT ARG_NO_INSTALL)
    install(CODE "execute_process\(COMMAND \${CMAKE_COMMAND} -DCMAKE_INSTALL_PREFIX=\${CMAKE_INSTALL_PREFIX} -DCMAKE_INSTALL_DO_STRIP=\${CMAKE_INSTALL_DO_STRIP} -P ${BINARY_DIR}/cmake_install.cmake\)"
      COMPONENT ${name})

    add_llvm_install_targets(install-${name}
                             DEPENDS ${name}
                             COMPONENT ${name})
  endif()

  # Add top-level targets
  foreach(target ${ARG_EXTRA_TARGETS})
    if(DEFINED ${target})
      set(external_target "${${target}}")
    else()
      set(external_target "${target}")
    endif()
    llvm_ExternalProject_BuildCmd(build_runtime_cmd ${external_target} ${BINARY_DIR})
    add_custom_target(${target}
      COMMAND ${build_runtime_cmd}
      DEPENDS ${name}-configure
      WORKING_DIRECTORY ${BINARY_DIR}
      VERBATIM
      USES_TERMINAL)
  endforeach()
endfunction()
