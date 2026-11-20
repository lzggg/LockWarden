/**
 * 安全设置页（从设置页「安全」进入）。
 *
 * 目前包含「生物识别」一节（指纹 / 面容解锁）；后续的更多安全项都可以加在这里。
 * 设置页只留一行「安全」入口 + 当前状态摘要。
 */
import { Theme } from '../common/Theme';
import { Icons } from '../common/Icons';
import { VaultStore } from '../common/VaultStore';
import { confirmDanger } from '../common/Dialog';
import { VaultIO, PickedFile } from '../common/VaultIO';
import { EyeToggle } from './EyeToggle';
import { LOCK_OPTIONS, lockLabel, lockOptions, lockIndex } from '../common/LockOptions';

/** 单条开关行（独立组件：@Builder 的按值参数不会刷新开关状态），生物识别与隐私共用 */
@Component
struct ToggleRow {
  /** 左侧图标：指纹用 touchid，面容用 face */
  @Prop icon: Resource = Icons.touchId;
  @Prop label: string = '';
  @Prop desc: string = '';
  @Prop @Watch('syncFromProp') on: boolean = false;
  @Prop @Watch('syncFromProp') rev: number = 0;
  @Prop interactable: boolean = true;
  @State internalOn: boolean = false;
  onToggle: (on: boolean) => void = () => {
  };

  aboutToAppear(): void {
    this.internalOn = this.on;
  }

  /** 父组件每次尝试后都会递增 rev，即使 on 没变也把开关拉回真实状态 */
  syncFromProp(): void {
    this.internalOn = this.on;
  }

  build() {
    Row() {
      SymbolGlyph(this.icon)
        .fontSize(18)
        .fontColor([Theme.TEXT_SECONDARY])
      Column({ space: 3 }) {
        Text(this.label)
          .fontSize(Theme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY)
        Text(this.desc)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_HINT)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      Toggle({ type: ToggleType.Switch, isOn: $$this.internalOn })
        .selectedColor(Theme.PRIMARY)
        .enabled(this.interactable)
        .onChange((value: boolean) => {
          // 父组件回写开关状态时也会触发 onChange，值与真实状态相同则忽略
          if (value === this.on) {
            return;
          }
          this.onToggle(value);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }
}

/**
 * 本机模式下的「清除并退出」二次确认。
 * 本地没有服务端副本，删除即不可恢复，因此用红色警示区 + 不可逆提示 + 红色按钮。
 */
/** 剪贴板自动清除可选秒数：0 = 从不清除 */
const CLIP_OPTIONS: number[] = [0, 30, 60, 120, 300];

function clipLabel(seconds: number): string {
  if (seconds <= 0) {
    return '从不';
  }
  if (seconds < 60) {
    return `${seconds} 秒`;
  }
  return `${seconds / 60} 分钟`;
}

function clipOptions(): SelectOption[] {
  const list: SelectOption[] = [];
  for (let i = 0; i < CLIP_OPTIONS.length; i++) {
    list.push({ value: clipLabel(CLIP_OPTIONS[i]) });
  }
  return list;
}

function clipIndex(seconds: number): number {
  const found: number = CLIP_OPTIONS.indexOf(seconds);
  return found < 0 ? 1 : found;
}

@CustomDialog
struct ClearLocalVaultDialog {
  controller?: CustomDialogController;
  onConfirm: () => void = () => {
  };

  build() {
    Column({ space: 14 }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text('!')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(24)
            .height(24)
            .textAlign(TextAlign.Center)
            .borderRadius(12)
            .backgroundColor(Theme.DANGER)
          Text('清除后无法找回')
            .fontSize(Theme.FONT_BODY)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.DANGER)
        }
        .width('100%')

        Text('这是仅在本机使用的保险库，数据只加密保存在这台设备上，没有任何服务器副本。')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_SECONDARY)
          .lineHeight(19)
          .width('100%')
        Text('清除并退出后，条目、文件夹与设置会被永久删除，且无法恢复。')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.DANGER)
          .lineHeight(19)
          .width('100%')
        Text('验证器账号只保存在本机（不会同步到服务器），退出并清除不会删除它们；但卸载应用或在系统设置里清除应用数据后，验证器会丢失。')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.DANGER)
          .lineHeight(19)
          .width('100%')
        Text('如果还需要这些数据，请先点「取消」，把它们备份好再回来。')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_SECONDARY)
          .lineHeight(19)
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .borderRadius(Theme.RADIUS_SMALL)
      .backgroundColor(Theme.TINT)

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .borderRadius(22)
          .backgroundColor(Theme.CARD)
          .fontColor(Theme.TEXT_PRIMARY)
          .fontSize(Theme.FONT_BODY)
          .onClick(() => {
            this.controller?.close();
          })
        Button('永久删除并退出')
          .layoutWeight(1)
          .height(44)
          .borderRadius(22)
          .backgroundColor(Theme.DANGER)
          .fontColor(Color.White)
          .fontSize(Theme.FONT_BODY)
          .onClick(() => {
            this.controller?.close();
            this.onConfirm();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.BACKGROUND)
  }
}

