/**
 * 会话与状态中心。
 *
 * 设计要点（贴近 Bitwarden 官方客户端的行为）：
 *  - 只把「被拉伸密钥加密过的账号密钥」和「被账号密钥加密过的 refresh_token」落到本地，
 *    明文主密码、明文主密钥、明文 refresh_token 都不落盘。
 *  - 解锁是纯本地行为：重新派生主密钥 -> 解密账号密钥 -> 校验 MAC，失败即密码错误。
 *  - 同步结果（密文 JSON）缓存到沙箱文件，断网时仍可查看已同步条目。
 *  - 回收站与正常条目分开维护（服务端用 deletedDate 区分）。
 */
import { preferences } from '@kit.ArkData';
import { CertPinning } from './CertPinning';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import {
  deriveMasterKey, hashMasterPassword, stretchMasterKey, decryptUserKey, encryptUserKey,
  SymmetricCryptoKey, encryptToString, decryptToString, decryptToStringSync, decryptToBytesSync,
  encryptNullable
} from './BitwardenCrypto';
import {
  SyncResponse, SyncCipher, TokenResponse, PreloginResponse, VaultItem, VaultFolder,
  CipherRequest, LoginRequest, LoginUriRequest, CardRequest, IdentityRequest, FieldRequest,
  SecureNoteRequest, CipherType, CipherDraft, VaultCard, VaultIdentity, VaultField,
  SyncFolder, LoginData, CardData, IdentityData, FieldData, LoginUriData
} from './Models';
import * as Api from './Api';
import { Bytes } from './CryptoUtils';
import { demoItems, demoFolders } from './DemoData';
import { Biometric } from './Biometric';
import { wrapUserKey, unwrapUserKey, deleteBioKey } from './BioKeyStore';
import * as Clipboard from './Clipboard';

const PREFS_NAME: string = 'vaultwarden_prefs';
const CACHE_FILE: string = 'sync-cache.json';
/** 本地模式（不连接服务器）的数据文件 */
const LOCAL_FILE: string = 'local-vault.json';
/** 本地模式的默认迭代次数，与 Vaultwarden 新账号一致 */
const LOCAL_ITERATIONS: number = 600000;

const KEY_SERVER: string = 'server';
const KEY_EMAIL: string = 'email';
const KEY_DEVICE_ID: string = 'deviceId';
const KEY_KDF: string = 'kdf';
const KEY_ITERATIONS: string = 'iterations';
const KEY_KDF_MEMORY: string = 'kdfMemory';
const KEY_KDF_PARALLELISM: string = 'kdfParallelism';
const KEY_ENC_USER_KEY: string = 'encUserKey';
const KEY_ENC_REFRESH: string = 'encRefreshToken';
const KEY_NAME: string = 'userName';
const KEY_AUTO_LOCK: string = 'autoLockMinutes';
const KEY_CLIP_CLEAR: string = 'clipboardClearSeconds';
const KEY_NOTIFY_KEEP: string = 'notifyKeepSeconds';
const KEY_FLOAT_BALL: string = 'floatBallEnabled';
const KEY_SORT_MODE: string = 'sortMode';
const KEY_BIO_BLOB: string = 'bioUserKeyBlob';
const KEY_BIO_FINGERPRINT: string = 'bioFingerprintEnabled';
const KEY_BIO_FACE: string = 'bioFaceEnabled';
const KEY_LOCAL_MODE: string = 'localMode';

/** 本地模式的保险库文件：密钥材料 + 与服务器同构的密文条目 */
interface LocalVaultFile {
  version: number;
  /** PBKDF2 盐（base64），本地模式不使用邮箱，用随机盐代替 */
  salt: string;
  kdf: number;
  iterations: number;
  /** 账号密钥（用主密码派生的密钥加密） */
  encUserKey: string;
  ciphers: SyncCipher[];
  folders: SyncFolder[];
  savedAt: number;
}

interface CachePayload {
  server: string;
  email: string;
  savedAt: number;
  raw: string;
}

class VaultStoreImpl {
  ready: boolean = false;
  hasAccount: boolean = false;

  server: string = '';
  email: string = '';
  userName: string = '';
  deviceId: string = '';
  kdf: number = 0;
  iterations: number = 600000;
  /** Argon2id 的内存（KiB）与并行度，仅 kdf=2 时有效 */
  kdfMemory: number = 64;
  kdfParallelism: number = 4;
  /** 自动锁定分钟数；0 表示从不 */
  autoLockMinutes: number = 5;
  /** 复制后自动清空剪贴板的秒数；0 表示从不清除 */
  clipboardClearSeconds: number = 30;
  /** 「复制密码」通知的保留秒数（30 / 40 / 50） */
  notifyKeepSeconds: number = 30;
  /** 复制用户名后是否用闪控球提示（默认关闭） */
  floatBallEnabled: boolean = true;
  /** 列表排序方式：name | created | updated */
  sortMode: string = 'name';
  /** 指纹解锁是否开启 */
  bioFingerprint: boolean = false;
  /** 面容解锁是否开启 */
  bioFace: boolean = false;

  /** 任意一种生物识别是否开启 */
  get bioEnabled(): boolean {
    return this.bioFingerprint || this.bioFace;
  }

  accessToken: string = '';
  refreshToken: string = '';
  userKey: SymmetricCryptoKey | null = null;

  /** 正常条目 */
  items: VaultItem[] = [];
  /** 回收站 */
  trash: VaultItem[] = [];
  folders: VaultFolder[] = [];
  lastSyncAt: number = 0;
  syncing: boolean = false;
  /** 检测到服务器账号密钥已轮换（需用户重新登录） */
  keyRotated: boolean = false;
  /** 演示模式：使用内置样例数据，不联网 */
  demo: boolean = false;
  /** 本地模式：数据只存在本机，不需要服务器 */
  localMode: boolean = false;
  private localCiphers: SyncCipher[] = [];
  private localFolders: SyncFolder[] = [];
  private localSalt: string = '';
  private localEncUserKey: string = '';

  private prefs: preferences.Preferences | null = null;
  private appCtx: common.UIAbilityContext | null = null;
  private cacheDir: string = '';
  private deviceName: string = 'HarmonyOS';

  /** 供文件选择器使用（import/export） */
  appContext(): common.UIAbilityContext | null {
    return this.appCtx;
  }

