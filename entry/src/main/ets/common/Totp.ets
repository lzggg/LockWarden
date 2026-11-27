/**
 * TOTP（RFC 6238）实现。
 *
 * 这里刻意用**纯 ArkTS** 实现 SHA-1 / HMAC-SHA1，不依赖 @kit.CryptoArchitectureKit：
 * DevEco 预览器没有 security 原生模块，一旦 UI 路径上出现 cryptoFramework 的静态导入，
 * 整个页面就会预览失败。纯 JS 实现让详情页在预览器里也能正常显示动态码，
 * 同时真机行为不变（RFC 6238 标准算法）。
 *
 * Vaultwarden 存储的 totp 字段是加密的 otpauth:// URI 或裸 Base32 密钥，两种都支持。
 */

const BASE32_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function rotl(value: number, bits: number): number {
  return ((value << bits) | (value >>> (32 - bits))) >>> 0;
}

/** SHA-1（FIPS 180-1），输入任意字节，输出 20 字节 */
function sha1(data: Uint8Array): Uint8Array {
  const bitLength: number = data.length * 8;
  const total: number = Math.ceil((data.length + 9) / 64) * 64;
  const buffer: Uint8Array = new Uint8Array(total);
  buffer.set(data);
  buffer[data.length] = 0x80;

  const high: number = Math.floor(bitLength / 4294967296);
  const low: number = bitLength % 4294967296;
  for (let i = 0; i < 4; i++) {
    buffer[total - 1 - i] = Math.floor(low / Math.pow(256, i)) % 256;
    buffer[total - 5 - i] = Math.floor(high / Math.pow(256, i)) % 256;
  }

  let h0: number = 0x67452301;
  let h1: number = 0xEFCDAB89;
  let h2: number = 0x98BADCFE;
  let h3: number = 0x10325476;
  let h4: number = 0xC3D2E1F0;
  const w: number[] = new Array<number>(80);

  for (let block = 0; block < total; block += 64) {
    for (let i = 0; i < 16; i++) {
      const offset: number = block + i * 4;
      w[i] = ((buffer[offset] << 24) | (buffer[offset + 1] << 16) |
        (buffer[offset + 2] << 8) | buffer[offset + 3]) >>> 0;
    }
    for (let i = 16; i < 80; i++) {
      w[i] = rotl((w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]) >>> 0, 1);
    }

    let a: number = h0;
    let b: number = h1;
    let c: number = h2;
    let d: number = h3;
    let e: number = h4;

    for (let i = 0; i < 80; i++) {
      let f: number = 0;
      let k: number = 0;
      if (i < 20) {
        f = (b & c) | ((~b) & d);
        k = 0x5A827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }
      const temp: number = (rotl(a, 5) + (f >>> 0) + e + k + w[i]) >>> 0;
      e = d;
      d = c;
      c = rotl(b, 30);
      b = a;
      a = temp;
    }

    h0 = (h0 + a) >>> 0;
    h1 = (h1 + b) >>> 0;
    h2 = (h2 + c) >>> 0;
    h3 = (h3 + d) >>> 0;
    h4 = (h4 + e) >>> 0;
  }

  const out: Uint8Array = new Uint8Array(20);
  const words: number[] = [h0, h1, h2, h3, h4];
  for (let i = 0; i < 5; i++) {
    out[i * 4] = (words[i] >>> 24) & 0xFF;
    out[i * 4 + 1] = (words[i] >>> 16) & 0xFF;
    out[i * 4 + 2] = (words[i] >>> 8) & 0xFF;
    out[i * 4 + 3] = words[i] & 0xFF;
  }
  return out;
}

/** HMAC-SHA1（RFC 2104），输出 20 字节 */
function hmacSha1(key: Uint8Array, message: Uint8Array): Uint8Array {
  const blockSize: number = 64;
  let normalised: Uint8Array = key;
  if (key.length > blockSize) {
    normalised = sha1(key);
  }
  const padded: Uint8Array = new Uint8Array(blockSize);
  padded.set(normalised);

  const inner: Uint8Array = new Uint8Array(blockSize + message.length);
  const outer: Uint8Array = new Uint8Array(blockSize + 20);
  for (let i = 0; i < blockSize; i++) {
    inner[i] = padded[i] ^ 0x36;
    outer[i] = padded[i] ^ 0x5C;
  }
  inner.set(message, blockSize);
  outer.set(sha1(inner), blockSize);
  return sha1(outer);
}

function base32Decode(input: string): Uint8Array {
  const clean: string = input.toUpperCase().replace(new RegExp('=', 'g'), '').replace(new RegExp('\\s', 'g'), '');
  let bits: number = 0;
  let value: number = 0;
  const out: number[] = [];
  for (let i = 0; i < clean.length; i++) {
    const idx: number = BASE32_ALPHABET.indexOf(clean.charAt(i));
    if (idx < 0) {
      throw new Error('非法的 Base32 字符');
    }
    value = ((value << 5) | idx) >>> 0;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.push((value >>> bits) & 0xFF);
    }
  }
  return new Uint8Array(out);
}

/** Base32 密钥长度是否合法（去掉 = 和空白后，长度对 8 取余只能是 0/2/4/5/7） */
export function isBase32LengthValid(raw: string): boolean {
  const clean: string = raw.trim().toUpperCase().replace(new RegExp('=', 'g'), '')
    .replace(new RegExp('\\s', 'g'), '');
  if (clean.length === 0) {
    return false;
  }
  const rem: number = clean.length % 8;
  return rem === 0 || rem === 2 || rem === 4 || rem === 5 || rem === 7;
}

/** 从 otpauth:// URI 或裸密钥里取出 Base32 密钥 */
export function extractTotpSecret(raw: string): string {
  const text: string = raw.trim();
  if (!text.toLowerCase().startsWith('otpauth://')) {
    return text;
  }
  const marker: number = text.toLowerCase().indexOf('secret=');
  if (marker < 0) {
    throw new Error('otpauth URI 缺少 secret 参数');
  }
  let rest: string = text.substring(marker + 7);
  const amp: number = rest.indexOf('&');
  if (amp >= 0) {
    rest = rest.substring(0, amp);
  }
  return decodeURIComponent(rest);
}

/** 生成当前时间片的验证码 */
export function generateTotpSync(raw: string, digits: number, period: number): string {
  const secret: Uint8Array = base32Decode(extractTotpSecret(raw));
  const counter: number = Math.floor(Date.now() / 1000 / period);
  const message: Uint8Array = new Uint8Array(8);
  let temp: number = counter;
  for (let i = 7; i >= 0; i--) {
    message[i] = temp & 0xFF;
    temp = Math.floor(temp / 256);
  }
  const digest: Uint8Array = hmacSha1(secret, message);
  const offset: number = digest[digest.length - 1] & 0x0F;
  const binary: number = ((digest[offset] & 0x7F) << 24) |
    ((digest[offset + 1] & 0xFF) << 16) |
    ((digest[offset + 2] & 0xFF) << 8) |
    (digest[offset + 3] & 0xFF);
  let code: string = (binary % Math.pow(10, digits)).toString();
  while (code.length < digits) {
    code = `0${code}`;
  }
  return code;
}

/** 指定时间戳的验证码，便于测试 */
export function secondsRemaining(period: number): number {
  return period - (Math.floor(Date.now() / 1000) % period);
}
