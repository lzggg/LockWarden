/**
 * Vaultwarden / Bitwarden 兼容 HTTP 客户端。
 *
 * 端点与字段依据 vaultwarden-main 源码：
 *  - POST /identity/accounts/prelogin        （src/api/core/accounts.rs）
 *  - POST /identity/connect/token            （src/api/identity.rs）
 *  - GET  /api/sync
 *  - GET/POST /api/ciphers                   （src/api/core/ciphers.rs）
 *
 * 注意：服务端登录接口接收的是「主密码摘要」而不是明文主密码。
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreloginResponse, TokenResponse, SyncResponse, CipherRequest } from './Models';

const CLIENT_ID: string = 'mobile';
const DEVICE_TYPE: string = '0'; // Bitwarden DeviceType.Android
const CLIENT_VERSION: string = '2026.1.0';
const TIMEOUT_MS: number = 15000;

/** 带状态码的接口错误，便于 UI 区分「密码错」和「服务器连不上」 */
export class ApiError extends Error {
  status: number;
  /** 兜底保存错误文案：ArkTS 里继承 Error 后 message 有时读不到 */
  detail: string;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
    this.detail = message;
    this.message = message;
  }
}

/** 统一读取任意抛出对象的可读文案（ApiError 继承 Error 时 message 可能为空） */
export function errorMessage(e: Object): string {
  const apiErr: ApiError = e as ApiError;
  if (apiErr.detail !== undefined && apiErr.detail !== null && apiErr.detail.length > 0) {
    return apiErr.detail;
  }
  const err: Error = e as Error;
  if (err.message !== undefined && err.message !== null && err.message.length > 0) {
    return err.message;
  }
  const text: string = JSON.stringify(e);
  return text === '{}' ? '操作失败，请稍后重试' : text;
}

/** 统一整理服务器地址：补协议、去尾部斜杠；只接受 https（明文 http 会被拒绝） */
export function normalizeServer(input: string): string {
  let server: string = input.trim();
  if (server.length === 0) {
    throw new Error('请填写服务器地址');
  }
  const lower: string = server.toLowerCase();
  if (lower.startsWith('http://')) {
    throw new Error('只支持 https:// 连接，请把地址改成 https:// 开头');
  }
  if (!lower.startsWith('https://')) {
    server = `https://${server}`;
  }
  while (server.endsWith('/')) {
    server = server.substring(0, server.length - 1);
  }
  return server;
}

function formEncode(pairs: string[][]): string {
  const parts: string[] = [];
  for (let i = 0; i < pairs.length; i++) {
    const key: string = pairs[i][0];
    const value: string = pairs[i][1];
    parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
  }
  return parts.join('&');
}

interface RawResponse {
  status: number;
  body: string;
}

async function send(method: http.RequestMethod, url: string, body: string | null,
  headers: Record<string, string>): Promise<RawResponse> {
  const client: http.HttpRequest = http.createHttp();
  try {
    const options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: TIMEOUT_MS,
      readTimeout: TIMEOUT_MS,
      usingCache: false
    };
    if (body !== null) {
      options.extraData = body;
    }
    const response: http.HttpResponse = await client.request(url, options);
    const text: string = typeof response.result === 'string' ?
      response.result as string : JSON.stringify(response.result);
    return { status: response.responseCode, body: text };
  } catch (e) {
    throw new ApiError(0, `无法连接服务器：${networkReason((e as Error).message)}`);
  } finally {
    client.destroy();
  }
}

/** 把底层网络异常翻成用户能看懂的原因 */
function networkReason(raw: string): string {
  const text: string = raw.toLowerCase();
  if (text.indexOf('resolve') >= 0 || text.indexOf('unknownhost') >= 0 ||
    text.indexOf('name not resolved') >= 0 || text.indexOf('no address') >= 0) {
    return '域名无法解析，请检查服务器地址是否拼写正确';
  }
  if (text.indexOf('timeout') >= 0 || text.indexOf('timed out') >= 0) {
    return '连接超时，请检查网络或端口是否正确';
  }
  if (text.indexOf('refused') >= 0) {
    return '服务器拒绝连接，请确认端口号与服务是否在运行';
  }
  if (text.indexOf('certificate') >= 0 || text.indexOf('ssl') >= 0 || text.indexOf('tls') >= 0) {
    return '证书校验失败，请确认服务器证书是否有效';
  }
  if (text.indexOf('network') >= 0 || text.indexOf('offline') >= 0) {
    return '手机当前没有可用网络';
  }
  return raw;
}
function deviceHeaders(accessToken: string | null, deviceId: string): Record<string, string> {
  const headers: Record<string, string> = {
    'Accept': 'application/json',
    'device-type': DEVICE_TYPE,
    'device-identifier': deviceId,
    'Bitwarden-Client-Name': 'mobile',
    'Bitwarden-Client-Version': CLIENT_VERSION,
    'User-Agent': `LockWarden/${CLIENT_VERSION}`
  };
  if (accessToken !== null && accessToken.length > 0) {
    headers['Authorization'] = `Bearer ${accessToken}`;
  }
  return headers;
}