  get unlocked(): boolean {
    return this.userKey !== null;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    this.appCtx = context;
    await CertPinning.init(context);
    this.cacheDir = context.filesDir;
    this.prefs = await preferences.getPreferences(context, PREFS_NAME);
    this.server = this.prefs.getSync(KEY_SERVER, '') as string;
    this.email = this.prefs.getSync(KEY_EMAIL, '') as string;
    this.userName = this.prefs.getSync(KEY_NAME, '') as string;
    this.kdf = this.prefs.getSync(KEY_KDF, 0) as number;
    this.iterations = this.prefs.getSync(KEY_ITERATIONS, 600000) as number;
    this.kdfMemory = this.prefs.getSync(KEY_KDF_MEMORY, 64) as number;
    this.kdfParallelism = this.prefs.getSync(KEY_KDF_PARALLELISM, 4) as number;
    this.autoLockMinutes = this.prefs.getSync(KEY_AUTO_LOCK, 5) as number;
    this.clipboardClearSeconds = this.prefs.getSync(KEY_CLIP_CLEAR, 30) as number;
    this.notifyKeepSeconds = this.prefs.getSync(KEY_NOTIFY_KEEP, 30) as number;
    this.floatBallEnabled = this.prefs.getSync(KEY_FLOAT_BALL, true) as boolean;
    this.sortMode = this.prefs.getSync(KEY_SORT_MODE, 'name') as string;
    this.bioFingerprint = this.prefs.getSync(KEY_BIO_FINGERPRINT, false) as boolean;
    this.bioFace = this.prefs.getSync(KEY_BIO_FACE, false) as boolean;
    this.deviceId = this.prefs.getSync(KEY_DEVICE_ID, '') as string;
    if (this.deviceId.length === 0) {
      this.deviceId = util.generateRandomUUID(true);
      await this.prefs.put(KEY_DEVICE_ID, this.deviceId);
      await this.prefs.flush();
    }
    this.localMode = this.prefs.getSync(KEY_LOCAL_MODE, false) as boolean;
    const encUserKey: string = this.prefs.getSync(KEY_ENC_USER_KEY, '') as string;
    if (this.localMode) {
      this.hasAccount = encUserKey.length > 0 && this.localExists();
    } else {
      this.hasAccount = encUserKey.length > 0 && this.server.length > 0 && this.email.length > 0;
    }
    this.ready = true;
  }

  /** 退出本机模式：清掉本机保险库文件与相关状态，避免和服务器账号串用 */
  private async leaveLocalMode(): Promise<void> {
    if (!this.localMode) {
      return;
    }
    this.localMode = false;
    this.localSalt = '';
    this.localEncUserKey = '';
    this.localCiphers = [];
    this.localFolders = [];
    try {
      if (fs.accessSync(this.localPath())) {
        fs.unlinkSync(this.localPath());
      }
    } catch (e) {
      // 文件不存在或删除失败都不影响后续连接服务器
    }
    if (this.prefs !== null) {
      await this.prefs.put(KEY_LOCAL_MODE, false);
      await this.prefs.put(KEY_ENC_USER_KEY, '');
      await this.prefs.put(KEY_ENC_REFRESH, '');
      await this.prefs.flush();
    }
    this.refreshToken = '';
  }

  /** 本地模式：创建只存在本机的保险库（主密码仅用于本机加解密） */
  async createLocalVault(password: string): Promise<void> {
    if (this.prefs === null) {
      throw new Error('本地存储未就绪');
    }
    if (password.length < 8) {
      throw new Error('主密码至少 8 位');
    }
    const salt: string = Bytes.b64(Bytes.random(16));
    const kdf: number = 0;
    const iterations: number = LOCAL_ITERATIONS;
    const masterKey: Uint8Array = await deriveMasterKey(password, salt, kdf, iterations);
    const stretched: SymmetricCryptoKey = await stretchMasterKey(masterKey);
    const userKey: SymmetricCryptoKey = new SymmetricCryptoKey(Bytes.random(64));
    const encUserKey: string = await encryptUserKey(userKey, stretched);
    this.localSalt = salt;
    this.localEncUserKey = encUserKey;
    this.localCiphers = [];
    this.localFolders = [];
    await this.writeLocalFile();
    this.localMode = true;
    this.server = '';
    this.email = '';
    this.userName = '本机保险库';
    // 本机库不继承服务器会话
    this.accessToken = '';
    this.refreshToken = '';
    this.kdf = kdf;
    this.iterations = iterations;
    await this.prefs.put(KEY_LOCAL_MODE, true);
    await this.prefs.put(KEY_SERVER, '');
    await this.prefs.put(KEY_EMAIL, '');
    await this.prefs.put(KEY_NAME, this.userName);
    await this.prefs.put(KEY_KDF, kdf);
    await this.prefs.put(KEY_ITERATIONS, iterations);
    await this.prefs.put(KEY_KDF_MEMORY, this.kdfMemory);
    await this.prefs.put(KEY_KDF_PARALLELISM, this.kdfParallelism);
    await this.prefs.put(KEY_ENC_USER_KEY, encUserKey);
    await this.prefs.put(KEY_ENC_REFRESH, '');
    await this.prefs.flush();
    this.userKey = userKey;
    this.accessToken = '';
    this.refreshToken = '';
    this.items = [];
    this.trash = [];
    this.folders = [];
    this.lastSyncAt = Date.now();
    this.hasAccount = true;
  }

  /**
   * 本地模式：修改主密码。
   * 先用旧密码解出账号密钥 → 换新盐重新派生并加密同一把账号密钥 → 写回文件与偏好。
   * 数据密文不用重新加密（条目都是用账号密钥加密的，账号密钥本身没变）。
   */
  async changeLocalPassword(oldPassword: string, newPassword: string): Promise<void> {
    if (!this.localMode) {
      throw new Error('服务器模式请到网页端修改主密码');
    }
    if (this.prefs === null) {
      throw new Error('本地存储未就绪');
    }
    if (newPassword.length < 8) {
      throw new Error('新主密码至少 8 位');
    }
    if (newPassword === oldPassword) {
      throw new Error('新主密码不能与当前主密码相同');
    }
    await this.readLocalFile();
    const oldMaster: Uint8Array = await deriveMasterKey(oldPassword, this.localSalt,
      this.kdf, this.iterations);
    const oldStretched: SymmetricCryptoKey = await stretchMasterKey(oldMaster);
    let userKey: SymmetricCryptoKey;
    try {
      userKey = await decryptUserKey(this.localEncUserKey, oldStretched);
    } catch (e) {
      throw new Error('当前主密码不正确');
    }
    const salt: string = Bytes.b64(Bytes.random(16));
    const iterations: number = LOCAL_ITERATIONS;
    const newMaster: Uint8Array = await deriveMasterKey(newPassword, salt, 0, iterations);
    const newStretched: SymmetricCryptoKey = await stretchMasterKey(newMaster);
    const encUserKey: string = await encryptUserKey(userKey, newStretched);
    this.localSalt = salt;
    this.kdf = 0;
    this.iterations = iterations;
    this.localEncUserKey = encUserKey;
    this.userKey = userKey;
    await this.writeLocalFile();
    await this.prefs.put(KEY_ENC_USER_KEY, encUserKey);
    await this.prefs.put(KEY_KDF, this.kdf);
    await this.prefs.put(KEY_ITERATIONS, iterations);
    await this.prefs.flush();
  }

  private localPath(): string {
    return `${this.cacheDir}/${LOCAL_FILE}`;
  }

  private localExists(): boolean {
    try {
      return fs.accessSync(this.localPath());
    } catch (e) {
      return false;
    }
  }

  /** 把内存里的密文条目写回本地文件 */
  private async writeLocalFile(): Promise<void> {
    const payload: LocalVaultFile = {
      version: 1,
      salt: this.localSalt,
      kdf: this.kdf,
      iterations: this.iterations,
      encUserKey: this.localEncUserKey,
      ciphers: this.localCiphers,
      folders: this.localFolders,
      savedAt: Date.now()
    };
    const file: fs.File = fs.openSync(this.localPath(),
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, JSON.stringify(payload));
    fs.closeSync(file);
  }

