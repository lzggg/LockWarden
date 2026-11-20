/** 设置页（对应 Bitwarden Android 底部导航的「设置」） */
import { Theme, syncLabel } from '../common/Theme';
import { Icons } from '../common/Icons';
import { ThemeMode } from '../common/ThemeMode';

/** 自动锁定可选时长（分钟）：0=从不，最长 6 小时 */
const LOCK_OPTIONS: number[] = [0, 1, 5, 10, 15, 30, 60, 120, 240, 360];

function lockLabel(minutes: number): string {
  if (minutes <= 0) {
    return '从不';
  }
  if (minutes < 60) {
    return `${minutes} 分钟`;
  }
  return `${minutes / 60} 小时`;
}

@Component
struct SettingsInfoRow {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Row() {
      // 左右两侧统一风格：同字号、同字重、同颜色
      // 左侧标签固定宽度不参与压缩，右侧值吃掉剩余空间，超长时换行（最多 2 行）而不是被截断
      Text(this.label)
        .fontSize(Theme.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_PRIMARY)
        .flexShrink(0)
      Text(this.value)
        .fontSize(Theme.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_PRIMARY)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .maxLines(2)
        .wordBreak(WordBreak.BREAK_ALL)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 12 })
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
  }
}

@Component
struct SettingsActionRow {
  @Prop icon: Resource = $r('sys.symbol.chevron_right');
  @Prop label: string = '';
  @Prop danger: boolean = false;
  /** 右侧摘要文字（为空则不显示） */
  @Prop value: string = '';
  onTap: () => void = () => {
  };

  build() {
    Row({ space: 12 }) {
      SymbolGlyph(this.icon)
        .fontSize(18)
        .fontColor([this.danger ? Theme.DANGER : Theme.TEXT_SECONDARY])
      Text(this.label)
        .fontSize(Theme.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.danger ? Theme.DANGER : Theme.TEXT_PRIMARY)
        .layoutWeight(1)
      if (this.value.length > 0) {
        Text(this.value)
          .fontSize(13)
          .fontWeight(FontWeight.Regular)
          .fontColor(Theme.TEXT_SECONDARY)
      }
      SymbolGlyph(Icons.chevron)
        .fontSize(14)
        .fontColor([Theme.TEXT_HINT])
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .onClick(() => this.onTap())
  }
}

@Component
export struct SettingsView {
  @Prop email: string = '';
  @Prop server: string = '';
  @Prop syncAt: number = 0;
  @Prop itemCount: number = 0;
  @Prop demo: boolean = false;
  @Prop localMode: boolean = false;

  @Prop autoLockMinutes: number = 5;
  @Prop trashCount: number = 0;
  /** 当前外观模式（跟随系统 / 明亮 / 深色） */
  @State themeMode: string = ThemeMode.mode;
  /** 驱动"上次同步"随时间和保险库页一致地刷新 */
  @State tick: number = 0;
  private clockTimer: number = -1;

  aboutToAppear(): void {
    this.clockTimer = setInterval(() => {
      this.tick = this.tick + 1;
    }, 30000);
  }

  aboutToDisappear(): void {
    if (this.clockTimer >= 0) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
  }

  /** 与保险库页同一套文案：1 分钟内「刚刚同步」，否则「同步完成 年月日 时分」 */
  private syncText(): string {
    const stamp: number = this.tick;
    if (this.localMode) {
      return '无需同步（本机存储）';
    }
    return syncLabel(this.syncAt + 0 * stamp, false);
  }

  onSync: () => void = () => {
  };
  onLock: () => void = () => {
  };
  onOpenTrash: () => void = () => {
  };
  onOpenFolders: () => void = () => {
  };
  onAutoLock: (minutes: number) => void = () => {
  };
  /** 打开安全子页面（含生物识别） */
  onOpenBiometric: () => void = () => {
  };