/** 选择导出格式 */
@CustomDialog
struct ExportFormatDialog {
  controller?: CustomDialogController;
  onJson: () => void = () => {
  };
  onCsv: () => void = () => {
  };

  build() {
    Column({ space: 14 }) {
      Text('导出保险库')
        .fontSize(Theme.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT_PRIMARY)
        .width('100%')
      Text('导出文件是明文，包含全部密码。请只在安全的位置保存，用完及时删除。')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.DANGER)
        .lineHeight(19)
        .width('100%')

      Column({ space: 10 }) {
        Button('导出为 .json（Bitwarden 兼容）')
          .width('100%')
          .height(46)
          .borderRadius(23)
          .backgroundColor(Theme.PRIMARY)
          .fontColor(Color.White)
          .fontSize(Theme.FONT_BODY)
          .onClick(() => {
            this.controller?.close();
            this.onJson();
          })
        Button('导出为 .csv（表格通用）')
          .width('100%')
          .height(46)
          .borderRadius(23)
          .backgroundColor(Theme.TINT)
          .fontColor(Theme.PRIMARY)
          .fontSize(Theme.FONT_BODY)
          .onClick(() => {
            this.controller?.close();
            this.onCsv();
          })
        Button('取消')
          .width('100%')
          .height(46)
          .borderRadius(23)
          .backgroundColor(Theme.CARD)
          .fontColor(Theme.TEXT_PRIMARY)
          .fontSize(Theme.FONT_BODY)
          .onClick(() => {
            this.controller?.close();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.BACKGROUND)
  }
}

/** 敏感操作前验证主密码（导出、清除本机数据共用） */
@CustomDialog
struct PasswordCheckDialog {
  controller?: CustomDialogController;
  /** 标题、说明、确认按钮文案由调用方决定 */
  @Prop title: string = '验证主密码';
  @Prop message: string = '';
  @Prop confirmText: string = '验证并继续';
  verify: (password: string) => Promise<boolean> = () => Promise.resolve(false);
  onPassed: () => void = () => {
  };

  @State password: string = '';
  @State revealed: boolean = false;
  @State busy: boolean = false;
  @State error: string = '';

  private async confirm(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.password.length === 0) {
      this.error = '请输入主密码';
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const ok: boolean = await this.verify(this.password);
      if (ok) {
        this.controller?.close();
        this.onPassed();
      } else {
        this.error = '主密码不正确，请重试';
      }
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column({ space: 14 }) {
      Text(this.title)
        .fontSize(Theme.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT_PRIMARY)
        .width('100%')
      Text(this.message)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_SECONDARY)
        .lineHeight(19)
        .width('100%')

      Row({ space: 8 }) {
        TextInput({ text: this.password, placeholder: '主密码' })
          .type(this.revealed ? InputType.Normal : InputType.Password)
          .showPasswordIcon(false)
          .height(46)
          .layoutWeight(1)
          .backgroundColor(Theme.CARD)
          .borderRadius(12)
          .fontSize(Theme.FONT_BODY)
          .fontColor(Theme.TEXT_PRIMARY)
          .placeholderColor(Theme.TEXT_HINT)
          .onChange((value: string) => {
            this.password = value;
            this.error = '';
          })
        EyeToggle({
          revealed: this.revealed,
          onToggle: () => {
            this.revealed = !this.revealed;
          }
        })
      }
      .width('100%')

      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.DANGER)
          .width('100%')
      }

      Column({ space: 10 }) {
        Button(this.busy ? '验证中…' : this.confirmText)
          .width('100%')
          .height(46)
          .borderRadius(23)
          .backgroundColor(Theme.PRIMARY)
          .fontColor(Color.White)
          .fontSize(Theme.FONT_BODY)
          .enabled(!this.busy)
          .onClick(() => {
            this.confirm();
          })
        Button('取消')
          .width('100%')
          .height(46)
          .borderRadius(23)
          .backgroundColor(Theme.CARD)
          .fontColor(Theme.TEXT_PRIMARY)
          .fontSize(Theme.FONT_BODY)
          .onClick(() => {
            this.controller?.close();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.BACKGROUND)
  }
}

@Component
export struct SecurityView {
  @Prop bioFingerprint: boolean = false;
  @Prop bioFace: boolean = false;
  @Prop fpAvailable: boolean = false;
  @Prop faceAvailable: boolean = false;
  @Prop fpReason: string = '';
  @Prop faceReason: string = '';
  @Prop bioRev: number = 0;
  /** 禁止截屏 */
  @Prop noScreenshot: boolean = false;
  /** 自动锁定分钟数（0 = 从不） */
  @Prop autoLockMinutes: number = 5;

  onBack: () => void = () => {
  };
  onToggleNoScreenshot: (on: boolean) => void = () => {
  };
  onAutoLock: (minutes: number) => void = () => {
  };
  onToggleBiometric: (kind: string, enable: boolean) => void = () => {
  };
  /** 打开「修改主密码」页 */
  onChangePassword: () => void = () => {
  };
  /** 是否仅本机模式（决定清除数据的提示强度） */
  @Prop localMode: boolean = false;
  /** 退出并清除本机数据 */
  onSignOut: () => void = () => {
  };
  /** 导入完成后通知外层刷新列表 */
  onImported: () => void = () => {
  };

  /** 忙状态（导入/导出进行中） */
  @State ioBusy: boolean = false;
  /** 剪贴板自动清除秒数（0 = 从不） */
  @State clipSeconds: number = VaultStore.clipboardClearSeconds;
  /** 待导出格式：false=json，true=csv（进验证对话框后才知道结果） */
  private pendingCsv: boolean = false;

  private exportDialog: CustomDialogController = new CustomDialogController({
    builder: ExportFormatDialog({
      onJson: () => {
        this.pendingCsv = false;
        this.exportAuth.open();
      },
      onCsv: () => {
        this.pendingCsv = true;
        this.exportAuth.open();
      }
    }),
    autoCancel: true,
    customStyle: true
  });

  /** 本机模式的强提醒对话框 */
  private clearDialog: CustomDialogController = new CustomDialogController({
    builder: ClearLocalVaultDialog({
      onConfirm: () => this.requirePasswordThenClear()
    }),
    autoCancel: true,
    customStyle: true
  });

  /** 导出前的主密码验证 */
  private exportAuth: CustomDialogController = new CustomDialogController({
    builder: PasswordCheckDialog({
      title: '验证主密码',
      message: '导出的文件是明文密码库，请先输入主密码确认是本人操作。',
      confirmText: '验证并导出',
      verify: (password: string): Promise<boolean> => VaultStore.verifyMasterPassword(password),
      onPassed: () => {
        this.doExport(this.pendingCsv);
      }
    }),
    autoCancel: true,
    customStyle: true
  });

  /** 清除本机数据前的主密码验证 */
  private clearAuth: CustomDialogController = new CustomDialogController({
    builder: PasswordCheckDialog({
      title: '验证主密码',
      message: '即将清除本机数据且无法恢复，请输入主密码确认是本人操作。',
      confirmText: '验证并清除',
      verify: (password: string): Promise<boolean> => VaultStore.verifyMasterPassword(password),
      onPassed: () => this.onSignOut()
    }),
    autoCancel: true,
    customStyle: true
  });

  /** 清除数据前统一走主密码验证（演示模式没有主密码，直接清除） */
  private requirePasswordThenClear(): void {
    if (VaultStore.demo) {
      this.onSignOut();
      return;
    }
    this.clearAuth.open();
  }

  /** 可点击的设置行：图标 + 标题 + 说明 + 右箭头 */
  @Builder
  actionRow(icon: Resource, label: string, desc: string) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([Theme.TEXT_SECONDARY])
        .width(24)
      Column({ space: 2 }) {
        Text(label)
          .fontSize(Theme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')
        Text(desc)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_HINT)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph(Icons.chevron)
        .fontSize(16)
        .fontColor([Theme.TEXT_HINT])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick(() => this.onChangePassword())
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2500 });
  }