  /** 读本地文件到内存（解锁、同步、每次增删改前都会调用） */
  private async readLocalFile(): Promise<void> {
    try {
      const text: string = fs.readTextSync(this.localPath());
      const payload: LocalVaultFile = JSON.parse(text) as LocalVaultFile;
      this.localSalt = payload.salt;
      this.kdf = payload.kdf;
      this.iterations = payload.iterations;
      this.localEncUserKey = payload.encUserKey;
      this.localCiphers = payload.ciphers === undefined || payload.ciphers === null ? [] : payload.ciphers;
      this.localFolders = payload.folders === undefined || payload.folders === null ? [] : payload.folders;
    } catch (e) {
      throw new Error('本机保险库文件读取失败');
    }
  }

  /** 本地模式：把密文重新解密进内存（等价于服务器模式的 sync） */
  private async refreshLocal(): Promise<void> {
    await this.readLocalFile();
    const response: SyncResponse = { ciphers: this.localCiphers, folders: this.localFolders };
    this.applySync(response);
    this.lastSyncAt = Date.now();
  }

  /** 本地新建/更新条目：按服务器同一套 EncString 形式加密后落盘 */
  private async saveLocalDraft(draft: CipherDraft): Promise<void> {
    if (this.userKey === null) {
      throw new Error('请先解锁保险库');
    }
    await this.readLocalFile();
    const key: SymmetricCryptoKey = this.userKey;
    const now: string = new Date().toISOString();
    let index: number = -1;
    for (let i = 0; i < this.localCiphers.length; i++) {
      if (this.localCiphers[i].id === draft.id) {
        index = i;
        break;
      }
    }
    const existing: SyncCipher | null = index >= 0 ? this.localCiphers[index] : null;
    let login: LoginData | null = null;
    let card: CardData | null = null;
    let identity: IdentityData | null = null;
    let secureNote: Object | null = null;
    if (draft.type === CipherType.Login) {
      const uri: string | null = await encryptNullable(draft.uri, key);
      let uris: LoginUriData[] | null = null;
      if (draft.uri.trim().length > 0) {
        uris = [{ match: null, uri: uri }];
      }
      login = {
        username: await encryptNullable(draft.username, key),
        password: await encryptNullable(draft.password, key),
        totp: await encryptNullable(draft.totp, key),
        uri: uri,
        uris: uris
      };
    } else if (draft.type === CipherType.Card) {
      card = {
        cardholderName: await encryptNullable(draft.card.cardholderName, key),
        brand: await encryptNullable(draft.card.brand, key),
        number: await encryptNullable(draft.card.number, key),
        expMonth: await encryptNullable(draft.card.expMonth, key),
        expYear: await encryptNullable(draft.card.expYear, key),
        code: await encryptNullable(draft.card.code, key)
      };
    } else if (draft.type === CipherType.Identity) {
      identity = {
        title: await encryptNullable(draft.identity.title, key),
        firstName: await encryptNullable(draft.identity.firstName, key),
        lastName: await encryptNullable(draft.identity.lastName, key),
        email: await encryptNullable(draft.identity.email, key),
        phone: await encryptNullable(draft.identity.phone, key),
        address1: await encryptNullable(draft.identity.address, key),
        city: await encryptNullable(draft.identity.city, key),
        postalCode: await encryptNullable(draft.identity.postalCode, key),
        country: await encryptNullable(draft.identity.country, key)
      };
    }
    let fields: FieldData[] | null = null;
    if (draft.fields.length > 0) {
      const list: FieldData[] = [];
      for (let i = 0; i < draft.fields.length; i++) {
        const f: VaultField = draft.fields[i];
        if (f.name.trim().length === 0 && f.value.length === 0) {
          continue;
        }
        list.push({
          name: await encryptNullable(f.name, key),
          value: await encryptNullable(f.value, key),
          type: f.type
        });
      }
      fields = list.length > 0 ? list : null;
    }
    const cipher: SyncCipher = {
      id: existing !== null ? existing.id : util.generateRandomUUID(false),
      type: draft.type,
      name: await encryptToString(draft.name.trim(), key),
      notes: await encryptNullable(draft.notes, key),
      favorite: draft.favorite,
      folderId: draft.folderId.length > 0 ? draft.folderId : null,
      login: login,
      card: card,
      identity: identity,
      secureNote: secureNote,
      fields: fields,
      revisionDate: now,
      creationDate: existing !== null && existing.creationDate !== undefined &&
        existing.creationDate !== null ? existing.creationDate : now,
      deletedDate: existing !== null && existing.deletedDate !== undefined &&
        existing.deletedDate !== null ? existing.deletedDate : null
    };
    if (index >= 0) {
      this.localCiphers[index] = cipher;
    } else {
      this.localCiphers.push(cipher);
    }
    await this.writeLocalFile();
    await this.refreshLocal();
  }

  private async saveLocalCiphers(): Promise<void> {
    await this.writeLocalFile();
    await this.refreshLocal();
  }

  /** 本地模式：改某条密文的若干字段（收藏 / 回收站 / 恢复） */
  private async patchLocalCipher(id: string, favorite: boolean | null,
    deleted: boolean | null): Promise<void> {
    await this.readLocalFile();
    for (let i = 0; i < this.localCiphers.length; i++) {
      const c: SyncCipher = this.localCiphers[i];
      if (c.id !== id) {
        continue;
      }
      if (favorite !== null) {
        c.favorite = favorite;
      }
      if (deleted !== null) {
        c.deletedDate = deleted ? new Date().toISOString() : null;
      }
      c.revisionDate = new Date().toISOString();
      this.localCiphers[i] = c;
      break;
    }
    await this.saveLocalCiphers();
  }

  /** 本地模式：彻底删除 */
  private async purgeLocalCipher(id: string): Promise<void> {
    await this.readLocalFile();
    const rest: SyncCipher[] = [];
    for (let i = 0; i < this.localCiphers.length; i++) {
      if (this.localCiphers[i].id !== id) {
        rest.push(this.localCiphers[i]);
      }
    }
    this.localCiphers = rest;
    await this.saveLocalCiphers();
  }

  async configure(serverInput: string, emailInput: string): Promise<string> {
    const server: string = Api.normalizeServer(serverInput);
    const email: string = emailInput.trim();
    // 之前可能是「本机保险库」：切到服务器账号前必须清掉本机模式，
    // 否则解锁仍走本机分支，用服务器密码去解本机密钥，提示"主密码错误"。
    await this.leaveLocalMode();
    if (email.length === 0) {
      throw new Error('请填写账号邮箱');
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new Error('邮箱格式不正确，例如 you@example.com');
    }
    const version: string = await Api.probeServer(server);
    // 首次连接记录证书指纹；之后证书变化会抛 CERT_CHANGED，由连接页让用户确认
    await CertPinning.verify(server);
    let prelogin: PreloginResponse;
    try {
      prelogin = await Api.prelogin(server, email);
    } catch (e) {
      const status: number = (e as Api.ApiError).status;
      const text: string = Api.errorMessage(e);
      if (status === 0) {
        throw new Error(text);          // 网络类错误，保留“无法连接服务器…”
      }
      if (status === 400 || status === 404) {
        throw new Error('该邮箱未在此服务器注册，请检查邮箱与服务器地址是否正确');
      }
      throw new Error(Api.friendlyAuthError(text));
    }
    const kdf: number = prelogin.kdf === undefined || prelogin.kdf === null ? 0 : prelogin.kdf;
    const iterations: number = prelogin.kdfIterations === undefined || prelogin.kdfIterations === null ?
      600000 : prelogin.kdfIterations;
    const memory: number = prelogin.kdfMemory === undefined || prelogin.kdfMemory === null ?
      64 : prelogin.kdfMemory;
    const parallelism: number = prelogin.kdfParallelism === undefined || prelogin.kdfParallelism === null ?
      4 : prelogin.kdfParallelism;
    this.server = server;
    this.email = email;
    this.kdf = kdf;
    this.iterations = iterations;
    this.kdfMemory = memory;
    this.kdfParallelism = parallelism;
    await this.persistAccount();
    return version;
  }

