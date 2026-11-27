/**
 * 生物识别解锁用的密钥包裹（HUKS）。
 *
 * 为什么需要它：生物识别解锁时没有主密码，无法现算主密钥，
 * 必须把"已经解密好的账号密钥"留在设备上。直接存明文显然不行，
 * 因此用 HUKS 里的一把设备绑定、不可导出的 AES-256 密钥把它加密后再落盘。
 *
 * 安全边界（如实说明）：
 *  - HUKS 密钥在 TEE 内生成与使用，应用拿不到明文密钥，换设备/清数据即失效；
 *  - 但当前实现没有把密钥绑定到具体生物特征（HUKS_TAG_USER_AUTH_TYPE），
 *    生物识别是"应用层闸门"。若要更强，应改为认证绑定密钥，
 *    并在解密时附带 userAuth 返回的 token —— 那样连应用自身都无法绕过认证。
 */
import { huks } from '@kit.UniversalKeystoreKit';
import { Bytes } from './CryptoUtils';

const KEY_ALIAS: string = 'vaultwarden_bio_userkey_v1';
const IV_SIZE: number = 16;

function baseProps(): huks.HuksParam[] {
  const props: huks.HuksParam[] = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    },
    { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CBC },
    { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 }
  ];
  return props;
}

/** 键不存在时 isKeyItemExist 会抛错，这里统一转成布尔值 */
async function keyExists(): Promise<boolean> {
  try {
    return await huks.isKeyItemExist(KEY_ALIAS, { properties: [] });
  } catch (e) {
    return false;
  }
}

async function ensureKey(): Promise<void> {
  if (await keyExists()) {
    return;
  }
  const options: huks.HuksOptions = { properties: baseProps() };
  await huks.generateKeyItem(KEY_ALIAS, options);
}

/** 跑完一次 init/update/finish，把两段输出拼起来（HUKS 可能返回 null） */
async function runCipher(handle: number, data: Uint8Array): Promise<Uint8Array> {
  const parts: Uint8Array[] = [];
  const first: huks.HuksReturnResult | null = await huks.updateSession(handle, {
    properties: [], inData: data
  });
  if (first !== null && first !== undefined && first.outData !== undefined &&
    first.outData.length > 0) {
    parts.push(first.outData);
  }
  const last: huks.HuksReturnResult | null = await huks.finishSession(handle, {
    properties: [], inData: new Uint8Array(0)
  });
  if (last !== null && last !== undefined && last.outData !== undefined &&
    last.outData.length > 0) {
    parts.push(last.outData);
  }
  return Bytes.concat(parts);
}

function cipherInitProps(purpose: number, iv: Uint8Array): huks.HuksParam[] {
  // initSession 必须重复声明算法/长度/模式/填充，只给 PURPOSE+IV 会报 Invalid parameters
  const props: huks.HuksParam[] = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
    { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CBC },
    { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 },
    { tag: huks.HuksTag.HUKS_TAG_IV, value: iv }
  ];
  return props;
}

/** 用 HUKS 密钥包裹账号密钥，返回 "base64(iv):base64(cipher)" */
export async function wrapUserKey(plain: Uint8Array): Promise<string> {
  await ensureKey();
  const iv: Uint8Array = Bytes.random(IV_SIZE);
  const handle: huks.HuksSessionHandle = await huks.initSession(KEY_ALIAS, {
    properties: cipherInitProps(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, iv)
  });
  const cipher: Uint8Array = await runCipher(handle.handle, plain);
  return `${Bytes.b64(iv)}:${Bytes.b64(cipher)}`;
}

/** 解开包裹，返回账号密钥（64 字节） */
export async function unwrapUserKey(blob: string): Promise<Uint8Array> {
  const sep: number = blob.indexOf(':');
  if (sep <= 0) {
    throw new Error('生物识别密钥数据损坏');
  }
  const iv: Uint8Array = Bytes.fromB64(blob.substring(0, sep));
  const cipher: Uint8Array = Bytes.fromB64(blob.substring(sep + 1));
  const handle: huks.HuksSessionHandle = await huks.initSession(KEY_ALIAS, {
    properties: cipherInitProps(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, iv)
  });
  return runCipher(handle.handle, cipher);
}

/** 关闭生物识别时删掉 HUKS 密钥，之前的包裹数据随之作废 */
export async function deleteBioKey(): Promise<void> {
  try {
    if (await keyExists()) {
      await huks.deleteKeyItem(KEY_ALIAS, { properties: [] });
    }
  } catch (e) {
    // 删除失败不阻塞主流程
  }
}
