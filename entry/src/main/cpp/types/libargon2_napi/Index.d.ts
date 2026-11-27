/**
 * Argon2id 原生模块的类型声明。
 *
 * password / salt 必须是 Uint8Array；返回原始哈希的 ArrayBuffer。
 */
export const argon2idRaw: (password: Uint8Array, salt: Uint8Array,
  iterations: number, memoryKiB: number, parallelism: number, outLen: number) => ArrayBuffer;