  async login(password: string): Promise<void> {
    if (this.server.length === 0 || this.email.length === 0) {
      throw new Error('尚未配置服务器，请先完成服务器设置');
    }
    if (password.length === 0) {
      throw new Error('请输入主密码');
    }
    const masterKey: Uint8Array = await deriveMasterKey(password, this.email, this.kdf, this.iterations, this.kdfMemory, this.kdfParallelism);
    const hashed: string = await hashMasterPassword(masterKey, password);
    const stretched: SymmetricCryptoKey = await stretchMasterKey(masterKey);
    let token: TokenResponse;
    try {
      token = await Api.loginWithPassword(this.server, this.email, hashed,
        this.deviceId, this.deviceName);
    } catch (e) {
      throw new Error(Api.friendlyAuthError(Api.errorMessage(e)));
    }
    if (token.KdfIterations !== undefined && token.KdfIterations !== null && token.KdfIterations > 0) {
      this.iterations = token.KdfIterations;
    }
    const encryptedKey: string = token.Key === undefined || token.Key === null ? '' : token.Key;
    if (encryptedKey.length === 0) {
      throw new Error('服务器未返回账号密钥，可能是账号尚未完成初始化');
    }
    this.userKey = await decryptUserKey(encryptedKey, stretched);
    this.accessToken = token.access_token === undefined || token.access_token === null ? '' : token.access_token;
    this.refreshToken = token.refresh_token === undefined || token.refresh_token === null ? '' : token.refresh_token;
    if (this.accessToken.length === 0) {
      throw new Error('登录成功但未获取到访问令牌');
    }
    await this.persistSession(this.userKey, stretched, this.refreshToken);
    await this.sync();
  }

  async unlock(password: string): Promise<void> {
    if (this.prefs === null) {
      throw new Error('本地存储未就绪');
    }
    if (this.localMode) {
      await this.readLocalFile();
      if (this.localEncUserKey.length === 0) {
        throw new Error('本机没有可解锁的保险库');
      }
      const localMaster: Uint8Array = await deriveMasterKey(password, this.localSalt,
        this.kdf, this.iterations);
      const localStretched: SymmetricCryptoKey = await stretchMasterKey(localMaster);
      try {
        this.userKey = await decryptUserKey(this.localEncUserKey, localStretched);
      } catch (e) {
        this.userKey = null;
        throw new Error('主密码错误，请重试');
      }
      await this.refreshLocal();
      return;
    }
    const encUserKey: string = this.prefs.getSync(KEY_ENC_USER_KEY, '') as string;
    if (encUserKey.length === 0) {
      throw new Error('本机没有可解锁的账号数据');
    }
    const masterKey: Uint8Array = await deriveMasterKey(password, this.email, this.kdf, this.iterations, this.kdfMemory, this.kdfParallelism);
    const stretched: SymmetricCryptoKey = await stretchMasterKey(masterKey);
    try {
      this.userKey = await decryptUserKey(encUserKey, stretched);
    } catch (e) {
      this.userKey = null;
      throw new Error('主密码错误，请重试');
    }
    await this.activateSession();
  }

  /** 生物识别解锁：kind = 'fingerprint' | 'face'，先过系统认证再用 HUKS 解出账号密钥 */
  async unlockWithBiometric(kind: string): Promise<void> {
    if (this.prefs === null) {
      throw new Error('本地存储未就绪');
    }
    const enabled: boolean = kind === 'face' ? this.bioFace : this.bioFingerprint;
    if (!enabled) {
      throw new Error(kind === 'face' ? '未开启面容解锁' : '未开启指纹解锁');
    }
    const passed: boolean = kind === 'face' ?
      await Biometric.authenticateFace('解锁保险库') :
      await Biometric.authenticateFingerprint('解锁保险库');
    if (!passed) {
      throw new Error(Biometric.lastError.length > 0 ? Biometric.lastError : '生物识别未通过');
    }
    const blob: string = this.prefs.getSync(KEY_BIO_BLOB, '') as string;
    if (blob.length === 0) {
      throw new Error('生物识别密钥已失效，请用主密码解锁');
    }
    const raw: Uint8Array = await unwrapUserKey(blob);
    this.userKey = new SymmetricCryptoKey(raw);
    await this.activateSession();
  }

  /** 开启某一种生物识别（需已解锁 + 通过该类型的一次认证） */
  async enableBiometric(kind: string): Promise<void> {
    if (this.prefs === null) {
      throw new Error('本地存储未就绪');
    }
    if (this.userKey === null) {
      throw new Error('请先解锁保险库');
    }
    const available: boolean = kind === 'face' ?
      Biometric.faceAvailable() : Biometric.fingerprintAvailable();
    if (!available) {
      throw new Error(kind === 'face' ? Biometric.faceReason() : Biometric.fingerprintReason());
    }
    const passed: boolean = kind === 'face' ?
      await Biometric.authenticateFace('开启面容解锁') :
      await Biometric.authenticateFingerprint('开启指纹解锁');
    if (!passed) {
      throw new Error(Biometric.lastError.length > 0 ? Biometric.lastError : '认证未通过，未开启');
    }
    // 两种方式共用同一份包裹（同一把 HUKS 密钥），只需生成一次
    let blob: string = this.prefs.getSync(KEY_BIO_BLOB, '') as string;
    if (blob.length === 0) {
      blob = await wrapUserKey(this.userKey.key);
      await this.prefs.put(KEY_BIO_BLOB, blob);
    }
    if (kind === 'face') {
      this.bioFace = true;
      await this.prefs.put(KEY_BIO_FACE, true);
    } else {
      this.bioFingerprint = true;
      await this.prefs.put(KEY_BIO_FINGERPRINT, true);
    }
    await this.prefs.flush();
  }

  /** 关闭某一种生物识别；两种都关掉时清除包裹并删除 HUKS 密钥 */
  async disableBiometric(kind: string): Promise<void> {
    if (kind === 'face') {
      this.bioFace = false;
    } else {
      this.bioFingerprint = false;
    }
    if (this.prefs !== null) {
      await this.prefs.put(KEY_BIO_FACE, this.bioFace);
      await this.prefs.put(KEY_BIO_FINGERPRINT, this.bioFingerprint);
      if (!this.bioEnabled) {
        await this.prefs.put(KEY_BIO_BLOB, '');
      }
      await this.prefs.flush();
    }
    if (!this.bioEnabled) {
      await deleteBioKey();
    }
  }

