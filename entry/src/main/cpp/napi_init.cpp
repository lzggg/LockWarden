/*
 * Argon2id 的 NAPI 封装。
 *
 * 只暴露一个同步函数：
 *   argon2idRaw(password, salt, t, mKiB, parallelism, outLen) -> ArrayBuffer
 *
 * 使用官方参考实现（P-H-C/phc-winner-argon2），编译时定义 ARGON2_NO_THREADS，
 * 因此 lanes 是顺序计算的，结果与多线程版本一致。
 */
#include <cstring>
#include <vector>

#include "napi/native_api.h"
#include "argon2.h"

namespace {

bool GetBytes(napi_env env, napi_value value, std::vector<uint8_t>& out) {
  napi_typedarray_type type;
  size_t length = 0;
  void* data = nullptr;
  napi_value arraybuffer = nullptr;
  size_t byte_offset = 0;
  if (napi_get_typedarray_info(env, value, &type, &length, &data, &arraybuffer, &byte_offset) != napi_ok) {
    return false;
  }
  if (type != napi_uint8_array) {
    return false;
  }
  const uint8_t* bytes = static_cast<const uint8_t*>(data);
  out.assign(bytes, bytes + length);
  return true;
}

napi_value Argon2idRaw(napi_env env, napi_callback_info info) {
  size_t argc = 6;
  napi_value argv[6] = {nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc < 6) {
    napi_throw_error(env, nullptr, "argon2idRaw requires 6 arguments");
    return nullptr;
  }

  std::vector<uint8_t> password;
  std::vector<uint8_t> salt;
  if (!GetBytes(env, argv[0], password) || !GetBytes(env, argv[1], salt)) {
    napi_throw_type_error(env, nullptr, "password and salt must be Uint8Array");
    return nullptr;
  }

  uint32_t iterations = 0;
  uint32_t memory_kib = 0;
  uint32_t parallelism = 0;
  uint32_t out_len = 0;
  napi_get_value_uint32(env, argv[2], &iterations);
  napi_get_value_uint32(env, argv[3], &memory_kib);
  napi_get_value_uint32(env, argv[4], &parallelism);
  napi_get_value_uint32(env, argv[5], &out_len);

  if (out_len == 0 || out_len > 1024) {
    napi_throw_range_error(env, nullptr, "outLen must be 1..1024");
    return nullptr;
  }

  std::vector<uint8_t> out(out_len);
  int rc = argon2id_hash_raw(iterations, memory_kib, parallelism,
                             password.data(), password.size(),
                             salt.data(), salt.size(),
                             out.data(), out.size());
  if (rc != ARGON2_OK) {
    napi_throw_error(env, nullptr, argon2_error_message(rc));
    return nullptr;
  }

  napi_value buffer = nullptr;
  void* buffer_data = nullptr;
  if (napi_create_arraybuffer(env, out_len, &buffer_data, &buffer) != napi_ok) {
    napi_throw_error(env, nullptr, "failed to create ArrayBuffer");
    return nullptr;
  }
  std::memcpy(buffer_data, out.data(), out_len);
  return buffer;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
    {"argon2idRaw", nullptr, Argon2idRaw, nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  return exports;
}

} // namespace

static napi_module argon2Module = {
  .nm_version = 1,
  .nm_flags = 0,
  .nm_filename = nullptr,
  .nm_register_func = Init,
  .nm_modname = "argon2_napi",
  .nm_priv = nullptr,
  .reserved = {0}
};

extern "C" __attribute__((constructor)) void RegisterArgon2Module(void) {
  napi_module_register(&argon2Module);
}