  /** 下拉选项文案 */
  private lockOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let i = 0; i < LOCK_OPTIONS.length; i++) {
      const option: SelectOption = { value: lockLabel(LOCK_OPTIONS[i]) };
      options.push(option);
    }
    return options;
  }

  /** 当前取值在下拉里的下标 */
  private lockIndex(): number {
    for (let i = 0; i < LOCK_OPTIONS.length; i++) {
      if (LOCK_OPTIONS[i] === this.autoLockMinutes) {
        return i;
      }
    }
    return 0;
  }

  build() {
    Column() {
      Row() {
        Text('设置')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
        if (this.demo) {
          Text('演示数据')
            .fontSize(11)
            .fontColor('#B26A00')
            .backgroundColor('#FFF3E0')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(8)
            .margin({ left: 10 })
        }
      }
      .width('100%')
      .padding({ top: 8, bottom: 16 })

      Scroll() {
        Column() {
          Column() {
            SettingsInfoRow({
              label: '账号',
              value: this.demo ? '演示模式' : (this.localMode ? '本机保险库' : this.email)
            })
            Divider().color(Theme.DIVIDER)
            SettingsInfoRow({
              label: '服务器',
              value: this.localMode ? '未使用（本机存储）' : (this.server.length > 0 ? this.server : '未连接')
            })
            Divider().color(Theme.DIVIDER)
            SettingsInfoRow({ label: '条目数量', value: `${this.itemCount}` })
            Divider().color(Theme.DIVIDER)
            SettingsInfoRow({ label: '上次同步', value: this.syncText() })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .borderRadius(Theme.RADIUS)
          .backgroundColor(Theme.CARD)
          .margin({ bottom: 16 })

          // 外观 + 自动锁定（同一张卡片，用分隔线分开）
          Column() {
            Row() {
              Text('外观')
                .fontSize(Theme.FONT_BODY)
                .fontColor(Theme.TEXT_PRIMARY)
              Blank()
              Select([
                { value: '跟随系统' },
                { value: '明亮' },
                { value: '深色' }
              ])
                .selected(ThemeMode.index(this.themeMode))
                .value(ThemeMode.label(this.themeMode))
                .font({ size: 14 })
                .fontColor(Theme.PRIMARY)
        .font({ size: Theme.FONT_BODY, weight: FontWeight.Medium })
                .optionFont({ size: 14 })
                .selectedOptionFont({ size: 14 })
                .backgroundColor(Color.Transparent)
                .onSelect((index: number) => {
                  const mode: string = ThemeMode.fromIndex(index);
                  this.themeMode = mode;
                  ThemeMode.set(mode);
                })
            }
            .width('100%')
            .height(44)

            Divider().color(Theme.DIVIDER).margin({ left: 16, right: 16 })

            Row() {
              Text('自动锁定')
                .fontSize(Theme.FONT_BODY)
                .fontColor(Theme.TEXT_PRIMARY)
              Blank()
              Select(this.lockOptions())
                .selected(this.lockIndex())
                .value(lockLabel(this.autoLockMinutes))
                .font({ size: 14 })
                .fontColor(Theme.PRIMARY)
        .font({ size: Theme.FONT_BODY, weight: FontWeight.Medium })
                .optionFont({ size: 14 })
                .selectedOptionFont({ size: 14 })
                .backgroundColor(Color.Transparent)
                .onSelect((index: number) => {
                  this.onAutoLock(LOCK_OPTIONS[index]);
                })
            }
            .width('100%')
            .height(44)
          }
          .width('100%')
          .padding({ left: 16, right: 8 })
          .borderRadius(Theme.RADIUS)
          .backgroundColor(Theme.CARD)
          .margin({ bottom: 16 })


          // 生物识别 + 操作入口（同一张卡片）
          Column() {
            SettingsActionRow({
              icon: Icons.lock,
              label: '安全',
              onTap: () => this.onOpenBiometric()
            })
            Divider().color(Theme.DIVIDER)
            SettingsActionRow({
              icon: Icons.folder,
              label: '文件夹管理',
              onTap: () => this.onOpenFolders()
            })
            Divider().color(Theme.DIVIDER)
            SettingsActionRow({
              icon: Icons.trash,
              label: this.trashCount > 0 ? `回收站（${this.trashCount}）` : '回收站',
              onTap: () => this.onOpenTrash()
            })
            Divider().color(Theme.DIVIDER)
            SettingsActionRow({
              icon: Icons.vault,
              label: '锁定保险库',
              onTap: () => this.onLock()
            })
            SettingsActionRow({
              icon: Icons.refresh,
              label: '立即同步',
              onTap: () => this.onSync()
            })
            Divider().color(Theme.DIVIDER)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .borderRadius(Theme.RADIUS)
          .backgroundColor(Theme.CARD)

          Column({ space: 6 }) {
            Text('LockWarden')
              .fontSize(Theme.FONT_CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_SECONDARY)
            Text('兼容 Bitwarden / Vaultwarden 协议的自建密码服务器客户端')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
            Text('主密码与账号密钥不落盘；本地仅保存被加密的账号密钥与刷新令牌')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .margin({ top: 24 })
        }
        .width('100%')
        .padding({ bottom: 120 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: Theme.PAGE_PADDING, right: Theme.PAGE_PADDING })
    .backgroundColor(Theme.BACKGROUND)
  }
}