  /** 账号密钥到手后的公共收尾：恢复访问令牌、读缓存、同步 */
  private async activateSession(): Promise<void> {
    if (this.prefs === null || this.userKey === null) {
      return;
    }
    if (this.localMode) {
      await this.refreshLocal();
      return;
    }
    const encRefresh: string = this.prefs.getSync(KEY_ENC_REFRESH, '') as string;
    this.refreshToken = encRefresh.length === 0 ? '' : await decryptToString(encRefresh, this.userKey);
    if (this.refreshToken.length > 0) {
      try {
        const token: TokenResponse = await Api.refreshToken(this.server, this.refreshToken,
          this.deviceId, this.deviceName);
        this.accessToken = token.access_token === undefined || token.access_token === null ?
          '' : token.access_token;
        const rotated: string = token.refresh_token === undefined || token.refresh_token === null ?
          '' : token.refresh_token;
        if (rotated.length > 0 && rotated !== this.refreshToken) {
          this.refreshToken = rotated;
          await this.persistRefresh(this.refreshToken);
        }
        // 服务器返回了新的账号密钥：说明密钥已轮换，本地旧密钥作废
        if (this.prefs !== null) {
          const serverKey: string = token.Key === undefined || token.Key === null ? '' : token.Key;
          const storedKey: string = this.prefs.getSync(KEY_ENC_USER_KEY, '') as string;
          if (serverKey.length > 0 && storedKey.length > 0 && serverKey !== storedKey) {
            await this.markKeyRotated();
            return;
          }
        }
      } catch (e) {
        this.accessToken = '';
      }
    }
    await this.loadCache();
    if (this.accessToken.length > 0) {
      try {
        await this.sync();
      } catch (e) {
        // 同步失败不影响解锁
      }
    }
  }

  async sync(): Promise<void> {
    if (this.demo) {
      throw new Error('当前是演示模式，请先连接真实服务器');
    }
    if (this.localMode) {
      if (this.userKey === null) {
        throw new Error('保险库处于锁定状态');
      }
      await this.refreshLocal();
      return;
    }
    if (this.accessToken.length === 0) {
      throw new Error('会话已过期，请重新解锁');
    }
    if (this.userKey === null) {
      throw new Error('保险库处于锁定状态');
    }
    this.syncing = true;
    try {
      const response: SyncResponse = await Api.fetchSync(this.server, this.accessToken, this.deviceId);
      const rotated: boolean = this.applySync(response);
      if (rotated) {
        await this.markKeyRotated();
        return;
      }
      await this.writeCache(JSON.stringify(response));
      this.lastSyncAt = Date.now();
    } finally {
      this.syncing = false;
    }
  }

  /** 把 sync 结果解密落进内存（正常条目 / 回收站分开） */
  private applySync(response: SyncResponse): boolean {
    const key: SymmetricCryptoKey = this.userKey as SymmetricCryptoKey;
    const ciphers: SyncCipher[] = response.ciphers === undefined || response.ciphers === null ?
      [] : response.ciphers;
    const active: VaultItem[] = [];
    const trashed: VaultItem[] = [];
    let broken: number = 0;
    for (let i = 0; i < ciphers.length; i++) {
      const cipher: SyncCipher = ciphers[i];
      const deleted: boolean = cipher.deletedDate !== undefined && cipher.deletedDate !== null &&
        cipher.deletedDate.length > 0;
      const item: VaultItem = this.decryptCipher(cipher, key, deleted);
      if (item.broken) {
        broken++;
      }
      if (deleted) {
        trashed.push(item);
      } else {
        active.push(item);
      }
    }
    // 只按名称排序（名称相同再按 id），不能把"收藏"放进排序键，
    // 否则一收藏条目就跳到列表最前面，打乱用户的浏览顺序
    const sortFn = (a: VaultItem, b: VaultItem): number => {
      const an: string = a.name.toLowerCase();
      const bn: string = b.name.toLowerCase();
      if (an !== bn) {
        return an < bn ? -1 : 1;
      }
      return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
    };
    // 超过 80% 的条目解密失败，基本可以判定账号密钥已被轮换，
    // 而不是个别条目损坏（个别损坏仍按 broken 展示）
    const total: number = active.length + trashed.length;
    if (total >= 5 && broken * 5 >= total * 4) {
      return true;
    }
    active.sort(sortFn);
    trashed.sort(sortFn);
    this.items = active;
    this.trash = trashed;
    this.folders = this.decryptFolders(response, key);
    return false;
  }

  /** 标记密钥轮换并清掉本地一切会话密钥（保留服务器地址/邮箱，方便重新登录） */
  private async markKeyRotated(): Promise<void> {
    this.keyRotated = true;
    this.lock();
    this.bioFingerprint = false;
    this.bioFace = false;
    try {
      await deleteBioKey();
    } catch (e) {
      // 忽略
    }
    this.deleteCache();
    if (this.prefs !== null) {
      await this.prefs.put(KEY_ENC_USER_KEY, '');
      await this.prefs.put(KEY_ENC_REFRESH, '');
      await this.prefs.flush();
    }
  }

  /** 用户已看到提示后清除标记 */
  clearKeyRotated(): void {
    this.keyRotated = false;
  }

  /** 解密单个条目（含卡片/身份/自定义字段/密码历史） */
  private decryptCipher(cipher: SyncCipher, key: SymmetricCryptoKey, deleted: boolean): VaultItem {
    const item: VaultItem = {
      id: cipher.id,
      type: cipher.type,
      name: '',
      username: '',
      password: '',
      totp: '',
      uri: '',
      notes: '',
      favorite: cipher.favorite === true,
      folderId: cipher.folderId === undefined || cipher.folderId === null ? '' : cipher.folderId,
      revisionDate: cipher.revisionDate === undefined || cipher.revisionDate === null ?
        '' : cipher.revisionDate,
      creationDate: cipher.creationDate === undefined || cipher.creationDate === null ?
        '' : cipher.creationDate,
      broken: false,
      deleted: deleted,
      card: null,
      identity: null,
      fields: null,
      history: null
    };
    // Bitwarden 新版条目可能带「条目自有密钥」(cipher.key)：先解开它，再用它解字段
    let itemKey: SymmetricCryptoKey = key;
    const rawItemKey: string = cipher.key === undefined || cipher.key === null ? '' : cipher.key;
    if (rawItemKey.length > 0) {
      try {
        itemKey = new SymmetricCryptoKey(decryptToBytesSync(rawItemKey, key));
      } catch (e) {
        itemKey = key;
      }
    }
    try {
      item.name = this.decryptSync(cipher.name, itemKey);
      item.notes = this.decryptSync(cipher.notes, itemKey);
      if (cipher.login !== undefined && cipher.login !== null) {
        item.username = this.decryptSync(cipher.login.username, itemKey);
        item.password = this.decryptSync(cipher.login.password, itemKey);
        item.totp = this.decryptSync(cipher.login.totp, itemKey);
        const uris = cipher.login.uris;
        if (uris !== undefined && uris !== null && uris.length > 0) {
          item.uri = this.decryptSync(uris[0].uri, itemKey);
        } else {
          item.uri = this.decryptSync(cipher.login.uri, itemKey);
        }
      }
      if (cipher.card !== undefined && cipher.card !== null) {
        const card: VaultCard = {
          cardholderName: this.decryptSync(cipher.card.cardholderName, itemKey),
          brand: this.decryptSync(cipher.card.brand, itemKey),
          number: this.decryptSync(cipher.card.number, itemKey),
          expMonth: this.decryptSync(cipher.card.expMonth, itemKey),
          expYear: this.decryptSync(cipher.card.expYear, itemKey),
          code: this.decryptSync(cipher.card.code, itemKey)
        };
        item.card = card;
      }
      if (cipher.identity !== undefined && cipher.identity !== null) {
        const identity: VaultIdentity = {
          title: this.decryptSync(cipher.identity.title, itemKey),
          firstName: this.decryptSync(cipher.identity.firstName, itemKey),
          lastName: this.decryptSync(cipher.identity.lastName, itemKey),
          email: this.decryptSync(cipher.identity.email, itemKey),
          phone: this.decryptSync(cipher.identity.phone, itemKey),
          address: this.decryptSync(cipher.identity.address1, itemKey),
          city: this.decryptSync(cipher.identity.city, itemKey),
          postalCode: this.decryptSync(cipher.identity.postalCode, itemKey),
          country: this.decryptSync(cipher.identity.country, itemKey)
        };
        item.identity = identity;
      }
      const fields = cipher.fields;
      if (fields !== undefined && fields !== null && fields.length > 0) {
        const list: VaultField[] = [];
        for (let i = 0; i < fields.length; i++) {
          const field: VaultField = {
            name: this.decryptSync(fields[i].name, itemKey),
            value: this.decryptSync(fields[i].value, itemKey),
            type: fields[i].type
          };
          list.push(field);
        }
        item.fields = list;
      }
      const history = cipher.passwordHistory;
      if (history !== undefined && history !== null && history.length > 0) {
        const passwords: string[] = [];
        for (let i = 0; i < history.length; i++) {
          const entry: Record<string, Object> = history[i] as Record<string, Object>;
          const encrypted: Object | undefined = entry['password'];
          if (encrypted !== undefined && encrypted !== null) {
            const plain: string = this.decryptSync(encrypted.toString(), itemKey);
            if (plain.length > 0) {
              passwords.push(plain);
            }
          }
        }
        item.history = passwords;
      }
      if (item.name.length === 0) {
        item.name = '(无标题条目)';
        item.broken = true;
      }
    } catch (e) {
      item.broken = true;
      if (item.name.length === 0) {
        item.name = '(无法解密)';
      }
    }
    return item;
  }

