/**
 * 独立验证器（Authenticator）账号存储。
 *
 * 不依赖保险库条目：扫码或手动添加 otpauth 账号，账号密钥用**当前账号的 userKey**
 * 加密后存进本地 preferences（和条目一样是 AES-256-CBC + HMAC，见 BitwardenCrypto），
 * 因此磁盘上不会出现明文密钥。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { encryptToString, decryptToString, SymmetricCryptoKey } from './BitwardenCrypto';
import { VaultStore } from './VaultStore';

const PREFS_NAME: string = 'totp_vault';
const KEY_ACCOUNTS: string = 'accounts';

export interface TotpAccount {
  id: string;
  /** 发行方，如 GitHub */
  issuer: string;
  /** 账号，如 me@example.com */
  account: string;
  /** Base32 明文密钥（仅内存中出现） */
  secret: string;
  digits: number;
  period: number;
}

interface StoredAccount {
  id: string;
  issuer: string;
  account: string;
  /** 加密后的 secret */
  encSecret: string;
  digits: number;
  period: number;
}

function newId(): string {
  return `t${Date.now()}${Math.floor(Math.random() * 1000)}`;
}

/** 从 otpauth:// URI 解析账号；不是合法 otpauth 返回 null */
export function parseOtpauth(uri: string): TotpAccount | null {
  const text: string = uri.trim();
  if (!text.toLowerCase().startsWith('otpauth://totp/') && !text.toLowerCase().startsWith('otpauth://hotp/')) {
    return null;
  }
  let rest: string = text.substring('otpauth://'.length);
  const slash: number = rest.indexOf('/');
  if (slash < 0) {
    return null;
  }
  rest = rest.substring(slash + 1);
  const question: number = rest.indexOf('?');
  let label: string = question >= 0 ? rest.substring(0, question) : rest;
  const params: string = question >= 0 ? rest.substring(question + 1) : '';
  label = decodeURIComponent(label);

  let issuer: string = '';
  let account: string = label;
  const colon: number = label.indexOf(':');
  if (colon >= 0) {
    issuer = label.substring(0, colon).trim();
    account = label.substring(colon + 1).trim();
  }

  let secret: string = '';
  let digits: number = 6;
  let period: number = 30;
  const pairs: string[] = params.split('&');
  for (let i = 0; i < pairs.length; i++) {
    const eq: number = pairs[i].indexOf('=');
    if (eq < 0) {
      continue;
    }
    const name: string = pairs[i].substring(0, eq).toLowerCase();
    const value: string = decodeURIComponent(pairs[i].substring(eq + 1));
    if (name === 'secret') {
      secret = value;
    } else if (name === 'issuer' && issuer.length === 0) {
      issuer = value.trim();
    } else if (name === 'digits') {
      const n: number = Number.parseInt(value, 10);
      if (!Number.isNaN(n) && n >= 6 && n <= 8) {
        digits = n;
      }
    } else if (name === 'period') {
      const p: number = Number.parseInt(value, 10);
      if (!Number.isNaN(p) && p > 0) {
        period = p;
      }
    }
  }
  if (secret.length === 0) {
    return null;
  }
  const result: TotpAccount = {
    id: newId(),
    issuer: issuer,
    account: account,
    secret: secret,
    digits: digits,
    period: period
  };
  return result;
}

class TotpStoreImpl {
  accounts: TotpAccount[] = [];
  private prefs: preferences.Preferences | null = null;

  private key(): SymmetricCryptoKey | null {
    return VaultStore.userKey;
  }

  /** 解锁后调用；解密失败（换账号等）按"没有账号"处理 */
  async load(context: common.Context): Promise<void> {
    this.prefs = await preferences.getPreferences(context, PREFS_NAME);
    const raw: string = this.prefs.getSync(KEY_ACCOUNTS, '') as string;
    this.accounts = [];
    if (raw.length === 0) {
      return;
    }
    const key: SymmetricCryptoKey | null = this.key();
    if (key === null) {
      return;
    }
    try {
      const plain: string = await decryptToString(raw, key);
      const stored: StoredAccount[] = JSON.parse(plain) as StoredAccount[];
      const list: TotpAccount[] = [];
      for (let i = 0; i < stored.length; i++) {
        const item: StoredAccount = stored[i];
        let secret: string = '';
        try {
          secret = await decryptToString(item.encSecret, key);
        } catch (e) {
          secret = '';
        }
        if (secret.length === 0) {
          continue;
        }
        const acc: TotpAccount = {
          id: item.id,
          issuer: item.issuer,
          account: item.account,
          secret: secret,
          digits: item.digits,
          period: item.period
        };
        list.push(acc);
      }
      this.accounts = list;
    } catch (e) {
      this.accounts = [];
    }
  }

  private async persist(): Promise<void> {
    const key: SymmetricCryptoKey | null = this.key();
    if (key === null) {
      throw new Error('请先解锁保险库');
    }
    if (this.prefs === null) {
      throw new Error('验证器存储未初始化');
    }
    const stored: StoredAccount[] = [];
    for (let i = 0; i < this.accounts.length; i++) {
      const acc: TotpAccount = this.accounts[i];
      const item: StoredAccount = {
        id: acc.id,
        issuer: acc.issuer,
        account: acc.account,
        encSecret: await encryptToString(acc.secret, key),
        digits: acc.digits,
        period: acc.period
      };
      stored.push(item);
    }
    const blob: string = await encryptToString(JSON.stringify(stored), key);
    this.prefs.putSync(KEY_ACCOUNTS, blob);
    await this.prefs.flush();
  }

  async add(account: TotpAccount): Promise<void> {
    const list: TotpAccount[] = this.accounts.slice(0);
    list.push(account);
    this.accounts = list;
    await this.persist();
  }

  async remove(id: string): Promise<void> {
    const list: TotpAccount[] = [];
    for (let i = 0; i < this.accounts.length; i++) {
      if (this.accounts[i].id !== id) {
        list.push(this.accounts[i]);
      }
    }
    this.accounts = list;
    await this.persist();
  }

}

export const TotpStore: TotpStoreImpl = new TotpStoreImpl();