function withJson(headers: Record<string, string>): Record<string, string> {
  headers['Content-Type'] = 'application/json; charset=utf-8';
  return headers;
}

/** 从错误响应里抽取服务端给出的说明 */
function describeError(status: number, body: string): string {
  try {
    const parsed: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
    const description: Object | undefined = parsed['error_description'];
    if (description !== undefined && description !== null) {
      const text: string = description.toString().trim();
      // Vaultwarden 有时返回空的 error_description，这种情况要继续往下找 error 字段
      if (text.length > 0) {
        return text;
      }
    }
    const error: Object | undefined = parsed['error'];
    if (error !== undefined && error !== null) {
      const message: Object | undefined = parsed['errorModel'];
      if (message !== undefined && message !== null) {
        const msg: Record<string, Object> = message as Record<string, Object>;
        const text: Object | undefined = msg['message'];
        if (text !== undefined && text !== null) {
          return text.toString();
        }
      }
      const errText: string = error.toString().trim();
      if (errText.length > 0) {
        return errText;
      }
    }
    const errors: Object | undefined = parsed['validationErrors'];
    if (errors !== undefined && errors !== null) {
      return JSON.stringify(errors);
    }
  } catch (e) {
    // 非 JSON 响应，退回原文
  }
  if (body !== null && body.length > 0 && body.length < 200) {
    return body;
  }
  if (status === 401) {
    return '主密码错误或会话已失效';
  }
  if (status === 429) {
    return '尝试次数过多，已被服务器暂时限制，请稍后再试';
  }
  if (status >= 500) {
    return `服务器内部错误（HTTP ${status}），请稍后重试或联系服务器管理员`;
  }
  if (status === 400) {
    return '请求被服务器拒绝（400）';
  }
  if (status === 404) {
    return '接口不存在，请确认服务器地址是否正确';
  }

  return `服务器返回错误（HTTP ${status}）`;
}

function parseJson<T>(body: string, status: number): T {
  if (status < 200 || status >= 300) {
    throw new ApiError(status, describeError(status, body));
  }
  if (body === null || body.trim().length === 0) {
    throw new ApiError(status, '服务器返回空响应');
  }
  return JSON.parse(body) as T;
}

/** 探测服务器：/api/config 返回 JSON 即认为可用 */
export async function probeServer(server: string): Promise<string> {
  const url: string = `${server}/api/config`;
  const response: RawResponse = await send(http.RequestMethod.GET, url, null,
    { 'Accept': 'application/json' });
  if (response.status >= 200 && response.status < 300) {
    try {
      const config: Record<string, Object> = JSON.parse(response.body) as Record<string, Object>;
      const version: Object | undefined = config['version'];
      if (version !== undefined && version !== null) {
        return version.toString();
      }
      return '已连接';
    } catch (e) {
      return '已连接';
    }
  }
  throw new ApiError(response.status, describeError(response.status, response.body));
}

/** KDF 参数预取 */
export async function prelogin(server: string, email: string): Promise<PreloginResponse> {
  const url: string = `${server}/identity/accounts/prelogin`;
  const headers: Record<string, string> = {
    'Content-Type': 'application/json; charset=utf-8',
    'Accept': 'application/json'
  };
  const body: string = JSON.stringify({ 'email': email } as Record<string, string>);
  const response: RawResponse = await send(http.RequestMethod.POST, url, body, headers);
  return parseJson<PreloginResponse>(response.body, response.status);
}