  private decryptFolders(response: SyncResponse, key: SymmetricCryptoKey): VaultFolder[] {
    const result: VaultFolder[] = [];
    const folders = response.folders;
    if (folders === undefined || folders === null) {
      return result;
    }
    for (let i = 0; i < folders.length; i++) {
      result.push({ id: folders[i].id, name: this.decryptSync(folders[i].name, key) });
    }
    return result;
  }

  /** 同步版解密：失败返回空串，避免单条脏数据中断整体渲染 */
  private decryptSync(cipher: string | null | undefined, key: SymmetricCryptoKey): string {
    if (cipher === null || cipher === undefined || cipher.toString().length === 0) {
      return '';
    }
    try {
      return decryptToStringSync(cipher.toString(), key);
    } catch (e) {
      return '';
    }
  }

  /** 新建或更新条目（由编辑器提交的明文草稿） */
  async saveDraft(draft: CipherDraft): Promise<void> {
    if (this.demo) {
      throw new Error('演示模式无法保存，请先连接真实服务器');
    }
    if (draft.name.trim().length === 0) {
      throw new Error('条目名称不能为空');
    }
    if (this.localMode) {
      if (this.userKey === null) {
        throw new Error('请先解锁保险库');
      }
      await this.saveLocalDraft(draft);
      return;
    }
    if (this.userKey === null || this.accessToken.length === 0) {
      throw new Error('请先解锁保险库');
    }
    const payload: CipherRequest = await this.buildRequest(draft);
    if (draft.id.length === 0) {
      await Api.createCipher(this.server, this.accessToken, this.deviceId, payload);
    } else {
      await Api.updateCipher(this.server, this.accessToken, this.deviceId, draft.id, payload);
    }
    await this.sync();

  }

  /** 明文草稿 -> 密文请求体 */
  private async buildRequest(draft: CipherDraft): Promise<CipherRequest> {
    const key: SymmetricCryptoKey = this.userKey as SymmetricCryptoKey;
    const name: string = await encryptToString(draft.name.trim(), key);
    const notes: string | null = await encryptNullable(draft.notes, key);
    let login: LoginRequest | null = null;
    let card: CardRequest | null = null;
    let identity: IdentityRequest | null = null;
    let secureNote: SecureNoteRequest | null = null;
    let fields: FieldRequest[] | null = null;

    if (draft.type === CipherType.Login) {
      const uri: string | null = await encryptNullable(draft.uri, key);
      let uris: LoginUriRequest[] | null = null;
      if (draft.uri.trim().length > 0) {
        uris = [{ match: null, uri: uri }];
      }
      login = {
        username: await encryptNullable(draft.username, key),
        password: await encryptNullable(draft.password, key),
        passwordRevisionDate: null,
        totp: await encryptNullable(draft.totp, key),
        uri: uri,
        uris: uris
      };
    } else if (draft.type === CipherType.Card) {
      card = {
        cardholderName: await encryptNullable(draft.card.cardholderName, key),
        brand: await encryptNullable(draft.card.brand, key),
        number: await encryptNullable(draft.card.number, key),
        expMonth: await encryptNullable(draft.card.expMonth, key),
        expYear: await encryptNullable(draft.card.expYear, key),
        code: await encryptNullable(draft.card.code, key)
      };
    } else if (draft.type === CipherType.Identity) {
      identity = {
        title: await encryptNullable(draft.identity.title, key),
        firstName: await encryptNullable(draft.identity.firstName, key),
        lastName: await encryptNullable(draft.identity.lastName, key),
        email: await encryptNullable(draft.identity.email, key),
        phone: await encryptNullable(draft.identity.phone, key),
        address1: await encryptNullable(draft.identity.address, key),
        city: await encryptNullable(draft.identity.city, key),
        postalCode: await encryptNullable(draft.identity.postalCode, key),
        country: await encryptNullable(draft.identity.country, key)
      };
    } else if (draft.type === CipherType.SecureNote) {
      secureNote = { type: 0 };
    }

    if (draft.fields.length > 0) {
      const list: FieldRequest[] = [];
      for (let i = 0; i < draft.fields.length; i++) {
        const f: VaultField = draft.fields[i];
        if (f.name.trim().length === 0 && f.value.length === 0) {
          continue;
        }
        list.push({
          name: await encryptNullable(f.name, key),
          value: await encryptNullable(f.value, key),
          type: f.type
        });
      }
      fields = list.length > 0 ? list : null;
    }

    const payload: CipherRequest = {
      type: draft.type,
      name: name,
      notes: notes,
      favorite: draft.favorite,
      folderId: draft.folderId.length > 0 ? draft.folderId : null,
      login: login,
      card: card,
      identity: identity,
      secureNote: secureNote,
      fields: fields,
      lastKnownRevisionDate: null
    };
    return payload;
  }

