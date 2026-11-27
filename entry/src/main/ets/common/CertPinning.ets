/**
 * 服务器证书首次信任（TOFU, Trust On First Use）。
 *
 * 第一次连接某台服务器时记录它的证书指纹；之后每次连接开始前比对：
 *  - 一致：正常继续
 *  - 不一致：抛出 CERT_CHANGED 错误，由连接页弹窗让用户确认（确认后覆盖旧指纹）
 *
 * 设计取舍：
 *  - 不硬编码指纹：服务器是用户自建的，地址各异
 *  - 只校验「证书 DER 的 SHA-256」，不解析公钥：实现简单，证书续期时指纹会变，
 *    因此必须提供「信任新证书」入口，否则换证书的用户会被挡住
 *  - 拉取证书失败（自签名、非 443 端口不可达等）只记录日志、不阻断连接，
 *    避免把原本能用的用户挡在门外
 */
import { socket } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const PREFS_NAME: string = 'cert_pins';
const KEY_PINS: string = 'pins';
const DOMAIN: number = 0x0001;
const TAG: string = 'LockWarden';

/** 证书变化错误的固定前缀，UI 据此判断是否弹「信任新证书」 */
export const CERT_CHANGED_PREFIX: string = 'CERT_CHANGED|';

interface PinEntry {
  host: string;
  pin: string;
}

class CertPinningImpl {
  private prefs: preferences.Preferences | null = null;

  async init(context: common.Context): Promise<void> {
    if (this.prefs !== null) {
      return;
    }
    try {
      this.prefs = await preferences.getPreferences(context, PREFS_NAME);
    } catch (e) {
      this.prefs = null;
    }
  }

  /** 从 https://host:port/path 里取出 host 和 port */
  private hostOf(server: string): string {
    let text: string = server.trim().toLowerCase();
    const scheme: number = text.indexOf('://');
    if (scheme >= 0) {
      text = text.substring(scheme + 3);
    }
    const slash: number = text.indexOf('/');
    if (slash >= 0) {
      text = text.substring(0, slash);
    }
    const colon: number = text.indexOf(':');
    if (colon >= 0) {
      text = text.substring(0, colon);
    }
    return text;
  }

  private portOf(server: string): number {
    let text: string = server.trim().toLowerCase();
    const scheme: number = text.indexOf('://');
    if (scheme >= 0) {
      text = text.substring(scheme + 3);
    }
    const slash: number = text.indexOf('/');
    if (slash >= 0) {
      text = text.substring(0, slash);
    }
    const colon: number = text.indexOf(':');
    if (colon < 0) {
      return 443;
    }
    const port: number = Number.parseInt(text.substring(colon + 1), 10);
    return Number.isNaN(port) || port <= 0 ? 443 : port;
  }

  private async sha256Hex(data: Uint8Array): Promise<string> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
    await md.update({ data: data });
    const digest: cryptoFramework.DataBlob = await md.digest();
    let out: string = '';
    for (let i = 0; i < digest.data.length; i++) {
      const byte: number = digest.data[i];
      out += (byte < 16 ? '0' : '') + byte.toString(16);
    }
    return out;
  }

  /** 连一次 TLS 拿服务器证书，算 DER 的 SHA-256；失败返回 '' */
  private async fetchPin(server: string): Promise<string> {
    const host: string = this.hostOf(server);
    if (host.length === 0) {
      return '';
    }
    const tls: socket.TLSSocket = socket.constructTLSSocketInstance();
    try {
      const options: socket.TLSConnectOptions = {
        address: {
          address: host,
          port: this.portOf(server),
          family: 1
        },
        secureOptions: {}
      };
      await tls.connect(options);
      const raw: socket.X509CertRawData = await tls.getRemoteCertificate();
      return await this.sha256Hex(raw.data);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'cert fetch failed: %{public}s', (e as Error).message);
      return '';
    } finally {
      try {
        tls.close();
      } catch (e) {
        // 忽略关闭失败
      }
    }
  }

  private loadPins(): Map<string, string> {
    const map: Map<string, string> = new Map<string, string>();
    if (this.prefs === null) {
      return map;
    }
    try {
      const raw: string = this.prefs.getSync(KEY_PINS, '[]') as string;
      const list: PinEntry[] = JSON.parse(raw) as PinEntry[];
      for (let i = 0; i < list.length; i++) {
        map.set(list[i].host, list[i].pin);
      }
    } catch (e) {
      // 解析失败按没有记录处理
    }
    return map;
  }

  private async savePins(map: Map<string, string>): Promise<void> {
    if (this.prefs === null) {
      return;
    }
    try {
      const list: PinEntry[] = [];
      map.forEach((pin: string, host: string) => {
        list.push({ host: host, pin: pin });
      });
      this.prefs.putSync(KEY_PINS, JSON.stringify(list));
      await this.prefs.flush();
    } catch (e) {
      // 忽略持久化失败
    }
  }

  /** 首次连接记录指纹；已记录则比对，变化时抛 CERT_CHANGED 错误 */
  async verify(server: string): Promise<void> {
    const host: string = this.hostOf(server);
    if (host.length === 0) {
      return;
    }
    const pin: string = await this.fetchPin(server);
    if (pin.length === 0) {
      return;
    }
    const map: Map<string, string> = this.loadPins();
    const saved: string | undefined = map.get(host);
    if (saved === undefined || saved.length === 0) {
      map.set(host, pin);
      await this.savePins(map);
      return;
    }
    if (saved !== pin) {
      throw new Error(`${CERT_CHANGED_PREFIX}${host}|${saved.substring(0, 16)}|${pin.substring(0, 16)}`);
    }
  }

  /** 用户确认后，把当前证书覆盖为新指纹 */
  async trust(server: string): Promise<void> {
    const host: string = this.hostOf(server);
    if (host.length === 0) {
      return;
    }
    const pin: string = await this.fetchPin(server);
    if (pin.length === 0) {
      return;
    }
    const map: Map<string, string> = this.loadPins();
    map.set(host, pin);
    await this.savePins(map);
  }
}

export const CertPinning: CertPinningImpl = new CertPinningImpl();
