cmake_minimum_required(VERSION 3.5.0)
project(lockwarden)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# hvigor 会传入 --gcc-toolchain，clang 未使用该参数；静默这条无害警告
add_compile_options(-Wno-unused-command-line-argument)

add_library(argon2_napi SHARED
  napi_init.cpp
  argon2/argon2.c
  argon2/core.c
  argon2/ref.c
  argon2/encoding.c
  argon2/thread.c
  argon2/blake2/blake2b.c
)

target_compile_definitions(argon2_napi PRIVATE ARGON2_NO_THREADS)
target_include_directories(argon2_napi PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/argon2)

target_link_libraries(argon2_napi PUBLIC libace_napi.z.so)