/** 主密码登录 */
export async function loginWithPassword(server: string, email: string, hashedPassword: string,
  deviceId: string, deviceName: string): Promise<TokenResponse> {
  const url: string = `${server}/identity/connect/token`;
  const form: string = formEncode([
    ['grant_type', 'password'],
    ['username', email],
    ['password', hashedPassword],
    ['scope', 'api offline_access'],
    ['client_id', CLIENT_ID],
    ['deviceType', DEVICE_TYPE],
    ['deviceIdentifier', deviceId],
    ['deviceName', deviceName]
  ]);
  const headers: Record<string, string> = {
    'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
    'Accept': 'application/json',
    'device-type': DEVICE_TYPE,
    // 服务端强制要求三段式 semver，缺了它即使口令正确也会 400
    'Bitwarden-Client-Version': CLIENT_VERSION
  };
  const response: RawResponse = await send(http.RequestMethod.POST, url, form, headers);
  if (response.status >= 400) {
    hilog.error(0x0001, 'LockWarden', 'loginHttpDebug status=%{public}d body=%{public}s',
      response.status, response.body.length > 300 ? response.body.substring(0, 300) : response.body);
  }
  return parseJson<TokenResponse>(response.body, response.status);
}

/** 用 refresh_token 换新的 access_token */
export async function refreshToken(server: string, token: string, deviceId: string,
  deviceName: string): Promise<TokenResponse> {
  const url: string = `${server}/identity/connect/token`;
  const form: string = formEncode([
    ['grant_type', 'refresh_token'],
    ['refresh_token', token],
    ['client_id', CLIENT_ID],
    ['deviceType', DEVICE_TYPE],
    ['deviceIdentifier', deviceId],
    ['deviceName', deviceName]
  ]);
  const headers: Record<string, string> = {
    'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
    'Accept': 'application/json',
    'device-type': DEVICE_TYPE,
    'Bitwarden-Client-Version': CLIENT_VERSION
  };
  const response: RawResponse = await send(http.RequestMethod.POST, url, form, headers);
  return parseJson<TokenResponse>(response.body, response.status);
}

/** 全量同步 */
export async function fetchSync(server: string, accessToken: string, deviceId: string): Promise<SyncResponse> {
  const url: string = `${server}/api/sync?excludeDomains=true`;
  const response: RawResponse = await send(http.RequestMethod.GET, url, null,
    deviceHeaders(accessToken, deviceId));
  return parseJson<SyncResponse>(response.body, response.status);
}

/** 新建条目 */
export async function createCipher(server: string, accessToken: string, deviceId: string,
  payload: CipherRequest): Promise<void> {
  const url: string = `${server}/api/ciphers`;
  const headers: Record<string, string> = deviceHeaders(accessToken, deviceId);
  headers['Content-Type'] = 'application/json; charset=utf-8';
  const response: RawResponse = await send(http.RequestMethod.POST, url, JSON.stringify(payload), headers);
  if (response.status < 200 || response.status >= 300) {
    throw new ApiError(response.status, describeError(response.status, response.body));
  }
}

/** 整体更新条目（PUT /api/ciphers/{id}） */
export async function updateCipher(server: string, accessToken: string, deviceId: string,
  id: string, payload: CipherRequest): Promise<void> {
  const url: string = `${server}/api/ciphers/${id}`;
  const headers: Record<string, string> = deviceHeaders(accessToken, deviceId);
  headers['Content-Type'] = 'application/json; charset=utf-8';
  const response: RawResponse = await send(http.RequestMethod.PUT, url, JSON.stringify(payload), headers);
  if (response.status < 200 || response.status >= 300) {
    throw new ApiError(response.status, describeError(response.status, response.body));
  }
}

/**
 * 只改收藏与所属文件夹（PUT /api/ciphers/{id}/partial）。
 * 服务端要求 body 同时带 favorite 与 folderId。
 */
export async function partialUpdateCipher(server: string, accessToken: string, deviceId: string,
  id: string, folderId: string | null, favorite: boolean): Promise<void> {
  const url: string = `${server}/api/ciphers/${id}/partial`;
  const headers: Record<string, string> = deviceHeaders(accessToken, deviceId);
  headers['Content-Type'] = 'application/json; charset=utf-8';
  const body: string = JSON.stringify({
    'folderId': folderId,
    'favorite': favorite
  } as Record<string, Object>);
  const response: RawResponse = await send(http.RequestMethod.PUT, url, body, headers);
  if (response.status < 200 || response.status >= 300) {
    throw new ApiError(response.status, describeError(response.status, response.body));
  }
}

