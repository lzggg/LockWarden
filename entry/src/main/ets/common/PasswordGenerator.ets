/**
 * 密码生成算法（生成器页与新建条目页共用同一实现）。
 *
 * 随机数由外部注入：
 *  - 真机：Index 注入基于 cryptoFramework 的密码学安全随机数；
 *  - 预览器：注入 Math.random，仅用于渲染演示。
 * 视图层因此不必依赖任何原生模块。
 */

export const UPPER_CHARS: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
export const LOWER_CHARS: string = 'abcdefghijklmnopqrstuvwxyz';
export const DIGIT_CHARS: string = '0123456789';
export const SYMBOL_CHARS: string = '!@#$%^&*()-_=+[]{};:,.?/';

export const PASSWORD_MIN_LENGTH: number = 5;
export const PASSWORD_MAX_LENGTH: number = 30;

export interface PasswordOptions {
  length: number;
  upper: boolean;
  lower: boolean;
  digits: boolean;
  symbols: boolean;
  /** 至少包含几个数字（字符集关闭时忽略） */
  minDigits: number;
  /** 至少包含几个特殊字符（字符集关闭时忽略） */
  minSymbols: number;
}

/** 新建条目时「一键生成」的默认参数：16 位、大小写 + 数字 */
export function defaultPasswordOptions(): PasswordOptions {
  const options: PasswordOptions = {
    length: 16,
    upper: true,
    lower: true,
    digits: true,
    symbols: false,
    minDigits: 0,
    minSymbols: 0
  };
  return options;
}

/** 按开关拼出候选字符集；全关时回退到小写，保证一定能生成 */
export function passwordAlphabet(options: PasswordOptions): string {
  let pool: string = '';
  if (options.upper) {
    pool += UPPER_CHARS;
  }
  if (options.lower) {
    pool += LOWER_CHARS;
  }
  if (options.digits) {
    pool += DIGIT_CHARS;
  }
  if (options.symbols) {
    pool += SYMBOL_CHARS;
  }
  return pool.length > 0 ? pool : LOWER_CHARS;
}

/** 生成密码：先随机填满，再把「最少数字 / 最少特殊字符」替换进去并整体打乱 */
export function generatePassword(options: PasswordOptions, random: (bound: number) => number): string {
  const pool: string = passwordAlphabet(options);
  const length: number = Math.max(PASSWORD_MIN_LENGTH, Math.min(PASSWORD_MAX_LENGTH, options.length));
  const chars: string[] = [];
  for (let i = 0; i < length; i++) {
    chars.push(pool.charAt(random(pool.length)));
  }

  // 至少 N 个数字 / 特殊字符：受总长度约束，两类之和不会超过长度
  let needDigits: number = options.digits ? Math.max(0, Math.floor(options.minDigits)) : 0;
  let needSymbols: number = options.symbols ? Math.max(0, Math.floor(options.minSymbols)) : 0;
  if (needDigits + needSymbols > length) {
    needDigits = Math.min(needDigits, length);
    needSymbols = Math.min(needSymbols, length - needDigits);
  }

  const positions: number[] = [];
  for (let i = 0; i < length; i++) {
    positions.push(i);
  }
  // Fisher-Yates 洗牌，保证替换位置随机
  for (let i = length - 1; i > 0; i--) {
    const j: number = random(i + 1);
    const tmp: number = positions[i];
    positions[i] = positions[j];
    positions[j] = tmp;
  }

  let cursor: number = 0;
  for (let i = 0; i < needDigits; i++) {
    chars[positions[cursor]] = DIGIT_CHARS.charAt(random(DIGIT_CHARS.length));
    cursor++;
  }
  for (let i = 0; i < needSymbols; i++) {
    chars[positions[cursor]] = SYMBOL_CHARS.charAt(random(SYMBOL_CHARS.length));
    cursor++;
  }

  let out: string = '';
  for (let i = 0; i < chars.length; i++) {
    out += chars[i];
  }
  return out;
}