  /** 收藏 / 取消收藏（只发 partial 更新） */
  async setFavorite(item: VaultItem, favorite: boolean): Promise<void> {
    if (this.demo) {
      item.favorite = favorite;
      return;
    }
    if (this.localMode) {
      await this.patchLocalCipher(item.id, favorite, null);
      return;
    }
    if (this.accessToken.length === 0) {
      throw new Error('会话已过期，请重新解锁');
    }
    await Api.partialUpdateCipher(this.server, this.accessToken, this.deviceId, item.id,
      item.folderId.length > 0 ? item.folderId : null, favorite);
    await this.sync();
  }


  /** 移到回收站（软删除） */
  async trashItem(item: VaultItem): Promise<void> {
    if (this.demo) {
      throw new Error('演示模式不支持删除');
    }
    if (this.localMode) {
      await this.patchLocalCipher(item.id, null, true);
      return;
    }
    if (this.accessToken.length === 0) {
      throw new Error('会话已过期，请重新解锁');
    }
    await Api.trashCipher(this.server, this.accessToken, this.deviceId, item.id);
    await this.sync();
  }

  /** 从回收站恢复 */
  async restoreItem(item: VaultItem): Promise<void> {
    if (this.demo) {
      throw new Error('演示模式不支持恢复');
    }
    if (this.localMode) {
      await this.patchLocalCipher(item.id, null, false);
      return;
    }
    if (this.accessToken.length === 0) {
      throw new Error('会话已过期，请重新解锁');
    }
    await Api.restoreCipher(this.server, this.accessToken, this.deviceId, item.id);
    await this.sync();
  }

  /** 彻底删除（不可恢复） */
  async purgeItem(item: VaultItem): Promise<void> {
    if (this.demo) {
      throw new Error('演示模式不支持彻底删除');
    }
    if (this.localMode) {
      await this.purgeLocalCipher(item.id);
      return;
    }
    if (this.accessToken.length === 0) {
      throw new Error('会话已过期，请重新解锁');
    }
    await Api.purgeCipher(this.server, this.accessToken, this.deviceId, item.id);
    await this.sync();
  }

  /** 批量设置收藏状态（多个条目只同步一次） */
  async setFavorites(items: VaultItem[], favorite: boolean): Promise<void> {
    if (items.length === 0) {
      return;
    }
    if (this.demo) {
      for (let i = 0; i < items.length; i++) {
        items[i].favorite = favorite;
      }
      return;
    }
    if (this.localMode) {
      for (let i = 0; i < items.length; i++) {
        await this.patchLocalCipher(items[i].id, favorite, null);
      }
      return;
    }
    if (this.accessToken.length === 0) {
      throw new Error('会话已过期，请重新解锁');
    }
    for (let i = 0; i < items.length; i++) {
      const it: VaultItem = items[i];
      await Api.partialUpdateCipher(this.server, this.accessToken, this.deviceId, it.id,
        it.folderId.length > 0 ? it.folderId : null, favorite);
    }
    await this.sync();
  }

  /** 批量移到回收站 */
  async trashItems(items: VaultItem[]): Promise<void> {
    if (items.length === 0) {
      return;
    }
    if (this.demo) {
      throw new Error('演示模式不支持删除');
    }
    if (this.localMode) {
      for (let i = 0; i < items.length; i++) {
        await this.patchLocalCipher(items[i].id, null, true);
      }
      return;
    }
    if (this.accessToken.length === 0) {
      throw new Error('会话已过期，请重新解锁');
    }
    for (let i = 0; i < items.length; i++) {
      await Api.trashCipher(this.server, this.accessToken, this.deviceId, items[i].id);
    }
    await this.sync();
  }

  /** 批量从回收站恢复 */
  async restoreItems(items: VaultItem[]): Promise<void> {
    if (items.length === 0) {
      return;
    }
    if (this.demo) {
      throw new Error('演示模式不支持恢复');
    }
    if (this.localMode) {
      for (let i = 0; i < items.length; i++) {
        await this.patchLocalCipher(items[i].id, null, false);
      }
      return;
    }
    if (this.accessToken.length === 0) {
      throw new Error('会话已过期，请重新解锁');
    }
    for (let i = 0; i < items.length; i++) {
      await Api.restoreCipher(this.server, this.accessToken, this.deviceId, items[i].id);
    }
    await this.sync();
  }

  /** 批量彻底删除 */
  async purgeItems(items: VaultItem[]): Promise<void> {
    if (items.length === 0) {
      return;
    }
    if (this.demo) {
      throw new Error('演示模式不支持彻底删除');
    }
    if (this.localMode) {
      for (let i = 0; i < items.length; i++) {
        await this.purgeLocalCipher(items[i].id);
      }
      return;
    }
    if (this.accessToken.length === 0) {
      throw new Error('会话已过期，请重新解锁');
    }
    for (let i = 0; i < items.length; i++) {
      await Api.purgeCipher(this.server, this.accessToken, this.deviceId, items[i].id);
    }
    await this.sync();
  }

  /** 新建文件夹，返回新文件夹 id（失败抛错） */
  async createFolder(name: string): Promise<string> {
    if (this.demo) {
      throw new Error('演示模式不支持新建文件夹');
    }
    if (this.userKey === null) {
      throw new Error('请先解锁保险库');
    }
    const trimmed: string = name.trim();
    if (trimmed.length === 0) {
      throw new Error('文件夹名称不能为空');
    }
    const encrypted: string = await encryptToString(trimmed, this.userKey);
    if (this.localMode) {
      await this.readLocalFile();
      const folder: SyncFolder = { id: util.generateRandomUUID(false), name: encrypted };
      this.localFolders.push(folder);
      await this.saveLocalCiphers();
      return folder.id;
    }
    if (this.accessToken.length === 0) {
      throw new Error('请先解锁保险库');
    }
    const id: string = await Api.createFolder(this.server, this.accessToken, this.deviceId, encrypted);
    await this.sync();
    // 服务端没回 id 时按名字回查，保证调用方拿得到
    if (id.length > 0) {
      return id;
    }
    for (let i = 0; i < this.folders.length; i++) {
      if (this.folders[i].name === trimmed) {
        return this.folders[i].id;
      }
    }
    return '';
  }

  /** 文件夹改名 */
  async renameFolder(folder: VaultFolder, name: string): Promise<void> {
    if (this.demo) {
      throw new Error('演示模式不支持改名');
    }
    if (this.userKey === null) {
      throw new Error('请先解锁保险库');
    }
    if (name.trim().length === 0) {
      throw new Error('文件夹名称不能为空');
    }
    const encrypted: string = await encryptToString(name.trim(), this.userKey);
    if (this.localMode) {
      await this.readLocalFile();
      for (let i = 0; i < this.localFolders.length; i++) {
        if (this.localFolders[i].id === folder.id) {
          this.localFolders[i] = { id: folder.id, name: encrypted };
          break;
        }
      }
      await this.saveLocalCiphers();
      return;
    }
    if (this.accessToken.length === 0) {
      throw new Error('请先解锁保险库');
    }
    await Api.renameFolder(this.server, this.accessToken, this.deviceId, folder.id, encrypted);
    await this.sync();
  }