/** 软删除 → 回收站（PUT /api/ciphers/{id}/delete） */
export async function trashCipher(server: string, accessToken: string, deviceId: string,
  id: string): Promise<void> {
  const url: string = `${server}/api/ciphers/${id}/delete`;
  const response: RawResponse = await send(http.RequestMethod.PUT, url, '{}',
    withJson(deviceHeaders(accessToken, deviceId)));
  if (response.status < 200 || response.status >= 300) {
    throw new ApiError(response.status, describeError(response.status, response.body));
  }
}

/** 从回收站恢复（PUT /api/ciphers/{id}/restore） */
export async function restoreCipher(server: string, accessToken: string, deviceId: string,
  id: string): Promise<void> {
  const url: string = `${server}/api/ciphers/${id}/restore`;
  const response: RawResponse = await send(http.RequestMethod.PUT, url, '{}',
    withJson(deviceHeaders(accessToken, deviceId)));
  if (response.status < 200 || response.status >= 300) {
    throw new ApiError(response.status, describeError(response.status, response.body));
  }
}

/** 彻底删除，不可恢复（DELETE /api/ciphers/{id}） */
export async function purgeCipher(server: string, accessToken: string, deviceId: string,
  id: string): Promise<void> {
  const url: string = `${server}/api/ciphers/${id}`;
  const response: RawResponse = await send(http.RequestMethod.DELETE, url, null,
    deviceHeaders(accessToken, deviceId));
  if (response.status < 200 || response.status >= 300) {
    throw new ApiError(response.status, describeError(response.status, response.body));
  }
}

/** 新建文件夹（name 为密文），返回新文件夹 id */
export async function createFolder(server: string, accessToken: string, deviceId: string,
  encryptedName: string): Promise<string> {
  const url: string = `${server}/api/folders`;
  const headers: Record<string, string> = withJson(deviceHeaders(accessToken, deviceId));
  const response: RawResponse = await send(http.RequestMethod.POST, url,
    JSON.stringify({ 'name': encryptedName } as Record<string, string>), headers);
  if (response.status < 200 || response.status >= 300) {
    throw new ApiError(response.status, describeError(response.status, response.body));
  }
  try {
    const parsed: Record<string, Object> = JSON.parse(response.body) as Record<string, Object>;
    const id: Object | undefined = parsed['id'];
    return id === undefined || id === null ? '' : id.toString();
  } catch (e) {
    return '';
  }
}

/** 文件夹改名（name 为密文） */
export async function renameFolder(server: string, accessToken: string, deviceId: string,
  id: string, encryptedName: string): Promise<void> {
  const url: string = `${server}/api/folders/${id}`;
  const headers: Record<string, string> = withJson(deviceHeaders(accessToken, deviceId));
  const response: RawResponse = await send(http.RequestMethod.PUT, url,
    JSON.stringify({ 'name': encryptedName } as Record<string, string>), headers);
  if (response.status < 200 || response.status >= 300) {
    throw new ApiError(response.status, describeError(response.status, response.body));
  }
}

/** 删除文件夹（条目不会被删，只是失去归属） */
export async function deleteFolder(server: string, accessToken: string, deviceId: string,
  id: string): Promise<void> {
  const url: string = `${server}/api/folders/${id}`;
  const response: RawResponse = await send(http.RequestMethod.DELETE, url, null,
    deviceHeaders(accessToken, deviceId));
  if (response.status < 200 || response.status >= 300) {
    throw new ApiError(response.status, describeError(response.status, response.body));
  }
}

/** 把身份接口的错误码翻成用户能看懂的中文 */
export function friendlyAuthError(message: string): string {
  const text: string = message.toLowerCase();
  if (text.indexOf('invalid_grant') >= 0 || text.indexOf('invalid_username_or_password') >= 0 ||
    text.indexOf('username or password') >= 0 || text.indexOf('invalid password') >= 0) {
    return '主密码错误，请重新输入';
  }
  if (text.indexOf('user not found') >= 0 || text.indexOf('account does not exist') >= 0 ||
    text.indexOf('unknown user') >= 0) {
    return '该邮箱未在此服务器注册，请检查邮箱或服务器地址';
  }
  if (text.indexOf('captcha') >= 0) {
    return '服务器要求人机验证，请先在网页端登录一次';
  }
  if (text.indexOf('two_factor') >= 0 || text.indexOf('2fa') >= 0) {
    return '该账号开启了两步验证，当前版本暂不支持';
  }
  return message;
}