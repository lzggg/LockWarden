/**
 * Bitwarden / Vaultwarden 客户端侧加密。
 *
 * 协议依据：vaultwarden-main/src/crypto.rs（CipherString 解析）与
 * vaultwarden-main/src/api/identity.rs（登录口令摘要）。
 *
 * 密钥层级（个人账号，PBKDF2 KDF）：
 *   masterKey   = PBKDF2-SHA256(password, email, kdfIterations, 32)
 *   hashedPass  = Base64(PBKDF2-SHA256(masterKey, password, 1, 32))   -> 登录时作为 password 提交
 *   stretched   = HKDF-Expand(masterKey, "enc"|"mac") -> encKey(32) + macKey(32)
 *   userKey     = decrypt(profile.key, stretched)  -> encKey(32) + macKey(32)
 *   条目字段    = AES-256-CBC-PKCS7(encKey) 且 HMAC-SHA256(macKey, iv||ct)
 */
import { Bytes, pbkdf2Sha256, sha256, hkdfExpandSha256, hmacSha256, aesCbcEncrypt, aesCbcDecrypt,
  hmacSha256Sync, aesCbcDecryptSync } from './CryptoUtils';
import { argon2idRaw } from 'libargon2_napi.so';

/** KDF 类型，与 Vaultwarden 的 Kdf enum 一致 */
export enum KdfType {
  PBKDF2_SHA256 = 0,
  Argon2id = 1
}

/** CipherString 加密类型前缀 */
export enum CipherStringType {
  AesCbc256_B64 = 0,
  AesCbc128_HmacSha256_B64 = 1,
  AesCbc256_HmacSha256_B64 = 2,
  Rsa2048_OaepSha256_B64 = 3,
  Rsa2048_OaepSha1_B64 = 4
}

/** 对称密钥：encKey(32) 与可选 macKey(32) */
export class SymmetricCryptoKey {
  readonly encKey: Uint8Array;
  readonly macKey: Uint8Array | null;
  readonly key: Uint8Array;

  constructor(key: Uint8Array) {
    if (key.length !== 32 && key.length !== 64) {
      throw new Error(`对称密钥长度非法: ${key.length}`);
    }
    this.key = key;
    this.encKey = key.slice(0, 32);
    this.macKey = key.length === 64 ? key.slice(32, 64) : null;
  }

}

/**
 * 由主密码派生主密钥。
 *
 * - kdf = 0：PBKDF2-SHA256（Vaultwarden 默认）
 * - kdf = 2：Argon2id（RFC 9106，通过原生参考实现计算）
 *
 * Argon2id 的 salt 与 PBKDF2 相同，都使用小写邮箱。
 */
export async function deriveMasterKey(password: string, email: string, kdf: number,
  iterations: number, memoryKiB: number = 64, parallelism: number = 4): Promise<Uint8Array> {
  const salt: Uint8Array = Bytes.utf8(email.trim().toLowerCase());
  if (kdf === KdfType.Argon2id) {
    // Bitwarden 的 Argon2 与 PBKDF2 不同：盐不是邮箱本身，而是 SHA-256(邮箱小写)。
    const argonSalt: Uint8Array = await sha256(salt);
    // 服务器返回的 kdfMemory 单位是 MiB，Argon2 的 m_cost 以 KiB 计。
    const memoryMiB: number = memoryKiB > 0 ? memoryKiB : 64;
    const memoryKib: number = memoryMiB * 1024;
    const lanes: number = parallelism > 0 ? parallelism : 4;
    const raw: ArrayBuffer = argon2idRaw(Bytes.utf8(password), argonSalt, iterations, memoryKib, lanes, 32);
    return new Uint8Array(raw);
  }
  if (kdf !== KdfType.PBKDF2_SHA256) {
    throw new Error(`不支持的 KDF 类型: ${kdf}`);
  }
  return pbkdf2Sha256(Bytes.utf8(password), salt, iterations, 32);
}

/** 登录口令摘要：PBKDF2(masterKey, password, 1) 后 Base64 */
export async function hashMasterPassword(masterKey: Uint8Array, password: string): Promise<string> {
  const hash: Uint8Array = await pbkdf2Sha256(masterKey, Bytes.utf8(password), 1, 32);
  return Bytes.b64(hash);
}

/** 拉伸主密钥 -> encKey/macKey */
export async function stretchMasterKey(masterKey: Uint8Array): Promise<SymmetricCryptoKey> {
  const encKey: Uint8Array = await hkdfExpandSha256(masterKey, 'enc', 32);
  const macKey: Uint8Array = await hkdfExpandSha256(masterKey, 'mac', 32);
  return new SymmetricCryptoKey(Bytes.concat([encKey, macKey]));
}

