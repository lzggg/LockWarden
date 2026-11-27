/**
 * 应用根页面：阶段切换 + 真实数据/能力注入 + 自动锁定。
 *
 * 阶段流转：
 *   Boot -> (无本地账号) Setup -> Login -> 主界面
 *   Boot -> (有本地账号) Unlock -> 主界面
 *   主界面 --锁定/自动锁定--> Unlock ；--退出--> Setup ；Setup --演示--> 主界面(演示数据)
 *
 * 界面本身在 view/MainShell.ets，与预览页共用。
 */
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Stage, VaultItem, VaultFolder, CipherDraft, VaultAttachment } from '../common/Models';
import { VaultStore } from '../common/VaultStore';
import { scanSupported } from '../common/ScanSupport';
import { TotpStore, TotpAccount, parseOtpauth } from '../common/TotpStore';
import { generateTotpSync, isBase32LengthValid, extractTotpSecret, secondsRemaining } from '../common/Totp';
import { FloatingBall } from '../common/FloatingBall';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { Theme } from '../common/Theme';
import { copyText, setAutoClearSeconds } from '../common/Clipboard';
import { CopyHint } from '../common/CopyHint';
import { offerPasswordCopy, publishTotpHint, cancelHints, COPY_EVENT, COPY_TOTP_EVENT } from '../common/Notify';
import { bindDialogContext, confirmDanger } from '../common/Dialog';
import { commonEventManager } from '@kit.BasicServicesKit';
import { Bytes } from '../common/CryptoUtils';
import { BackBus } from '../common/BackBus';
import { PrivacyMode } from '../common/PrivacyMode';
import { Biometric } from '../common/Biometric';
import { SetupView } from '../view/SetupView';
import { LocalSetupView } from '../view/LocalSetupView';
import { AuthView } from '../view/AuthView';
import { MainShell } from '../view/MainShell';

@Entry
@Component
struct Index {
  @State stage: Stage = Stage.Boot;
  /** 服务器密钥轮换提示（只弹一次） */
  private rotationNotified: boolean = false;
  @State items: VaultItem[] = [];
  @State trash: VaultItem[] = [];
  @State folders: VaultFolder[] = [];
  @State syncAt: number = 0;
  @State syncing: boolean = false;
  @State email: string = '';
  @State server: string = '';
  @State autoLockMinutes: number = 5;
  @State notifyKeepSeconds: number = 30;
  @State sortMode: string = 'name';
  @State bioEnabled: boolean = false;
  /** 全屏布局下状态栏占用的高度（vp），给根容器留出内边距 */
  @State topInset: number = 0;
  /** 底部导航条高度（vp）：让 TabBar 把它盖住，避免多出一条灰边 */
  @State bottomInset: number = 0;
  /** 是否禁止截屏（安全页开关） */
  @State noScreenshot: boolean = false;
  @State bioFingerprint: boolean = false;
  @State bioFace: boolean = false;
  @State fpAvailable: boolean = false;
  @State faceAvailable: boolean = false;
  @State fpReason: string = '';
  @State faceReason: string = '';
  @State bioRev: number = 0;
  @State bootError: string = '';
  @State demo: boolean = false;
  @State localMode: boolean = false;
  @State totpAccounts: TotpAccount[] = [];
  /** 正在上传附件，用于详情页显示进度提示 */
  @State attachmentBusy: boolean = false;
  /** 附件操作提示文案（上传/下载） */
  @State attachmentBusyLabel: string = '';
  /** 已确认删除、等待服务端完成的附件 id：先从界面隐藏，避免大附件删除后残留 */
  @State attachmentHideIds: string[] = [];

  private lastActive: number = Date.now();
  private idleTimer: number = -1;
  private bioPrompted: boolean = false;
  /** 通知点击事件的订阅者（后台直接复制密码，不切前台） */
  private copySubscriber: commonEventManager.CommonEventSubscriber | null = null;
  /** 闪控球状态 */
  private ballItemId: string = '';
  private ballMode: string = '';
  private ballCode: string = '';
  private ballTimer: number = -1;
  private ballPulseTimer: number = -1;
  private ballName: string = '';
  /** 复制密码后若带验证器，用通知显示动态码倒计时 */
  private totpNotifyTimer: number = -1;
  private totpNotifyItemId: string = '';






  aboutToAppear(): void {
    FloatingBall.setOnClick(() => this.onFloatBallClick());
    bindDialogContext(this.getUIContext());
    this.subscribeCopyEvent();
    this.bootstrap();
    this.startIdleWatch();
    this.fpAvailable = Biometric.fingerprintAvailable();
    this.faceAvailable = Biometric.faceAvailable();
    this.fpReason = Biometric.fingerprintReason();
    this.faceReason = Biometric.faceReason();
  }

  /** 页面隐藏（切到后台 / 退出应用）时：若设置为「退出时」，立即锁定 */
  onPageHide(): void {
    if (VaultStore.autoLockMinutes < 0 && VaultStore.unlocked) {
      this.lock();
    }
  }

  aboutToDisappear(): void {
    FloatingBall.stop();
    this.resetBall();
    this.unsubscribeCopyEvent();
    if (this.idleTimer >= 0) {
      clearInterval(this.idleTimer);
      this.idleTimer = -1;
    }
  }

  onBackPress(): boolean {
    if (this.stage === Stage.Vault) {
      return BackBus.dispatch();
    }
    if (this.stage === Stage.Login || this.stage === Stage.Unlock) {
      this.pullStoreState();
      this.stage = Stage.Setup;
      return true;
    }
    if (this.stage === Stage.Setup && VaultStore.hasAccount) {
      this.pullStoreState();
      this.stage = Stage.Unlock;
      return true;
    }
    return false;
  }

