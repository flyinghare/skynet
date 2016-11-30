
cmake_minimum_required(VERSION 2.8)
cmake_policy(SET CMP0017 NEW)

project (skynet)

# The version number
#set(SKYNET_VERSION 1.0)

#set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -DSKYNET_DEBUG=1")
#ADD_DEFINITIONS (-D_USRDLL -D_EXPORT_DLL_ -D_USEGUIDLL -D_USREXDLL -D_USRSTUDIODLL)

#message( FATAL_ERROR "Unsupported platform, CMake will exit" )

include_directories(
  ${CMAKE_CURRENT_SOURCE_DIR}/skynet-src
  ${CMAKE_CURRENT_SOURCE_DIR}/service-src
  ${CMAKE_CURRENT_SOURCE_DIR}/lualib-src
  ${CMAKE_CURRENT_SOURCE_DIR}/lualib-src/sproto
  ${CMAKE_CURRENT_SOURCE_DIR}/3rd/jemalloc
  ${CMAKE_CURRENT_SOURCE_DIR}/3rd/lpeg
  ${CMAKE_CURRENT_SOURCE_DIR}/3rd/lua
  ${CMAKE_CURRENT_SOURCE_DIR}/3rd/lua-md5
)

#include(CocosUsePrebuiltLibs)
#find_package(Threads REQUIRED)

#add_subdirectory(skynet-src)
#add_subdirectory(service-src)
#add_subdirectory(lualib-src)
#add_subdirectory(lualib-src/sproto)
#add_subdirectory(3rd/jemalloc)
#add_subdirectory(3rd/lpeg)
#add_subdirectory(3rd/lua)
#add_subdirectory(3rd/lua-md5)


AUX_SOURCE_DIRECTORY(skynet-src SKYNET_SRCS)
#ADD_LIBRARY(skynet STATIC ${SKYNET_SRCS})