/** 加密字符串：2.<ivB64>|<ctB64>|<macB64> */
export async function encryptToString(plaintext: string, key: SymmetricCryptoKey): Promise<string> {
  const iv: Uint8Array = Bytes.random(16);
  const ct: Uint8Array = await aesCbcEncrypt(key.encKey, iv, Bytes.utf8(plaintext));
  const mac: Uint8Array | null = key.macKey === null ? null :
    await hmacSha256(key.macKey, Bytes.concat([iv, ct]));
  if (mac === null) {
    return `${CipherStringType.AesCbc256_B64}.${Bytes.b64(iv)}|${Bytes.b64(ct)}`;
  }
  return `${CipherStringType.AesCbc256_HmacSha256_B64}.${Bytes.b64(iv)}|${Bytes.b64(ct)}|${Bytes.b64(mac)}`;
}

/** 可空字段的加密：null/undefined/空串按 Bitwarden 约定返回 null */
export async function encryptNullable(plaintext: string | null | undefined,
  key: SymmetricCryptoKey): Promise<string | null> {
  if (plaintext === null || plaintext === undefined) {
    return null;
  }
  const value: string = plaintext.toString();
  return value.length === 0 ? null : encryptToString(value, key);
}

/** 解密 2.xxx 形式的 CipherString；空值返回空串 */
export async function decryptToString(cipher: string | null | undefined,
  key: SymmetricCryptoKey): Promise<string> {
  if (cipher === null || cipher === undefined) {
    return '';
  }
  const raw: string = cipher.toString();
  if (raw.length === 0) {
    return '';
  }
  const dot: number = raw.indexOf('.');
  if (dot <= 0) {
    throw new Error('CipherString 缺少类型前缀');
  }
  const type: number = Number.parseInt(raw.substring(0, dot), 10);
  const payload: string = raw.substring(dot + 1);
  if (type === CipherStringType.AesCbc256_HmacSha256_B64) {
    const parts: string[] = payload.split('|');
    if (parts.length !== 3) {
      throw new Error('CipherString 分量数量非法');
    }
    if (key.macKey === null) {
      throw new Error('缺少 macKey，无法校验完整性');
    }
    const iv: Uint8Array = Bytes.fromB64(parts[0]);
    const ct: Uint8Array = Bytes.fromB64(parts[1]);
    const mac: Uint8Array = Bytes.fromB64(parts[2]);
    const expected: Uint8Array = await hmacSha256(key.macKey, Bytes.concat([iv, ct]));
    if (!Bytes.equals(expected, mac)) {
      throw new Error('完整性校验失败（MAC 不匹配）');
    }
    const plain: Uint8Array = await aesCbcDecrypt(key.encKey, iv, ct);
    return Bytes.toUtf8(plain);
  }
  if (type === CipherStringType.AesCbc256_B64) {
    const parts: string[] = payload.split('|');
    if (parts.length !== 2) {
      throw new Error('CipherString 分量数量非法');
    }
    const iv: Uint8Array = Bytes.fromB64(parts[0]);
    const ct: Uint8Array = Bytes.fromB64(parts[1]);
    const plain: Uint8Array = await aesCbcDecrypt(key.encKey, iv, ct);
    return Bytes.toUtf8(plain);
  }
  throw new Error(`不支持的加密类型: ${type}`);
}

/** 同步版解密：与 decryptToString 等价，供同步阶段批量解密（避免逐字段 await） */
export function decryptToStringSync(cipher: string | null | undefined, key: SymmetricCryptoKey): string {
  if (cipher === null || cipher === undefined) {
    return '';
  }
  const raw: string = cipher.toString();
  if (raw.length === 0) {
    return '';
  }
  const dot: number = raw.indexOf('.');
  if (dot <= 0) {
    throw new Error('CipherString 缺少类型前缀');
  }
  const type: number = Number.parseInt(raw.substring(0, dot), 10);
  const payload: string = raw.substring(dot + 1);
  if (type === CipherStringType.AesCbc256_HmacSha256_B64) {
    const parts: string[] = payload.split('|');
    if (parts.length !== 3) {
      throw new Error('CipherString 分量数量非法');
    }
    if (key.macKey === null) {
      throw new Error('缺少 macKey，无法校验完整性');
    }
    const iv: Uint8Array = Bytes.fromB64(parts[0]);
    const ct: Uint8Array = Bytes.fromB64(parts[1]);
    const mac: Uint8Array = Bytes.fromB64(parts[2]);
    const expected: Uint8Array = hmacSha256Sync(key.macKey, Bytes.concat([iv, ct]));
    if (!Bytes.equals(expected, mac)) {
      throw new Error('完整性校验失败（MAC 不匹配）');
    }
    return Bytes.toUtf8(aesCbcDecryptSync(key.encKey, iv, ct));
  }
  if (type === CipherStringType.AesCbc256_B64) {
    const parts: string[] = payload.split('|');
    if (parts.length !== 2) {
      throw new Error('CipherString 分量数量非法');
    }
    const iv: Uint8Array = Bytes.fromB64(parts[0]);
    const ct: Uint8Array = Bytes.fromB64(parts[1]);
    return Bytes.toUtf8(aesCbcDecryptSync(key.encKey, iv, ct));
  }
  throw new Error(`不支持的加密类型: ${type}`);
}