  /** 空闲自动锁定：10 秒轮询一次，超过设定分钟数就锁定 */
  private startIdleWatch(): void {
    this.idleTimer = setInterval(() => {
      const minutes: number = VaultStore.autoLockMinutes;
      if (!VaultStore.unlocked || minutes <= 0) {
        this.lastActive = Date.now();
        return;
      }
      if (Date.now() - this.lastActive > minutes * 60000) {
        this.lock();
      }
    }, 10000);
  }

  private touch(): void {
    this.lastActive = Date.now();
  }

  /** 启动：量安全区 → 初始化隐私开关 → 初始化存储 → 决定首屏阶段 */
  private async bootstrap(): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      Biometric.setContext(context);
      await Index.measureInsets(this, context);
      await PrivacyMode.init(context);
      this.noScreenshot = PrivacyMode.enabled;
      await VaultStore.init(context);
      // 把「剪贴板自动清除」设置同步给剪贴板模块（0 = 不清除）
      setAutoClearSeconds(VaultStore.clipboardClearSeconds);
      this.pullStoreState();
      this.stage = VaultStore.hasAccount ? Stage.Unlock : Stage.Setup;
    } catch (error) {
      this.bootError = (error as Error).message;
      this.stage = Stage.Setup;
    }
  }

  /** 把 store 里的状态同步到页面（每次增删改后调用） */
  private pullStoreState(): void {
    this.loadTotpAccounts();
    this.items = VaultStore.items.slice(0);
    this.trash = VaultStore.trash.slice(0);
    this.folders = VaultStore.folders.slice(0);
    this.syncAt = VaultStore.lastSyncAt;
    this.email = VaultStore.email;
    this.server = VaultStore.server;
    this.autoLockMinutes = VaultStore.autoLockMinutes;
    this.notifyKeepSeconds = VaultStore.notifyKeepSeconds;
    this.sortMode = VaultStore.sortMode;
    this.bioFingerprint = VaultStore.bioFingerprint;
    this.bioFace = VaultStore.bioFace;
    this.bioEnabled = VaultStore.bioEnabled;
    this.bioRev = this.bioRev + 1;
    this.demo = VaultStore.demo;
    this.localMode = VaultStore.localMode;
    this.watchKeyRotation();
  }

  /** 服务器密钥轮换时提示用户重新登录，避免被误认为软件故障 */
  private watchKeyRotation(): void {
    if (!VaultStore.keyRotated || this.rotationNotified) {
      return;
    }
    this.rotationNotified = true;
    this.getUIContext().showAlertDialog({
      title: '账号密钥已更新',
      message: '可能因为你修改了主密码或加密方式。\n请重新登录继续使用，你的数据没有丢失。',
      autoCancel: false,
      confirm: {
        value: '重新登录',
        action: () => {
          VaultStore.clearKeyRotated();
          this.rotationNotified = false;
          this.signOut();
        }
      }
    });
  }

  /** 首次进入保险库时询问是否开启生物识别（每次启动只问一次，优先指纹） */
  private maybePromptBiometric(): void {
    if (this.bioPrompted) {
      return;
    }
    this.bioPrompted = true;
    if (VaultStore.bioEnabled || VaultStore.demo) {
      return;
    }
    const kind: string = this.fpAvailable ? 'fingerprint' : (this.faceAvailable ? 'face' : '');
    if (kind.length === 0) {
      return;
    }
    const label: string = kind === 'face' ? '面容' : '指纹';
    this.getUIContext().showAlertDialog({
      title: `启用${label}解锁`,
      message: `下次打开可以用${label}直接解锁保险库，不必再输入主密码。`,
      autoCancel: true,
      primaryButton: {
        value: '暂不',
        action: () => {
        }
      },
      secondaryButton: {
        value: '启用',
        action: () => {
          this.toggleBiometric(kind, true);
        }
      }
    });
  }

  private toggleBiometric(kind: string, enable: boolean): void {
    this.touch();
    const action: Promise<void> = enable ?
      VaultStore.enableBiometric(kind) : VaultStore.disableBiometric(kind);
    const label: string = kind === 'face' ? '面容' : '指纹';
    action.then(() => {
      this.pullStoreState();
      this.toast(enable ? `已开启${label}解锁` : `已关闭${label}解锁`);
    }).catch((error: Error) => {
      this.pullStoreState();
      this.toast(error.message);
    });
  }

  /** 订阅通知点击事件：应用在后台时也能直接复制密码，不切前台 */
  private subscribeCopyEvent(): void {
    const info: commonEventManager.CommonEventSubscribeInfo = { events: [COPY_EVENT, COPY_TOTP_EVENT] };
    commonEventManager.createSubscriber(info, (err, subscriber) => {
      if (err) {
        return;
      }
      this.copySubscriber = subscriber;
      commonEventManager.subscribe(subscriber, (e, data) => {
        if (e) {
          return;
        }
        const params = data.parameters as Record<string, Object> | undefined;
        if (params === undefined || params === null) {
          return;
        }
        const totpRaw: Object | undefined = params['copyTotpItemId'];
        if (typeof totpRaw === 'string' && (totpRaw as string).length > 0) {
          this.copyTotpById(totpRaw as string);
          return;
        }
        const raw: Object | undefined = params['copyPasswordItemId'];
        if (typeof raw !== 'string' || (raw as string).length === 0) {
          return;
        }
        this.copyPasswordById(raw as string);
      });
    });
  }

  private unsubscribeCopyEvent(): void {
    if (this.copySubscriber === null) {
      return;
    }
    commonEventManager.unsubscribe(this.copySubscriber);
    this.copySubscriber = null;
  }

  /** 按条目 id 复制密码（通知事件与 AppStorage 两条路径共用） */
  private copyPasswordById(id: string): void {
    if (!VaultStore.unlocked) {
      this.toast('请先解锁保险库，再点通知复制密码');
      return;
    }
    let target: VaultItem | null = null;
    for (let i = 0; i < VaultStore.items.length; i++) {
      if (VaultStore.items[i].id === id) {
        target = VaultStore.items[i];
        break;
      }
    }
    if (target === null) {
      this.toast('条目不存在或已删除');
      return;
    }
    if (target.password.length === 0) {
      this.toast('该条目没有密码');
      return;
    }
    const password: string = target.password;
    const totpRaw: string = target.totp.length > 0 ? target.totp.trim() : '';
    copyText(password).then(() => {
      this.toast('密码已复制');
      if (totpRaw.length > 0) {
        this.startTotpNotification(id, totpRaw);
      } else {
        this.stopTotpNotification();
        cancelHints();
      }
    }).catch((e: Error) => {
      this.toast(`复制失败：${e.message}`);
    });
  }

  /** 复制用户名后：优先闪控球，设备/权限不允许时退回通知栏 */
  private startCopyFloatingBall(itemId: string): void {
    if (!VaultStore.floatBallEnabled) {
      this.offerPasswordNotification(itemId);
      return;
    }
    // 重新复制用户名时，先停掉上一轮验证码倒计时，避免两个定时器同时刷文字
    if (this.ballTimer >= 0) {
      clearInterval(this.ballTimer);
      this.ballTimer = -1;
    }
    this.stopBallPulse();
    this.ballName = '';
    for (let i = 0; i < VaultStore.items.length; i++) {
      if (VaultStore.items[i].id === itemId) {
        this.ballName = VaultStore.items[i].name;
        break;
      }
    }
    if (!FloatingBall.supported()) {
      this.offerPasswordNotification(itemId);
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    FloatingBall.ensurePermission(context).then((granted: boolean) => {
      if (!granted || !FloatingBall.supported()) {
        this.offerPasswordNotification(itemId);
        return;
      }
      let startHue: number = Math.random() * 360;
      if (startHue > 338 || startHue < 22) {
        startHue = (startHue + 70) % 360;
      }
      const startBg: string = this.hslToHex(startHue, 0.72, 0.86);
      FloatingBall.start(context, '点此复制密码', this.ballName, startBg, '#1F2937').then((started: boolean) => {
        if (!started) {
          this.offerPasswordNotification(itemId);
          return;
        }
        // 球已经出现，撤掉同名通知，避免重复入口
        this.stopTotpNotification();
        cancelHints();
        this.ballItemId = itemId;
        this.ballMode = 'password';
        this.ballCode = '';
        this.startBallPulse(startHue);
      });
    });
  }

  private offerPasswordNotification(itemId: string): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    offerPasswordCopy(context, itemId, this.notifyKeepSeconds).catch((e: Error) => {
      hilog.error(0x0001, 'LockWarden', 'offer failed: %{public}s', e.message);
    });
  }

  /** 闪控球被点击 */
  private onFloatBallClick(): void {
    if (this.ballMode === 'totp') {
      if (this.ballCode.length === 0) {
        FloatingBall.stop();
        this.resetBall();
        return;
      }
      if (this.ballCode.length > 0) {
        copyText(this.ballCode).then(() => {
          this.toast('验证码已复制');
          FloatingBall.stop();
          this.resetBall();
        }).catch((e: Error) => {
          this.toast(`复制失败：${e.message}`);
        });
      }
      return;
    }
    this.copyPasswordFromBall();
  }

  /** 球的第一阶段：复制密码；带验证器就切到验证码倒计时，否则收球 */
  private copyPasswordFromBall(): void {
    this.stopBallPulse();
    const id: string = this.ballItemId;
    let target: VaultItem | null = null;
    for (let i = 0; i < VaultStore.items.length; i++) {
      if (VaultStore.items[i].id === id) {
        target = VaultStore.items[i];
        break;
      }
    }
    if (target === null || target.password.length === 0) {
      this.toast('该条目没有可复制的密码');
      FloatingBall.stop();
      this.resetBall();
      return;
    }
    const item: VaultItem = target;
    copyText(item.password).then(() => {
      this.toast('密码已复制');
      const raw: string = item.totp.length > 0 ? item.totp.trim() : '';
      if (raw.length > 0) {
        this.enterBallTotp(raw);
      } else {
        FloatingBall.stop();
        this.resetBall();
      }
    }).catch((e: Error) => {
      this.toast(`复制失败：${e.message}`);
    });
  }

  /** 球的第二阶段：显示动态码 + 剩余秒数 */
  private enterBallTotp(raw: string): void {
    let secret: string = '';
    try {
      secret = extractTotpSecret(raw);
    } catch (e) {
      secret = '';
    }
    if (secret.length === 0) {
      FloatingBall.stop();
      this.resetBall();
      return;
    }
    this.ballMode = 'totp';
    const tick = () => {
      if (!FloatingBall.isStarted()) {
        this.resetBall();
        return;
      }
      const remaining: number = secondsRemaining(30);
      if (remaining <= 0) {
        FloatingBall.stop();
        this.resetBall();
        return;
      }
      const code: string = generateTotpSync(secret, 6, 30);
      this.ballCode = code;
      const bg: string = remaining <= 5 ? '#FECACA' : '#DBEAFE';
      const fg: string = remaining <= 5 ? '#B91C1C' : '#1F2937';
      FloatingBall.update(`${code} · ${remaining}s`, this.ballName, bg, fg);
    };
    if (this.ballTimer >= 0) {
      clearInterval(this.ballTimer);
    }
    tick();
    this.ballTimer = setInterval(tick, 1000);
  }

  /**
   * 提示阶段：浅色系流光。
   * 80ms 一帧，色相平滑推进（约 15 秒走完一圈），
   * 跳过红色区间，其余颜色连续过渡。
   */
  private startBallPulse(initialHue: number = -1): void {
    this.stopBallPulse();
    let hue: number = initialHue >= 0 ? initialHue : Math.random() * 360;
    let dir: number = 1;
    const stepPerTick: number = 360 / (15000 / 80); // 15 秒一圈
    this.ballPulseTimer = setInterval(() => {
      if (!FloatingBall.isStarted()) {
        this.stopBallPulse();
        return;
      }
      hue = hue + dir * stepPerTick;
      // 碰到红色区间就反向，颜色始终连续、不出现红色
      if (hue > 338 || hue < 22) {
        dir = -dir;
        hue = hue + dir * stepPerTick * 2;
      }
      hue = (hue + 360) % 360;
      const bg: string = this.hslToHex(hue, 0.72, 0.86);
      FloatingBall.update('点此复制密码', this.ballName, bg, '#1F2937');
    }, 80);
  }

  /** HSL -> #RRGGBB（s、l 取 0~1） */
  private hslToHex(h: number, s: number, l: number): string {
    const c: number = (1 - Math.abs(2 * l - 1)) * s;
    const hp: number = h / 60;
    const x: number = c * (1 - Math.abs(hp % 2 - 1));
    let r: number = 0;
    let g: number = 0;
    let b: number = 0;
    if (hp < 1) {
      r = c;
      g = x;
    } else if (hp < 2) {
      r = x;
      g = c;
    } else if (hp < 3) {
      g = c;
      b = x;
    } else if (hp < 4) {
      g = x;
      b = c;
    } else if (hp < 5) {
      r = x;
      b = c;
    } else {
      r = c;
      b = x;
    }
    const m: number = l - c / 2;
    const toHex = (v: number): string => {
      const n: number = Math.round((v + m) * 255);
      return (n < 16 ? '0' : '') + n.toString(16);
    };
    return ('#' + toHex(r) + toHex(g) + toHex(b)).toUpperCase();
  }

  private stopBallPulse(): void {
    if (this.ballPulseTimer >= 0) {
      clearInterval(this.ballPulseTimer);
      this.ballPulseTimer = -1;
    }
  }

  private resetBall(): void {
    this.stopBallPulse();
    if (this.ballTimer >= 0) {
      clearInterval(this.ballTimer);
      this.ballTimer = -1;
    }
    this.ballMode = '';
    this.ballItemId = '';
    this.ballCode = '';
    this.ballName = '';
  }

  /** 点通知里的「复制验证码」：按条目当前时间重新算码，避免用到过期值 */
  private copyTotpById(id: string): void {
    let target: VaultItem | null = null;
    for (let i = 0; i < VaultStore.items.length; i++) {
      if (VaultStore.items[i].id === id) {
        target = VaultStore.items[i];
        break;
      }
    }
    if (target === null || target.totp.trim().length === 0) {
      this.toast('该条目没有验证器');
      return;
    }
    let secret: string = '';
    try {
      secret = extractTotpSecret(target.totp.trim());
    } catch (e) {
      secret = '';
    }
    if (secret.length === 0) {
      this.toast('验证器密钥无效');
      return;
    }
    const code: string = generateTotpSync(secret, 6, 30);
    copyText(code).then(() => {
      this.toast('验证码已复制');
      // 验证码复制完成即收起通知，不再继续显示倒计时
      this.stopTotpNotification();
      cancelHints();
    }).catch((e: Error) => {
      this.toast(`复制失败：${e.message}`);
    });
  }

  /** 通知栏验证码倒计时：每秒刷新，到期自动关闭 */
  private startTotpNotification(itemId: string, raw: string): void {
    let secret: string = '';
    try {
      secret = extractTotpSecret(raw);
    } catch (e) {
      secret = '';
    }
    if (secret.length === 0) {
      cancelHints();
      return;
    }
    this.stopTotpNotification();
    this.totpNotifyItemId = itemId;
    const tick = () => {
      const remaining: number = secondsRemaining(30);
      if (remaining <= 0) {
        this.stopTotpNotification();
        cancelHints();
        return;
      }
      const code: string = generateTotpSync(secret, 6, 30);
      publishTotpHint(itemId, code, remaining);
    };
    tick();
    this.totpNotifyTimer = setInterval(tick, 1000);
  }

  private stopTotpNotification(): void {
    if (this.totpNotifyTimer >= 0) {
      clearInterval(this.totpNotifyTimer);
      this.totpNotifyTimer = -1;
    }
    this.totpNotifyItemId = '';
  }

  /** 点通知「复制密码」：找到对应条目并复制（需已解锁） */
  /** 解锁后加载本地验证器账号（用 userKey 解密） */
  private loadTotpAccounts(): void {
    if (!VaultStore.unlocked) {
      this.totpAccounts = [];
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    TotpStore.load(context).then(() => {
      this.totpAccounts = TotpStore.accounts.slice(0);
    }).catch(() => {
      this.totpAccounts = [];
    });
  }

  /** 扫码添加验证器：走系统扫码界面，结果应为 otpauth:// 链接 */
  private async scanTotp(): Promise<void> {
    // 电脑、部分无摄像头平板没有 ScanKit：提前拦下，避免弹英文错误
    if (!scanSupported()) {
      this.toast('当前设备不支持扫码，请手动输入密钥');
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: true
    };
    let result: scanBarcode.ScanResult;
    try {
      result = await scanBarcode.startScanForResult(context, options);
    } catch (error) {
      // 用户点返回取消时 ScanKit 抛的是英文错误，这里翻成中文，避免弹英文提示
      const message: string = (error as Error).message === undefined ? '' : (error as Error).message;
      const lower: string = message.toLowerCase();
      if (lower.indexOf('cancel') >= 0 || message.indexOf('取消') >= 0 || lower.indexOf('abort') >= 0) {
        throw new Error('用户取消扫码');
      }
      throw new Error(`扫码失败：${message.length > 0 ? message : '未知错误'}`);
    }
    const raw: string = result.originalValue;
    const parsed: TotpAccount | null = parseOtpauth(raw);
    if (parsed === null) {
      throw new Error('这不是有效的 otpauth 二维码');
    }
    await this.saveTotpAccount(parsed);
  }

  /** 扫码并把原始内容返回给条目编辑器（不在这里落库） */
  private async scanOtpauthRaw(): Promise<string> {
    if (!scanSupported()) {
      throw new Error('当前设备不支持扫码，请手动输入密钥');
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: true
    };
    try {
      const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, options);
      return result.originalValue;
    } catch (error) {
      const message: string = (error as Error).message === undefined ? '' : (error as Error).message;
      const lower: string = message.toLowerCase();
      if (lower.indexOf('cancel') >= 0 || message.indexOf('取消') >= 0 || lower.indexOf('abort') >= 0) {
        throw new Error('已取消扫码');
      }
      throw new Error(`扫码失败：${message.length > 0 ? message : '未知错误'}`);
    }
  }

  /** 保存带验证器密钥的条目后，把账号同步到「验证器」页 */
  private async syncTotpFromDraft(draft: CipherDraft): Promise<void> {
    const raw: string = draft.totp.trim();
    if (raw.length === 0 || !VaultStore.unlocked) {
      return;
    }
    let acc: TotpAccount | null = parseOtpauth(raw);
    if (acc === null) {
      // 允许直接填 Base32：用条目名称/用户名补上发行方和账号
      const cleaned: string = raw.replace(/[\s-]/g, '').toUpperCase();
      if (!/^[A-Z2-7]+$/.test(cleaned)) {
        return;
      }
      acc = {
        id: `t${Date.now()}${Math.floor(Math.random() * 1000)}`,
        issuer: draft.name.trim(),
        account: draft.username.trim(),
        secret: cleaned,
        digits: 6,
        period: 30
      };
    }
    for (let i = 0; i < TotpStore.accounts.length; i++) {
      if (TotpStore.accounts[i].secret === acc.secret) {
        return;
      }
    }
    await TotpStore.add(acc);
    this.totpAccounts = TotpStore.accounts.slice(0);
  }

  /** 手动添加：密钥可以是 Base32，也可以是完整 otpauth 链接 */
  private async addTotp(issuer: string, account: string, secret: string): Promise<void> {
    const text: string = secret.trim();
    if (text.length === 0) {
      throw new Error('请填写密钥');
    }
    if (text.toLowerCase().startsWith('otpauth://')) {
      const parsed: TotpAccount | null = parseOtpauth(text);
      if (parsed === null) {
        throw new Error('otpauth 链接无效');
      }
      if (parsed.issuer.length === 0) {
        parsed.issuer = issuer.trim();
      }
      if (parsed.account.length === 0) {
        parsed.account = account.trim();
      }
      await this.saveTotpAccount(parsed);
      return;
    }
    if (!isBase32LengthValid(text)) {
      throw new Error('密钥长度不对，请确认复制完整（Base32 去掉「=」后长度应为 8 的倍数，或余 2/4/5/7）');
    }
    const acc: TotpAccount = {
      id: `t${Date.now()}`,
      issuer: issuer.trim(),
      account: account.trim(),
      secret: text,
      digits: 6,
      period: 30
    };
    await this.saveTotpAccount(acc);
  }

  private async saveTotpAccount(acc: TotpAccount): Promise<void> {
    generateTotpSync(acc.secret, acc.digits, acc.period);
    await TotpStore.add(acc);
    this.totpAccounts = TotpStore.accounts.slice(0);
    this.toast(`已添加 ${acc.issuer.length > 0 ? acc.issuer : acc.account}`);
  }

  private fileNameOf(uri: string): string {
    const cut: number = uri.lastIndexOf('/');
    const raw: string = cut >= 0 ? uri.substring(cut + 1) : uri;
    try {
      return decodeURIComponent(raw);
    } catch (e) {
      return raw;
    }
  }

  /** 选择文件并上传附件 */
  private async addAttachment(item: VaultItem): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const uris: string[] = await docPicker.select({ maxSelectNumber: 1 });
    if (uris.length === 0) {
      return;
    }
    const file = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(file.fd);
    if (stat.size <= 0) {
      fs.closeSync(file);
      this.toast('文件为空或读取失败');
      return;
    }
    if (stat.size > 500 * 1024 * 1024) {
      fs.closeSync(file);
      this.toast('附件不能超过 500MB');
      return;
    }
    const data: Uint8Array = new Uint8Array(stat.size);
    let offset: number = 0;
    const chunkSize: number = 8 * 1024 * 1024;
    while (offset < stat.size) {
      const length: number = Math.min(chunkSize, stat.size - offset);
      const chunk: ArrayBuffer = new ArrayBuffer(length);
      const read: number = fs.readSync(file.fd, chunk);
      if (read <= 0) {
        break;
      }
      data.set(new Uint8Array(chunk, 0, read), offset);
      offset += read;
    }
    fs.closeSync(file);
    if (offset !== stat.size) {
      this.toast('文件读取失败');
      return;
    }
    const fileName: string = this.fileNameOf(uris[0]);
    this.attachmentBusy = true;
    this.attachmentBusyLabel = '正在上传…';
    this.toast(`正在上传 ${fileName}…`);
    try {
      await VaultStore.uploadAttachment(item.id, fileName, data);
      this.pullStoreState();
      this.toast('附件已上传');
    } finally {
      this.attachmentBusy = false;
      this.attachmentBusyLabel = '';
    }
  }

  /** 下载并保存附件 */
  private async saveAttachment(item: VaultItem, attachment: VaultAttachment): Promise<void> {
    // 先并行发起下载，同时立刻弹保存框，避免用户等待网络/解密
    let pendingError: Error | null = null;
    const pending: Promise<Uint8Array> = VaultStore.downloadAttachment(item.id, attachment)
      .catch((e: Error) => {
        pendingError = e;
        return new Uint8Array(0);
      });
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    let uris: string[] = [];
    try {
      uris = await docPicker.save({ newFileNames: [attachment.fileName] });
    } catch (e) {
      pending.catch(() => {
      });
      return;
    }
    if (uris.length === 0) {
      pending.catch(() => {
      });
      return;
    }
    this.attachmentBusy = true;
    this.attachmentBusyLabel = '正在下载…';
    this.toast(`正在下载 ${attachment.fileName}…`);
    try {
      const data: Uint8Array = await pending;
      if (pendingError !== null) {
        throw pendingError as Error;
      }
      const file = fs.openSync(uris[0],
        fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const bytes: Uint8Array = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
        let written: number = 0;
        const chunkSize: number = 8 * 1024 * 1024;
        while (written < bytes.length) {
          const length: number = Math.min(chunkSize, bytes.length - written);
          const chunk: ArrayBuffer = bytes.slice(written, written + length).buffer as ArrayBuffer;
          const n: number = fs.writeSync(file.fd, chunk);
          if (n <= 0) {
            throw new Error('写入文件失败');
          }
          written += n;
        }
      } finally {
        fs.closeSync(file);
      }
      this.toast('附件已保存');
    } catch (e) {
      try {
        fs.unlinkSync(uris[0]);
      } catch (ignored) {
      }
      throw e as Error;
    } finally {
      this.attachmentBusy = false;
      this.attachmentBusyLabel = '';
    }
  }

  /** 删除附件（二次确认，确认后先从列表隐藏） */
  private async removeAttachment(item: VaultItem, attachment: VaultAttachment): Promise<void> {
    confirmDanger('删除附件', `「${attachment.fileName}」将被删除，无法恢复。`, '删除', () => {
      const attachmentId: string = attachment.id;
      this.attachmentHideIds = this.attachmentHideIds.concat([attachmentId]);
      VaultStore.deleteAttachment(item.id, attachmentId).then(() => {
        this.pullStoreState();
        this.attachmentHideIds = this.attachmentHideIds.filter((id: string) => id !== attachmentId);
        this.toast('附件已删除');
      }).catch((e: Error) => {
        this.attachmentHideIds = this.attachmentHideIds.filter((id: string) => id !== attachmentId);
        this.toast(`删除失败：${e.message}`);
      });
    });
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2200 });
    } catch (e) {
      // 页面已销毁时 PromptAction 会抛异常，忽略即可
    }
  }

  private async doSync(): Promise<void> {
    if (this.syncing) {
      return;
    }
    this.touch();
    this.syncing = true;
    try {
      await VaultStore.sync();
      this.pullStoreState();
      this.toast('同步完成');
    } catch (error) {
      this.toast((error as Error).message);
    } finally {
      this.syncing = false;
    }
  }

  /** 密码学安全随机数：给生成器用 */
  private secureRandom(bound: number): number {
    if (bound <= 0) {
      return 0;
    }
    const bytes: Uint8Array = Bytes.random(4);
    const value: number = (((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) >>> 0);
    return value % bound;
  }

  private lock(): void {
    FloatingBall.stop();
    this.resetBall();
    this.stopTotpNotification();
    cancelHints();
    if (VaultStore.demo) {
      VaultStore.exitDemo();
      this.pullStoreState();
      this.stage = Stage.Setup;
      return;
    }
    VaultStore.lock();
    this.pullStoreState();
    this.stage = Stage.Unlock;
  }

  private async signOut(): Promise<void> {
    VaultStore.exitDemo();
    await VaultStore.signOut();
    this.items = [];
    this.trash = [];
    this.folders = [];
    this.syncAt = 0;
    this.email = '';
    this.server = '';
    this.stage = Stage.Setup;
  }

  /** 启动占位页：转圈 + 出错信息 */
  @Builder
  bootPage() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(Theme.PRIMARY)
      Text('正在初始化…')
        .fontSize(Theme.FONT_CAPTION)
        .fontColor(Theme.TEXT_SECONDARY)
      if (this.bootError.length > 0) {
        Text(this.bootError)
          .fontSize(12)
          .fontColor(Theme.DANGER)
          .padding(12)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Theme.BACKGROUND)
  }

  build() {
    Stack() {
      if (this.stage === Stage.Boot) {
        this.bootPage()
      } else if (this.stage === Stage.Setup) {
        Stack() {
          Column() {
          SetupView({
            initialServer: this.server,
            initialEmail: this.email,
            allowCancel: VaultStore.hasAccount,
            onCancel: () => {
              this.pullStoreState();
              this.stage = Stage.Unlock;
            },
            onReady: (server: string, email: string) => {
              this.server = server;
              this.email = email;
                        this.stage = Stage.Login;
            },
            onDemo: () => {
              VaultStore.loadDemo();
              this.pullStoreState();
              this.stage = Stage.Vault;
            },
            onLocal: () => {
              this.stage = Stage.LocalSetup;
            }
          })
          }
          .width('100%')
          .height('100%')
          .constraintSize({ maxWidth: 560 })
        }
          .width('100%')
          .height('100%')
      } else if (this.stage === Stage.LocalSetup) {
        Stack() {
          Column() {
            LocalSetupView({
              onCreated: () => {
                this.touch();
                this.pullStoreState();
                this.stage = Stage.Vault;
                this.maybePromptBiometric();
              },
              onCancel: () => {
                this.stage = Stage.Setup;
              }
            })
          }
          .width('100%')
          .height('100%')
          .constraintSize({ maxWidth: 560 })
        }
        .width('100%')
        .height('100%')
      } else if (this.stage === Stage.Login || this.stage === Stage.Unlock) {
        Stack() {
          Column() {
          AuthView({
            mode: this.stage === Stage.Login ? 'login' : 'unlock',
            email: VaultStore.localMode ? '本机保险库' : this.email,
            server: VaultStore.localMode ? '数据只保存在这台设备' : this.server,
            bioFingerprint: this.bioFingerprint,
            bioFace: this.bioFace,
            onSuccess: () => {
              this.touch();
              this.pullStoreState();
              this.stage = Stage.Vault;
              this.maybePromptBiometric();
            },
            onSwitchAccount: () => {
              this.stage = Stage.Setup;
            },
            // 左上角返回 / 侧滑返回：回到「连接服务器」页（有账号时那边可「取消」再回解锁）
            onBack: () => {
              this.pullStoreState();
              this.stage = Stage.Setup;
            },
            canGoBack: true
          })
          }
          .width('100%')
          .height('100%')
          .constraintSize({ maxWidth: 560 })
        }
          .width('100%')
          .height('100%')
      } else {
        MainShell({
          bottomInset: this.bottomInset,
          noScreenshot: this.noScreenshot,
          onToggleNoScreenshot: (on: boolean) => {
            this.noScreenshot = on;
            PrivacyMode.set(on).catch(() => {
            });
          },
          items: this.items,
          trash: this.trash,
          folders: this.folders,
          email: this.email,
          server: this.server,
          syncAt: this.syncAt,
          syncing: this.syncing,
          demo: this.demo,
          localMode: this.localMode,
          onDataChanged: () => this.pullStoreState(),
          getAttachments: (itemId: string) => VaultStore.attachmentsOf(itemId),
          attachmentBusy: this.attachmentBusy,
          attachmentBusyLabel: this.attachmentBusyLabel,
          attachmentHideIds: this.attachmentHideIds,
          onAddAttachment: (item: VaultItem) => this.addAttachment(item),
          onDownloadAttachment: (item: VaultItem, attachment: VaultAttachment) =>
            this.saveAttachment(item, attachment),
          onDeleteAttachment: (item: VaultItem, attachment: VaultAttachment) =>
            this.removeAttachment(item, attachment),
        totpAccounts: this.totpAccounts,
        onScanTotp: () => {
          this.scanTotp().catch((e: Error) => this.toast(e.message));
        },
        onAddTotp: (issuer: string, account: string, secret: string) => {
          this.addTotp(issuer, account, secret).catch((e: Error) => this.toast(e.message));
        },
        onDeleteTotp: (id: string) => {
          TotpStore.remove(id).then(() => {
            this.totpAccounts = TotpStore.accounts.slice(0);
            this.toast('已删除');
          }).catch((e: Error) => this.toast(e.message));
        },
          autoLockMinutes: this.autoLockMinutes,
          notifyKeepSeconds: this.notifyKeepSeconds,
          sortMode: this.sortMode,
          bioFingerprint: this.bioFingerprint,
          bioFace: this.bioFace,
          fpAvailable: this.fpAvailable,
          faceAvailable: this.faceAvailable,
          fpReason: this.fpReason,
          faceReason: this.faceReason,
          bioRev: this.bioRev,
          random: (bound: number) => this.secureRandom(bound),
          onSync: () => {
            this.doSync();
          },
          onLock: () => {
            this.lock();
          },
          onSignOut: () => {
            this.signOut();
          },
          onCopy: (label: string, value: string) => {
            this.touch();
            // 复制前详情页已写入来源条目，这里只在复制用户名时提供「复制密码」入口
            const hintItem: string = CopyHint.itemId;
            const isUserName: boolean = label.indexOf('用户名') >= 0;
            const shouldOffer: boolean = isUserName && hintItem.length > 0 && !VaultStore.demo;
            const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
            copyText(value).then(() => {
              this.toast(`${label}已复制`);
              if (shouldOffer) {
                this.startCopyFloatingBall(hintItem);
              }
            }).catch((e: Error) => {
              this.toast(`复制失败：${e.message}`);
            });
          },
          onSaveDraft: (draft: CipherDraft) => {
            this.touch();
            return VaultStore.saveDraft(draft).then(() => {
              return this.syncTotpFromDraft(draft);
            }).then(() => {
              this.pullStoreState();
            });
          },
          onScanTotpForEditor: () => this.scanOtpauthRaw(),
          onDelete: (item: VaultItem) => {
            this.touch();
            return VaultStore.trashItem(item).then(() => {
              this.pullStoreState();
              this.toast('已移到回收站');
            });
          },
          onRestore: (item: VaultItem) => {
            this.touch();
            return VaultStore.restoreItem(item).then(() => {
              this.pullStoreState();
              this.toast('已恢复');
            });
          },
          onPurge: (item: VaultItem) => {
            this.touch();
            return VaultStore.purgeItem(item).then(() => {
              this.pullStoreState();
              this.toast('已彻底删除');
            });
          },
          onToggleFavorite: (item: VaultItem) => {
            this.touch();
            return VaultStore.setFavorite(item, !item.favorite).then(() => {
              this.pullStoreState();
            });
          },
          onBatchFavorite: (items: VaultItem[], favorite: boolean) => {
            this.touch();
            return VaultStore.setFavorites(items, favorite).then(() => {
              this.pullStoreState();
              this.toast(`已${favorite ? '收藏' : '取消收藏'} ${items.length} 项`);
            });
          },
          onBatchDelete: (items: VaultItem[]) => {
            this.touch();
            return VaultStore.trashItems(items).then(() => {
              this.pullStoreState();
              this.toast(`已删除 ${items.length} 项`);
            });
          },
          onBatchRestore: (items: VaultItem[]) => {
            this.touch();
            return VaultStore.restoreItems(items).then(() => {
              this.pullStoreState();
              this.toast(`已恢复 ${items.length} 项`);
            });
          },
          onDeleteFolders: (folders: VaultFolder[]) => {
            this.touch();
            const ids: string[] = [];
            for (let i = 0; i < folders.length; i++) {
              ids.push(folders[i].id);
            }
            const targets: VaultItem[] = [];
            for (let i = 0; i < VaultStore.items.length; i++) {
              if (ids.indexOf(VaultStore.items[i].folderId) >= 0) {
                targets.push(VaultStore.items[i]);
              }
            }
            let step: Promise<void> = targets.length > 0 ?
              VaultStore.trashItems(targets) : new Promise<void>((resolve: () => void) => {
                resolve();
              });
            for (let i = 0; i < folders.length; i++) {
              const folder: VaultFolder = folders[i];
              step = step.then(() => VaultStore.deleteFolder(folder));
            }
            return step.then(() => {
              this.pullStoreState();
              this.toast(targets.length > 0 ?
                `已删除 ${folders.length} 个文件夹，${targets.length} 个条目移到回收站` :
                `已删除 ${folders.length} 个文件夹`);
            });
          },
          onDeleteFolder: (folder: VaultFolder) => {
            this.touch();
            // 文件夹一起删除里面的条目：先整批移到回收站，再删文件夹
            const targets: VaultItem[] = [];
            for (let i = 0; i < VaultStore.items.length; i++) {
              if (VaultStore.items[i].folderId === folder.id) {
                targets.push(VaultStore.items[i]);
              }
            }
            const step: Promise<void> = targets.length > 0 ?
              VaultStore.trashItems(targets) : new Promise<void>((resolve: () => void) => {
                resolve();
              });
            return step.then(() => VaultStore.deleteFolder(folder)).then(() => {
              this.pullStoreState();
              this.toast(targets.length > 0 ?
                `文件夹和 ${targets.length} 个条目已移到回收站` : '文件夹已删除');
            });
          },
          onBatchPurge: (items: VaultItem[]) => {
            this.touch();
            return VaultStore.purgeItems(items).then(() => {
              this.pullStoreState();
              this.toast(`已永久删除 ${items.length} 项`);
            });
          },
          onNotifyKeep: (seconds: number) => {
            VaultStore.setNotifyKeepSeconds(seconds).then(() => {
              this.notifyKeepSeconds = seconds;
              if (seconds <= 0) {
                this.toast('通知已关闭');
              } else {
                const label: string = seconds >= 60 ? `${seconds / 60} 分钟` : `${seconds} 秒`;
                this.toast(`通知保留 ${label}`);
              }
            });
          },
          onAutoLock: (minutes: number) => {
            this.touch();
            VaultStore.setAutoLockMinutes(minutes).then(() => {
              this.autoLockMinutes = minutes;
            });
          },
          onSortChange: (mode: string) => {
            this.touch();
            VaultStore.setSortMode(mode).then(() => {
              this.sortMode = mode;
            });
          },
          onToggleBiometric: (kind: string, enable: boolean) => {
            this.toggleBiometric(kind, enable);
          },
          onCreateFolder: (name: string) => {
            this.touch();
            return VaultStore.createFolder(name).then((id: string) => {
              this.pullStoreState();
              return id;
            });
          },
          // 文件夹改名：接口返回后重新同步，列表里名字随即更新
          onRenameFolder: (folder: VaultFolder, name: string) => {
            this.touch();
            return VaultStore.renameFolder(folder, name).then(() => {
              this.pullStoreState();
            });
          }
        })
      }

    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topInset })
    .backgroundColor(Theme.BACKGROUND)
  }

  /** 全屏布局下量一下状态栏高度，避免内容钻到状态栏底下 */
  private static async measureInsets(host: Index, context: common.UIAbilityContext): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(context);
      const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      host.topInset = host.getUIContext().px2vp(area.topRect.height);
      // 全屏下 TYPE_SYSTEM 的底部高度是 0，底部手势条要用 NAVIGATION_INDICATOR 取
      const nav: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      host.bottomInset = host.getUIContext().px2vp(nav.bottomRect.height);
    } catch (e) {
      host.topInset = 0;
      host.bottomInset = 0;
    }
  }
}
