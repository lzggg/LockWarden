/**
 * 数据模型：与 Vaultwarden 的 JSON 契约一一对应（字段名大小写按服务端 serde 序列化结果）。
 *
 * 依据 vaultwarden-main/src/api/core/ciphers.rs 的 CipherData 与
 * src/api/identity.rs 的登录响应字段。
 */

/** 登录条目中的一条 URI */
export interface LoginUriData {
  match?: number | null;
  uri?: string | null;
}

/** 登录条目 */
export interface LoginData {
  username?: string | null;
  password?: string | null;
  passwordRevisionDate?: string | null;
  totp?: string | null;
  uri?: string | null;
  uris?: LoginUriData[] | null;
  fido2Credentials?: Object[] | null;
}

/** 自定义字段 */
export interface FieldData {
  name?: string | null;
  value?: string | null;
  type: number;
  linkedId?: number | null;
}

/** 卡片条目 */
export interface CardData {
  cardholderName?: string | null;
  brand?: string | null;
  number?: string | null;
  expMonth?: string | null;
  expYear?: string | null;
  code?: string | null;
}

/** 身份条目 */
export interface IdentityData {
  title?: string | null;
  firstName?: string | null;
  middleName?: string | null;
  lastName?: string | null;
  address1?: string | null;
  city?: string | null;
  postalCode?: string | null;
  country?: string | null;
  phone?: string | null;
  email?: string | null;
}

/** 服务端返回的加密条目 */
export interface SyncCipher {
  id: string;
  organizationId?: string | null;
  folderId?: string | null;
  type: number;
  name: string;
  notes?: string | null;
  favorite?: boolean | null;
  login?: LoginData | null;
  card?: CardData | null;
  identity?: IdentityData | null;
  secureNote?: Object | null;
  fields?: FieldData[] | null;
  passwordHistory?: Object[] | null;
  revisionDate?: string | null;
  creationDate?: string | null;
  deletedDate?: string | null;
  key?: string | null;
  collectionIds?: string[] | null;
}

/** 文件夹 */
export interface SyncFolder {
  id: string;
  name: string;
  revisionDate?: string | null;
}

/** 个人资料（sync 或 token 响应中的 profile 部分） */
export interface SyncProfile {
  id?: string;
  name?: string | null;
  email?: string | null;
  emailVerified?: boolean;
  key?: string | null;
  privateKey?: string | null;
  securityStamp?: string | null;
  kdf?: number | null;
  kdfIterations?: number | null;
  kdfMemory?: number | null;
  kdfParallelism?: number | null;
  culture?: string | null;
  twoFactorEnabled?: boolean | null;
  premium?: boolean | null;
}

/** GET /api/sync 响应 */
export interface SyncResponse {
  profile?: SyncProfile | null;
  folders?: SyncFolder[] | null;
  ciphers?: SyncCipher[] | null;
  collections?: Object[] | null;
  object?: string | null;
}

/** POST /identity/accounts/prelogin 响应 */
export interface PreloginResponse {
  kdf?: number | null;
  kdfIterations?: number | null;
  kdfMemory?: number | null;
  kdfParallelism?: number | null;
}

/**
 * POST /identity/connect/token 响应。
 * 注意：这几个字段是 PascalCase（`Key`/`Kdf`/`KdfIterations`），
 * 与 prelogin 的 camelCase（`kdf`/`kdfIterations`）不一致，见 docs/api-contract.md 4.3。
 */
export interface TokenResponse {
  access_token?: string | null;
  expires_in?: number | null;
  token_type?: string | null;
  refresh_token?: string | null;
  Key?: string | null;
  PrivateKey?: string | null;
  Kdf?: number | null;
  KdfIterations?: number | null;
  KdfMemory?: number | null;
  KdfParallelism?: number | null;
  TwoFactorToken?: string | null;
}

/** 创建/更新条目请求体（字段均为密文） */
export interface CipherRequest {
  type: number;
  name: string;
  notes: string | null;
  favorite: boolean;
  folderId: string | null;
  login?: LoginRequest | null;
  card?: CardRequest | null;
  identity?: IdentityRequest | null;
  secureNote?: SecureNoteRequest | null;
  fields?: FieldRequest[] | null;
  lastKnownRevisionDate?: string | null;
}