  /** 删除文件夹（其中的条目不删除） */
  async deleteFolder(folder: VaultFolder): Promise<void> {
    if (this.demo) {
      throw new Error('演示模式不支持删除文件夹');
    }
    if (this.localMode) {
      await this.readLocalFile();
      const kept: SyncFolder[] = [];
      for (let i = 0; i < this.localFolders.length; i++) {
        if (this.localFolders[i].id !== folder.id) {
          kept.push(this.localFolders[i]);
        }
      }
      this.localFolders = kept;
      for (let i = 0; i < this.localCiphers.length; i++) {
        if (this.localCiphers[i].folderId === folder.id) {
          this.localCiphers[i].folderId = null;
        }
      }
      await this.saveLocalCiphers();
      return;
    }
    if (this.accessToken.length === 0) {
      throw new Error('会话已过期，请重新解锁');
    }
    await Api.deleteFolder(this.server, this.accessToken, this.deviceId, folder.id);
    await this.sync();
  }

  /** 保存自动锁定设置（分钟，0 = 从不） */
  async setAutoLockMinutes(minutes: number): Promise<void> {
    this.autoLockMinutes = minutes;
    if (this.prefs !== null) {
      await this.prefs.put(KEY_AUTO_LOCK, minutes);
      await this.prefs.flush();
    }
  }

  /** 保存通知保留时长（秒） */
  async setFloatBallEnabled(enabled: boolean): Promise<void> {
    this.floatBallEnabled = enabled;
    if (this.prefs !== null) {
      await this.prefs.put(KEY_FLOAT_BALL, enabled);
      await this.prefs.flush();
    }
  }

  async setNotifyKeepSeconds(seconds: number): Promise<void> {
    this.notifyKeepSeconds = seconds;
    if (this.prefs !== null) {
      await this.prefs.put(KEY_NOTIFY_KEEP, seconds);
      await this.prefs.flush();
    }
  }

  /** 保存剪贴板自动清除设置（秒，0 = 从不清除），并同步给剪贴板模块 */
  async setClipboardClearSeconds(seconds: number): Promise<void> {
    this.clipboardClearSeconds = seconds;
    Clipboard.setAutoClearSeconds(seconds);
    if (this.prefs !== null) {
      await this.prefs.put(KEY_CLIP_CLEAR, seconds);
      await this.prefs.flush();
    }
  }

  /**
   * 校验主密码是否正确（完全离线，不联网、不改变当前登录状态）。
   * 原理：用输入的主密码重新派生密钥，能解开本机保存的账号密钥即为正确。
   * 演示模式没有主密码，直接放行。
   */
  async verifyMasterPassword(password: string): Promise<boolean> {
    if (this.demo) {
      return true;
    }
    if (password.length === 0) {
      return false;
    }
    try {
      let encKey: string = '';
      let salt: string = this.email;
      if (this.localMode) {
        await this.readLocalFile();
        encKey = this.localEncUserKey;
        salt = this.localSalt;
      } else {
        if (this.prefs === null) {
          return false;
        }
        encKey = this.prefs.getSync(KEY_ENC_USER_KEY, '') as string;
      }
      if (encKey.length === 0) {
        return false;
      }
      const masterKey: Uint8Array = await deriveMasterKey(password, salt, this.kdf, this.iterations, this.kdfMemory, this.kdfParallelism);
      const stretched: SymmetricCryptoKey = await stretchMasterKey(masterKey);
      await decryptUserKey(encKey, stretched);
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 排序方式：name（名称）/ created（新增时间）/ updated（修改时间） */
  async setSortMode(mode: string): Promise<void> {
    this.sortMode = mode;
    if (this.prefs !== null) {
      await this.prefs.put(KEY_SORT_MODE, mode);
      await this.prefs.flush();
    }
  }

  lock(): void {
    this.userKey = null;
    this.accessToken = '';
    this.items = [];
    this.trash = [];
    this.folders = [];
  }

  loadDemo(): void {
    this.demo = true;
    this.items = demoItems();
    this.trash = [];
    this.folders = demoFolders();
    this.lastSyncAt = Date.now();
  }

  exitDemo(): void {
    this.demo = false;
    this.items = [];
    this.trash = [];
    this.folders = [];
    this.lastSyncAt = 0;
  }

  async signOut(): Promise<void> {
    const wasLocal: boolean = this.localMode;
    this.lock();
    if (this.prefs !== null) {
      await this.prefs.clear();
      await this.prefs.flush();
    }
    this.hasAccount = false;
    this.bioFingerprint = false;
    this.bioFace = false;
    await deleteBioKey();
    this.server = '';
    this.email = '';
    this.userName = '';
    this.refreshToken = '';
    this.lastSyncAt = 0;
    this.deleteCache();
    if (wasLocal) {
      this.localMode = false;
      this.localCiphers = [];
      this.localFolders = [];
      this.localSalt = '';
      this.localEncUserKey = '';
      try {
        if (fs.accessSync(this.localPath())) {
          fs.unlinkSync(this.localPath());
        }
      } catch (e) {
        // 忽略
      }
    }
  }

  private async persistAccount(): Promise<void> {
    if (this.prefs === null) {
      return;
    }
    await this.prefs.put(KEY_SERVER, this.server);
    await this.prefs.put(KEY_EMAIL, this.email);
    await this.prefs.put(KEY_NAME, this.userName);
    await this.prefs.put(KEY_KDF, this.kdf);
    await this.prefs.put(KEY_ITERATIONS, this.iterations);
    await this.prefs.flush();
  }

  private async persistSession(key: SymmetricCryptoKey, stretched: SymmetricCryptoKey,
    refresh: string): Promise<void> {
    if (this.prefs === null) {
      return;
    }
    const encUserKey: string = await encryptUserKey(key, stretched);
    await this.prefs.put(KEY_ENC_USER_KEY, encUserKey);
    await this.persistRefresh(refresh);
    await this.prefs.put(KEY_KDF, this.kdf);
    await this.prefs.put(KEY_ITERATIONS, this.iterations);
    await this.prefs.flush();
    this.hasAccount = true;
  }

  private async persistRefresh(refresh: string): Promise<void> {
    if (this.prefs === null || this.userKey === null || refresh.length === 0) {
      return;
    }
    const encrypted: string = await encryptToString(refresh, this.userKey);
    await this.prefs.put(KEY_ENC_REFRESH, encrypted);
    await this.prefs.flush();
  }

  private cachePath(): string {
    return `${this.cacheDir}/${CACHE_FILE}`;
  }

  private async writeCache(raw: string): Promise<void> {
    try {
      const payload: CachePayload = {
        server: this.server,
        email: this.email,
        savedAt: Date.now(),
        raw: raw
      };
      const file: fs.File = fs.openSync(this.cachePath(),
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(payload));
      fs.closeSync(file);
    } catch (e) {
      // 缓存失败不影响主流程
    }
  }

  private async loadCache(): Promise<void> {
    try {
      const text: string = fs.readTextSync(this.cachePath());
      const payload: CachePayload = JSON.parse(text) as CachePayload;
      if (payload.server !== this.server || payload.email !== this.email) {
        return;
      }
      if (this.userKey === null) {
        return;
      }
      const response: SyncResponse = JSON.parse(payload.raw) as SyncResponse;
      this.applySync(response);
      this.lastSyncAt = payload.savedAt;
    } catch (e) {
      // 无缓存或缓存损坏
    }
  }

  private deleteCache(): void {
    try {
      if (fs.accessSync(this.cachePath())) {
        fs.unlinkSync(this.cachePath());
      }
    } catch (e) {
      // 忽略
    }
  }
}

export const VaultStore: VaultStoreImpl = new VaultStoreImpl();