  /** 导出：json / csv */
  private async doExport(csv: boolean): Promise<void> {
    if (this.ioBusy) {
      return;
    }
    this.ioBusy = true;
    try {
      const content: string = csv ? VaultIO.exportCsv() : VaultIO.exportJson();
      const stamp: string = new Date().toISOString().substring(0, 10).split('-').join('');
      const name: string = `lockwarden-${stamp}.${csv ? 'csv' : 'json'}`;
      const saved: string = await VaultIO.saveToFile(name, content);
      this.toast(saved.length > 0 ? `已导出 ${VaultStore.items.length} 条到 ${saved}` : '已取消导出');
    } catch (e) {
      this.toast(`导出失败：${(e as Error).message}`);
    } finally {
      this.ioBusy = false;
    }
  }

  /** 导入：按文件后缀选择解析方式 */
  private async doImport(): Promise<void> {
    if (this.ioBusy) {
      return;
    }
    this.ioBusy = true;
    try {
      const picked: PickedFile = await VaultIO.pickFile();
      if (picked.name.length === 0) {
        this.toast('已取消导入');
        return;
      }
      const csv: boolean = VaultIO.isCsvName(picked.name);
      const result = await VaultIO.importText(picked.text, csv);
      let message: string = `已导入 ${result.imported} 条`;
      if (result.folders > 0) {
        message += `，新建 ${result.folders} 个文件夹`;
      }
      if (result.skipped > 0) {
        message += `，跳过 ${result.skipped} 条（缺名称）`;
      }
      this.toast(message);
      // 导入是直接写 store，页面状态需要重新拉一次才会立刻显示
      this.onImported();
    } catch (e) {
      this.toast(`导入失败：${(e as Error).message}`);
    } finally {
      this.ioBusy = false;
    }
  }