/** 安全笔记体（Bitwarden 约定 type 恒为 0） */
export interface SecureNoteRequest {
  type: number;
}

export interface LoginRequest {
  username: string | null;
  password: string | null;
  passwordRevisionDate: string | null;
  totp: string | null;
  uri: string | null;
  uris: LoginUriRequest[] | null;
}

export interface LoginUriRequest {
  match: number | null;
  uri: string | null;
}

/** 卡片条目请求体（字段均为密文） */
export interface CardRequest {
  cardholderName: string | null;
  brand: string | null;
  number: string | null;
  expMonth: string | null;
  expYear: string | null;
  code: string | null;
}

/** 身份条目请求体（字段均为密文） */
export interface IdentityRequest {
  title: string | null;
  firstName: string | null;
  lastName: string | null;
  email: string | null;
  phone: string | null;
  address1: string | null;
  city: string | null;
  postalCode: string | null;
  country: string | null;
}

/** 自定义字段请求体 */
export interface FieldRequest {
  name: string | null;
  value: string | null;
  type: number;
}

/** 条目类型，与 Bitwarden CipherType 一致 */
export enum CipherType {
  Login = 1,
  SecureNote = 2,
  Card = 3,
  Identity = 4,
  Reprompt = 5
}

/** 解密后的条目附加信息 */
export interface VaultCard {
  cardholderName: string;
  brand: string;
  number: string;
  expMonth: string;
  expYear: string;
  code: string;
}

export interface VaultIdentity {
  title: string;
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
  address: string;
  city: string;
  postalCode: string;
  country: string;
}

/** 自定义字段（type: 0=文本 1=隐藏 2=布尔 3=关联） */
export interface VaultField {
  name: string;
  value: string;
  type: number;
}

/** 解密后的条目，供 UI 直接使用 */
export interface VaultItem {
  id: string;
  type: number;
  name: string;
  username: string;
  password: string;
  totp: string;
  uri: string;
  notes: string;
  favorite: boolean;
  folderId: string;
  revisionDate: string;
  /** 创建时间（ISO 字符串，可能缺省） */
  creationDate?: string;
  /** 无法解密时为 true，UI 显示占位符而不是崩溃 */
  broken: boolean;
  /** 是否在回收站 */
  deleted?: boolean;
  card?: VaultCard | null;
  identity?: VaultIdentity | null;
  fields?: VaultField[] | null;
  /** 历史密码（已解密），最新在前 */
  history?: string[] | null;
}

/** 解密后的文件夹 */
export interface VaultFolder {
  id: string;
  name: string;
}

/**
 * 编辑器与存储层之间的交换结构：明文。
 * 存储层负责按类型加密成 CipherRequest。
 */
export interface CipherDraft {
  /** 空串表示新建 */
  id: string;
  type: number;
  name: string;
  username: string;
  password: string;
  totp: string;
  uri: string;
  notes: string;
  favorite: boolean;
  folderId: string;
  card: VaultCard;
  identity: VaultIdentity;
  fields: VaultField[];
}

/** 空白卡片 */
export function emptyCard(): VaultCard {
  const card: VaultCard = {
    cardholderName: '', brand: '', number: '', expMonth: '', expYear: '', code: ''
  };
  return card;
}

/** 空白身份 */
export function emptyIdentity(): VaultIdentity {
  const identity: VaultIdentity = {
    title: '', firstName: '', lastName: '', email: '', phone: '',
    address: '', city: '', postalCode: '', country: ''
  };
  return identity;
}

/** 新建条目的空白草稿 */
export function emptyDraft(type: number): CipherDraft {
  const draft: CipherDraft = {
    id: '',
    type: type,
    name: '',
    username: '',
    password: '',
    totp: '',
    uri: '',
    notes: '',
    favorite: false,
    folderId: '',
    card: emptyCard(),
    identity: emptyIdentity(),
    fields: []
  };
  return draft;
}

/** 应用阶段 */
export enum Stage {
  Boot = 'boot',
  Setup = 'setup',
  LocalSetup = 'localSetup',
  Login = 'login',
  Unlock = 'unlock',
  Vault = 'vault'
}
