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
import { window } from '@kit.ArkUI';
import { Stage, VaultItem, VaultFolder, CipherDraft } from '../common/Models';
import { VaultStore } from '../common/VaultStore';
import { TotpStore, TotpAccount, parseOtpauth } from '../common/TotpStore';
import { generateTotpSync, isBase32LengthValid } from '../common/Totp';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { Theme } from '../common/Theme';
import { copyText } from '../common/Clipboard';
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
  @State items: VaultItem[] = [];
  @State trash: VaultItem[] = [];
  @State folders: VaultFolder[] = [];
  @State syncAt: number = 0;
  @State syncing: boolean = false;
  @State email: string = '';
  @State server: string = '';
  @State autoLockMinutes: number = 5;
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

  private lastActive: number = Date.now();
  private idleTimer: number = -1;
  private bioPrompted: boolean = false;

  aboutToAppear(): void {
    this.bootstrap();
    this.startIdleWatch();
    this.fpAvailable = Biometric.fingerprintAvailable();
    this.faceAvailable = Biometric.faceAvailable();
    this.fpReason = Biometric.fingerprintReason();
    this.faceReason = Biometric.faceReason();
  }

  aboutToDisappear(): void {
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
    this.sortMode = VaultStore.sortMode;
    this.bioFingerprint = VaultStore.bioFingerprint;
    this.bioFace = VaultStore.bioFace;
    this.bioEnabled = VaultStore.bioEnabled;
    this.bioRev = this.bioRev + 1;
    this.demo = VaultStore.demo;
    this.localMode = VaultStore.localMode;
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
    AlertDialog.show({
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

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2200 });
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
            copyText(value).then(() => {
              this.toast(`${label}已复制`);
            }).catch((e: Error) => {
              this.toast(`复制失败：${e.message}`);
            });
          },
          onSaveDraft: (draft: CipherDraft) => {
            this.touch();
            return VaultStore.saveDraft(draft).then(() => {
              this.pullStoreState();
            });
          },
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
      host.topInset = px2vp(area.topRect.height);
      // 全屏下 TYPE_SYSTEM 的底部高度是 0，底部手势条要用 NAVIGATION_INDICATOR 取
      const nav: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      host.bottomInset = px2vp(nav.bottomRect.height);
    } catch (e) {
      host.topInset = 0;
      host.bottomInset = 0;
    }
  }
}