  build() {
    Column() {
      // 返回
      Row({ space: 4 }) {
        SymbolGlyph(Icons.chevron)
          .fontSize(16)
          .fontColor([Theme.PRIMARY])
          .rotate({ angle: 180 })
        Text('设置')
          .fontSize(Theme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.PRIMARY)
      }
      .width('100%')
      .height(48)
      .onClick(() => this.onBack())

      // 内容较多（生物识别 / 隐私 / 主密码 / 数据 / 退出），统一放进 Scroll
      Scroll() {
        Column() {
      Text('安全')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT_PRIMARY)
        .width('100%')
      Text('解锁方式与本地安全设置')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
        .margin({ top: 4, bottom: 16 })

      // 小节标题
      Text('生物识别')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
        .margin({ left: 4, bottom: 8 })

      Column() {
        ToggleRow({
          icon: Icons.touchId,
          label: '指纹解锁',
          desc: this.fpAvailable ?
            (this.bioFingerprint ? '已开启，解锁时验证指纹' : '用指纹解锁保险库') :
            (this.fpReason.length > 0 ? this.fpReason : '本机不支持指纹'),
          on: this.bioFingerprint,
          rev: this.bioRev,
          interactable: this.fpAvailable || this.bioFingerprint,
          onToggle: (on: boolean) => {
            this.onToggleBiometric('fingerprint', on);
          }
        })
        Divider().color(Theme.DIVIDER).margin({ left: 16, right: 16 })
        ToggleRow({
          icon: Icons.faceId,
          label: '面容解锁',
          desc: this.faceAvailable ?
            (this.bioFace ? '已开启，解锁时验证面容' : '用面容解锁保险库') :
            (this.faceReason.length > 0 ? this.faceReason : '本机不支持面容'),
          on: this.bioFace,
          rev: this.bioRev,
          interactable: this.faceAvailable || this.bioFace,
          onToggle: (on: boolean) => {
            this.onToggleBiometric('face', on);
          }
        })
      }
      .width('100%')
      .borderRadius(Theme.RADIUS)
      .backgroundColor(Theme.CARD)

      Text('开启后，解锁页会出现对应的指纹 / 面容按钮，点一下才会验证；也可以直接输入主密码。')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
        .margin({ top: 12 })

      // 自动锁定 / 截屏 / 剪贴板：三类"自动与隐私"设置放同一张卡片
      Text('自动与隐私')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
        .margin({ left: 4, top: 24, bottom: 8 })

      Column() {
        Row({ space: 12 }) {
          SymbolGlyph(Icons.timer)
            .fontSize(20)
            .fontColor([Theme.TEXT_SECONDARY])
            .width(24)
          Column({ space: 2 }) {
            Text('自动锁定')
              .fontSize(Theme.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
              .width('100%')
            Text(this.autoLockMinutes < 0 ? '退出应用时立即锁定' :
              (this.autoLockMinutes === 0 ? '不会自动锁定' : `离开应用超过 ${lockLabel(this.autoLockMinutes)}自动锁定`))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_HINT)
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Select(lockOptions())
            .selected(lockIndex(this.autoLockMinutes))
            .value(lockLabel(this.autoLockMinutes))
            .font({ size: Theme.FONT_BODY, weight: FontWeight.Medium })
            .fontColor(Theme.PRIMARY)
            .optionFont({ size: 14 })
            .selectedOptionFont({ size: 14 })
            .backgroundColor(Color.Transparent)
            .onSelect((index: number) => {
              this.onAutoLock(LOCK_OPTIONS[index]);
            })
        }
        .width('100%')
        .padding({ left: 16, right: 8, top: 12, bottom: 12 })

        Divider().color(Theme.DIVIDER).margin({ left: 16, right: 16 })

        Row({ space: 12 }) {
          SymbolGlyph(Icons.clipboard)
            .fontSize(20)
            .fontColor([Theme.TEXT_SECONDARY])
            .width(24)
          Column({ space: 2 }) {
            Text('自动清除剪贴板')
              .fontSize(Theme.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
              .width('100%')
            Text(this.clipSeconds > 0 ?
              `复制密码后 ${clipLabel(this.clipSeconds)}自动清空` :
              '不会自动清空剪贴板')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_HINT)
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Select(clipOptions())
            .selected(clipIndex(this.clipSeconds))
            .value(clipLabel(this.clipSeconds))
            .font({ size: Theme.FONT_BODY, weight: FontWeight.Medium })
            .fontColor(Theme.PRIMARY)
            .optionFont({ size: 14 })
            .selectedOptionFont({ size: 14 })
            .backgroundColor(Color.Transparent)
            .onSelect((index: number) => {
              const seconds: number = CLIP_OPTIONS[index];
              this.clipSeconds = seconds;
              VaultStore.setClipboardClearSeconds(seconds);
            })
        }
        .width('100%')
        .padding({ left: 16, right: 8, top: 12, bottom: 12 })

        Divider().color(Theme.DIVIDER).margin({ left: 16, right: 16 })

        ToggleRow({
          icon: Icons.privacy,
          label: '不允许截图',
          desc: this.noScreenshot ?
            '已开启，系统截屏与录屏会显示为黑屏' :
            '开启后，系统截屏与录屏会显示为黑屏',
          on: this.noScreenshot,
          rev: 0,
          interactable: true,
          onToggle: (on: boolean) => {
            this.onToggleNoScreenshot(on);
          }
        })
      }
      .width('100%')
      .borderRadius(Theme.RADIUS)
      .backgroundColor(Theme.CARD)


      // 主密码
      Text('主密码')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
        .margin({ left: 4, top: 24, bottom: 8 })

      Column() {
        this.actionRow(Icons.lockOpen, '修改主密码',
          VaultStore.localMode ? '验证当前主密码后设置新的主密码' : '服务器模式需到网页端修改')
      }
      .width('100%')
      .borderRadius(Theme.RADIUS)
      .backgroundColor(Theme.CARD)

      Text(VaultStore.localMode ?
        '本机保险库的主密码只存在这台设备，修改后旧密码立即失效。' :
        '主密码由服务器统一管理，请到网页端「账户设置」里修改，改完用新密码解锁。')
        .fontSize(12)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
        .lineHeight(18)
        .margin({ top: 12 })

      // 数据导入/导出
      Text('数据')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
        .margin({ left: 4, top: 24, bottom: 8 })

      Column() {
        Row({ space: 12 }) {
          SymbolGlyph(Icons.copy)
            .fontSize(20)
            .fontColor([Theme.TEXT_SECONDARY])
            .width(24)
          Column({ space: 2 }) {
            Text('导出保险库')
              .fontSize(Theme.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
              .width('100%')
            Text('支持 .json / .csv，导出内容为明文')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_HINT)
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          SymbolGlyph(Icons.chevron)
            .fontSize(16)
            .fontColor([Theme.TEXT_HINT])
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .onClick(() => {
          if (!this.ioBusy) {
            this.exportDialog.open();
          }
        })

        Divider().color(Theme.DIVIDER).margin({ left: 16, right: 16 })

        Row({ space: 12 }) {
          SymbolGlyph(Icons.vault)
            .fontSize(20)
            .fontColor([Theme.TEXT_SECONDARY])
            .width(24)
          Column({ space: 2 }) {
            Text('导入数据')
              .fontSize(Theme.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
              .width('100%')
            Text(this.ioBusy ? '处理中…' : '选择 .json / .csv 文件')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_HINT)
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          SymbolGlyph(Icons.chevron)
            .fontSize(16)
            .fontColor([Theme.TEXT_HINT])
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .onClick(() => {
          this.doImport();
        })
      }
      .width('100%')
      .borderRadius(Theme.RADIUS)
      .backgroundColor(Theme.CARD)

      Text('导入会把文件里的条目逐条写入当前保险库（本机/服务器模式都支持）；导出文件不加密，请注意保管。')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
        .lineHeight(18)
        .margin({ top: 12 })

      // 危险操作
      Text('退出')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
        .margin({ left: 4, top: 24, bottom: 8 })

      Column() {
        Row({ space: 12 }) {
          SymbolGlyph(Icons.close)
            .fontSize(20)
            .fontColor([Theme.DANGER])
            .width(24)
          Column({ space: 2 }) {
            Text('退出并清除本机数据')
              .fontSize(Theme.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.DANGER)
              .width('100%')
            Text(this.localMode ? '本机数据会被永久删除，无法恢复' : '仅清除本机登录状态，服务器数据不受影响')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_HINT)
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          SymbolGlyph(Icons.chevron)
            .fontSize(16)
            .fontColor([Theme.TEXT_HINT])
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .onClick(() => {
          if (this.localMode) {
            this.clearDialog.open();
          } else {
            confirmDanger('退出登录？',
              '将从本机清除登录状态与缓存数据；服务器上的保险库不受影响，之后可以重新登录。验证器账号只保存在本机，退出登录不会删除；卸载应用或在系统设置里清除应用数据后会丢失。',
              '退出', () => this.requirePasswordThenClear());
          }
        })
      }
      .width('100%')
      .borderRadius(Theme.RADIUS)
      .backgroundColor(Theme.CARD)

      Text(this.localMode ?
        '这是仅在本机使用的保险库，清除后没有任何副本可以恢复。验证器账号也只在本机，卸载应用或清除应用数据会丢失。' :
        '退出后本机不再保留登录状态，重新登录即可继续使用。验证器账号只保存在本机，不会同步到服务器。')
        .fontSize(12)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
        .lineHeight(18)
        .margin({ top: 12 })

        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: Theme.PAGE_PADDING, right: Theme.PAGE_PADDING })
    .backgroundColor(Theme.BACKGROUND)
    .parallelGesture(
      PanGesture({ direction: PanDirection.Right, distance: 30 })
        .onActionEnd((event: GestureEvent) => {
          if (event.offsetX > 120) {
            this.onBack();
          }
        })
    )
  }
}
