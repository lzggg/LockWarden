/**
 * 基础字节 / 编码 / 密码学原语封装。
 *
 * 全部基于 HarmonyOS 原生 @kit.CryptoArchitectureKit 与 @kit.ArkTS 的 util，
 * 不依赖任何三方库，保证 HAP 体积与签名合规。
 *
 * 与 Bitwarden/Vaultwarden 协议相关的算法约定（详见 docs/api-contract.md）：
 *  - PBKDF2-HMAC-SHA256：主密钥派生
 *  - HKDF-Expand(HMAC-SHA256, PRK=masterKey, info="enc"/"mac")：拉伸密钥
 *  - AES-256-CBC + PKCS7 + HMAC-SHA256(encrypt-then-MAC)：密码库字段加解密
 */
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';

const ENCODER: util.TextEncoder = new util.TextEncoder();
const DECODER: util.TextDecoder = util.TextDecoder.create('utf-8');
const B64: util.Base64Helper = new util.Base64Helper();

export class Bytes {
  /** 字符串 -> UTF-8 字节 */
  static utf8(text: string): Uint8Array {
    return ENCODER.encodeInto(text);
  }

  /** UTF-8 字节 -> 字符串 */
  static toUtf8(data: Uint8Array): string {
    return DECODER.decodeToString(data);
  }

  /** 标准 Base64 编码 */
  static b64(data: Uint8Array): string {
    return B64.encodeToStringSync(data);
  }

  /** 标准 Base64 解码 */
  static fromB64(text: string): Uint8Array {
    return B64.decodeSync(text);
  }

  static concat(parts: Uint8Array[]): Uint8Array {
    let total: number = 0;
    for (let i = 0; i < parts.length; i++) {
      total += parts[i].length;
    }
    const out: Uint8Array = new Uint8Array(total);
    let offset: number = 0;
    for (let i = 0; i < parts.length; i++) {
      out.set(parts[i], offset);
      offset += parts[i].length;
    }
    return out;
  }

  /** 密码学安全随机数 */
  static random(size: number): Uint8Array {
    const rnd: cryptoFramework.Random = cryptoFramework.createRandom();
    return rnd.generateRandomSync(size).data;
  }

  /** 定长比较，避免时序侧信道 */
  static equals(a: Uint8Array, b: Uint8Array): boolean {
    if (a.length !== b.length) {
      return false;
    }
    let diff: number = 0;
    for (let i = 0; i < a.length; i++) {
      diff |= (a[i] ^ b[i]);
    }
    return diff === 0;
  }

}

function toError(e: Object, where: string): Error {
  const be: BusinessError = e as BusinessError;
  const msg: string = be && be.message ? be.message : JSON.stringify(e);
  return new Error(`${where} 失败: ${msg}`);
}

/** PBKDF2-HMAC-SHA256，输出 size 字节 */
export async function pbkdf2Sha256(password: Uint8Array, salt: Uint8Array,
  iterations: number, size: number): Promise<Uint8Array> {
  try {
    const kdf: cryptoFramework.Kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: password,
      salt: salt,
      iterations: iterations,
      keySize: size
    };
    const secret: cryptoFramework.DataBlob = await kdf.generateSecret(spec);
    return secret.data;
  } catch (e) {
    throw toError(e as Object, 'PBKDF2');
  }
}

async function hmac(algName: string, key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  try {
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
    const keyBlob: cryptoFramework.DataBlob = { data: key };
    const symKey: cryptoFramework.SymKey = await generator.convertKey(keyBlob);
    const mac: cryptoFramework.Mac = cryptoFramework.createMac(algName);
    await mac.init(symKey);
    await mac.update({ data: data });
    const result: cryptoFramework.DataBlob = await mac.doFinal();
    return result.data;
  } catch (e) {
    throw toError(e as Object, `HMAC-${algName}`);
  }
}

/** HMAC-SHA256 */
export async function hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  return hmac('SHA256', key, data);
}

/** HMAC-SHA1（仅 TOTP 使用） */
export async function hmacSha1(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  return hmac('SHA1', key, data);
}

/**
 * HKDF-Expand（RFC 5869 的 expand 部分，PRK 直接作为 HMAC key）。
 * Bitwarden 的 stretchKey 就是这个语义：不做 extract，只做单次 expand。
 */
export async function hkdfExpandSha256(prk: Uint8Array, info: string, length: number): Promise<Uint8Array> {
  const infoBytes: Uint8Array = Bytes.utf8(info);
  const blocks: Uint8Array[] = [];
  let previous: Uint8Array = new Uint8Array(0);
  let counter: number = 1;
  let produced: number = 0;
  while (produced < length) {
    const counterByte: Uint8Array = new Uint8Array([counter]);
    const input: Uint8Array = Bytes.concat([previous, infoBytes, counterByte]);
    const block: Uint8Array = await hmacSha256(prk, input);
    blocks.push(block);
    previous = block;
    produced += block.length;
    counter++;
  }
  const expanded: Uint8Array = Bytes.concat(blocks);
  return expanded.slice(0, length);
}

/** AES-256-CBC + PKCS7 加密 */
export async function aesCbcEncrypt(key: Uint8Array, iv: Uint8Array, plain: Uint8Array): Promise<Uint8Array> {
  try {
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
    const symKey: cryptoFramework.SymKey = await generator.convertKey({ data: key });
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
    const params: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: { data: iv } };
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
    const out: cryptoFramework.DataBlob = await cipher.doFinal({ data: plain });
    return out.data;
  } catch (e) {
    throw toError(e as Object, 'AES-CBC 加密');
  }
}

/** HMAC-SHA256（同步版，供批量解密使用） */
export function hmacSha256Sync(key: Uint8Array, data: Uint8Array): Uint8Array {
  try {
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
    const symKey: cryptoFramework.SymKey = generator.convertKeySync({ data: key });
    const mac: cryptoFramework.Mac = cryptoFramework.createMac('SHA256');
    mac.initSync(symKey);
    mac.updateSync({ data: data });
    return mac.doFinalSync().data;
  } catch (e) {
    throw toError(e as Object, 'HMAC-SHA256(同步)');
  }
}

/** AES-256-CBC + PKCS7 解密（同步版） */
export function aesCbcDecryptSync(key: Uint8Array, iv: Uint8Array, encrypted: Uint8Array): Uint8Array {
  try {
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
    const symKey: cryptoFramework.SymKey = generator.convertKeySync({ data: key });
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
    const params: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: { data: iv } };
    cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
    return cipher.doFinalSync({ data: encrypted }).data;
  } catch (e) {
    throw toError(e as Object, 'AES-CBC 解密(同步)');
  }
}

/** AES-256-CBC + PKCS7 解密 */
export async function aesCbcDecrypt(key: Uint8Array, iv: Uint8Array, encrypted: Uint8Array): Promise<Uint8Array> {
  try {
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
    const symKey: cryptoFramework.SymKey = await generator.convertKey({ data: key });
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
    const params: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: { data: iv } };
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
    const out: cryptoFramework.DataBlob = await cipher.doFinal({ data: encrypted });
    return out.data;
  } catch (e) {
    throw toError(e as Object, 'AES-CBC 解密');
  }
}