/** 同步版解密（返回字节）：用于解密条目自带的 key（得 64 字节 symmetric key） */
export function decryptToBytesSync(cipher: string | null | undefined, key: SymmetricCryptoKey): Uint8Array {
  if (cipher === null || cipher === undefined) {
    return new Uint8Array(0);
  }
  const raw: string = cipher.toString();
  const dot: number = raw.indexOf('.');
  if (dot <= 0) {
    throw new Error('CipherString 缺少类型前缀');
  }
  const type: number = Number.parseInt(raw.substring(0, dot), 10);
  const payload: string = raw.substring(dot + 1);
  const parts: string[] = payload.split('|');
  if (type === CipherStringType.AesCbc256_HmacSha256_B64) {
    if (parts.length !== 3 || key.macKey === null) {
      throw new Error('CipherString 分量非法或缺少 macKey');
    }
    const iv: Uint8Array = Bytes.fromB64(parts[0]);
    const ct: Uint8Array = Bytes.fromB64(parts[1]);
    const mac: Uint8Array = Bytes.fromB64(parts[2]);
    const expected: Uint8Array = hmacSha256Sync(key.macKey, Bytes.concat([iv, ct]));
    if (!Bytes.equals(expected, mac)) {
      throw new Error('完整性校验失败（MAC 不匹配）');
    }
    return aesCbcDecryptSync(key.encKey, iv, ct);
  }
  if (type === CipherStringType.AesCbc256_B64) {
    if (parts.length !== 2) {
      throw new Error('CipherString 分量数量非法');
    }
    return aesCbcDecryptSync(key.encKey, Bytes.fromB64(parts[0]), Bytes.fromB64(parts[1]));
  }
  throw new Error(`不支持的加密类型: ${type}`);
}

/** 拿对称密钥解密服务端返回的 Key 字段（个人账号密钥环） */
export async function decryptUserKey(encryptedKey: string, stretched: SymmetricCryptoKey): Promise<SymmetricCryptoKey> {
  const dot: number = encryptedKey.indexOf('.');
  if (dot <= 0) {
    throw new Error('Key 字段格式非法');
  }
  const type: number = Number.parseInt(encryptedKey.substring(0, dot), 10);
  if (type !== CipherStringType.AesCbc256_HmacSha256_B64) {
    throw new Error(`不支持的账号密钥类型: ${type}`);
  }
  const parts: string[] = encryptedKey.substring(dot + 1).split('|');
  if (parts.length !== 3) {
    throw new Error('Key 字段分量数量非法');
  }
  if (stretched.macKey === null) {
    throw new Error('缺少 macKey');
  }
  const iv: Uint8Array = Bytes.fromB64(parts[0]);
  const ct: Uint8Array = Bytes.fromB64(parts[1]);
  const mac: Uint8Array = Bytes.fromB64(parts[2]);
  const expected: Uint8Array = await hmacSha256(stretched.macKey, Bytes.concat([iv, ct]));
  if (!Bytes.equals(expected, mac)) {
    throw new Error('主密码错误（账号密钥校验失败）');
  }
  const plain: Uint8Array = await aesCbcDecrypt(stretched.encKey, iv, ct);
  if (plain.length !== 64 && plain.length !== 32) {
    throw new Error(`账号密钥长度异常: ${plain.length}`);
  }
  return new SymmetricCryptoKey(plain);
}

/** 用拉伸密钥加密账号密钥，用于本地离线解锁 */
export async function encryptUserKey(key: SymmetricCryptoKey, stretched: SymmetricCryptoKey): Promise<string> {
  const iv: Uint8Array = Bytes.random(16);
  const ct: Uint8Array = await aesCbcEncrypt(stretched.encKey, iv, key.key);
  const mac: Uint8Array = await hmacSha256(stretched.macKey as Uint8Array, Bytes.concat([iv, ct]));
  return `${CipherStringType.AesCbc256_HmacSha256_B64}.${Bytes.b64(iv)}|${Bytes.b64(ct)}|${Bytes.b64(mac)}`;
}
