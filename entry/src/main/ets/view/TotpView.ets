/**
 * 验证器（Authenticator）页 —— 独立的扫码验证码，不再依赖保险库条目。
 *
 * 页面本身不碰相机、存储和加密：扫码由外部（pages/Index）用 ScanKit 完成，
 * 账号列表由 TotpStore（Index 注入）提供，这里只负责展示与交互。
 */
import { Theme } from '../common/Theme';
import { scanSupported } from '../common/ScanSupport';
import { confirmDanger } from '../common/Dialog';
import { Icons } from '../common/Icons';
import { TotpAccount } from '../common/TotpStore';
import { generateTotpSync, secondsRemaining } from '../common/Totp';
import { CopyButton } from './CopyButton';
import { BrandAvatar } from './LogoBits';

/** 123456 -> 123 456 */
function spaced(code: string, digits: number): string {
  if (digits === 6) {
    return `${code.substring(0, 3)} ${code.substring(3)}`;
  }
  if (digits === 8) {
    return `${code.substring(0, 4)} ${code.substring(4)}`;
  }
  return code;
}

/** 单条验证器卡片：@Component + @Prop，保证每秒 tick 变化时能重新渲染 */
@Component
struct TotpRow {
  @Prop acc: TotpAccount = {
    id: '', issuer: '', account: '', secret: '', digits: 6, period: 30
  };
  @Prop tick: number = 0;
  onCopyTap: (label: string, value: string) => void = () => {
  };
  onDeleteTap: (acc: TotpAccount) => void = () => {
  };

  private title(): string {
    if (this.acc.issuer.length > 0) {
      return this.acc.issuer;
    }
    return this.acc.account.length > 0 ? this.acc.account : '未命名';
  }

  private code(): string {
    if (this.tick < 0) {
      return '';
    }
    try {
      return generateTotpSync(this.acc.secret, this.acc.digits, this.acc.period);
    } catch (e) {
      return '';
    }
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        BrandAvatar({ name: this.title(), diameter: 36 })

        Column({ space: 2 }) {
          Text(this.title())
            .fontSize(Theme.FONT_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.acc.account.length > 0) {
            Text(this.acc.account)
              .fontSize(Theme.FONT_CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_HINT)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(`${secondsRemaining(this.acc.period)}s`)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_HINT)
      }
      .width('100%')


      Row() {
        Text(this.code().length > 0 ? spaced(this.code(), this.acc.digits) : '密钥无效')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.code().length > 0 ? Theme.TEXT_PRIMARY : Theme.DANGER)
          .letterSpacing(1)
          .layoutWeight(1)
        CopyButton({
          iconSize: 17,
          onTap: () => {
            if (this.code().length > 0) {
              this.onCopyTap(`${this.title()} 动态码`, this.code());
            }
          }
        })
      }
      .width('100%')

      Row() {
        Row()
          .width(`${Math.round(secondsRemaining(this.acc.period) / this.acc.period * 100)}%`)
          .height(4)
          .borderRadius(2)
          .backgroundColor(secondsRemaining(this.acc.period) <= 5 ? Theme.DANGER : Theme.PRIMARY)
      }
      .width('100%')
      .height(4)
      .borderRadius(2)
      .backgroundColor(Theme.BACKGROUND)
    }
    .width('100%')
    .padding(14)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.CARD)
    .gesture(LongPressGesture({ repeat: false, duration: 500 })
      .onAction(() => this.onDeleteTap(this.acc)))
  }
}
@Component
export struct TotpView {
  @Prop accounts: TotpAccount[] = [];
  /** 扫码添加 */
  onScan: () => void = () => {
  };
  /** 手动添加（发行方, 账号, 密钥） */
  onAddManual: (issuer: string, account: string, secret: string) => void = () => {
  };
  onDelete: (id: string) => void = () => {
  };
  onCopy: (label: string, value: string) => void = () => {
  };

  @State tick: number = 0;
  @State showManual: boolean = false;
  @State issuer: string = '';
  @State accountName: string = '';
  @State secret: string = '';
  private timer: number = -1;

  aboutToAppear(): void {
    this.timer = setInterval(() => {
      this.tick = this.tick + 1;
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private titleOf(acc: TotpAccount): string {
    if (acc.issuer.length > 0) {
      return acc.issuer;
    }
    return acc.account.length > 0 ? acc.account : '未命名';
  }

  private confirmDelete(acc: TotpAccount): void {
    confirmDanger('删除验证器', `删除「${this.titleOf(acc)}」后，这个动态码将不再生成。`, '删除', () => this.onDelete(acc.id));
  }

  @Builder
  emptyState() {
    Column({ space: 12 }) {
      SymbolGlyph(Icons.shield)
        .fontSize(42)
        .fontColor([Theme.TEXT_HINT])
      Text('还没有验证器账号')
        .fontSize(Theme.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_PRIMARY)
      Text(scanSupported() ?
              '扫描网站给出的 otpauth 二维码即可添加，验证码每 30 秒刷新一次，密钥加密后只存在本机。' :
              '点右上角 + 手动输入 otpauth 密钥即可添加，验证码每 30 秒刷新一次，密钥加密后只存在本机。')
        .fontSize(Theme.FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_HINT)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 48, left: 20, right: 20 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  manualSheet() {
    Column({ space: 10 }) {
      Text('手动添加验证器')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT_PRIMARY)
        .width('100%')
      TextInput({ text: this.issuer, placeholder: '发行方，如 GitHub' })
        .fontColor(Theme.TEXT_PRIMARY)
        .placeholderColor(Theme.TEXT_HINT)
        .height(42)
        .borderRadius(Theme.RADIUS_SMALL)
        .backgroundColor(Theme.BACKGROUND)
        .fontSize(14)
        .onChange((v: string) => {
          this.issuer = v;
        })
      TextInput({ text: this.accountName, placeholder: '账号，如 me@example.com' })
        .fontColor(Theme.TEXT_PRIMARY)
        .placeholderColor(Theme.TEXT_HINT)
        .height(42)
        .borderRadius(Theme.RADIUS_SMALL)
        .backgroundColor(Theme.BACKGROUND)
        .fontSize(14)
        .onChange((v: string) => {
          this.accountName = v;
        })
      TextInput({ text: this.secret, placeholder: '密钥（Base32，或 otpauth:// 链接）' })
        .fontColor(Theme.TEXT_PRIMARY)
        .placeholderColor(Theme.TEXT_HINT)
        .height(42)
        .borderRadius(Theme.RADIUS_SMALL)
        .backgroundColor(Theme.BACKGROUND)
        .fontSize(14)
        .onChange((v: string) => {
          this.secret = v;
        })
      Row({ space: 8 }) {
        Text('取消')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_SECONDARY)
          .backgroundColor(Theme.BACKGROUND)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(16)
          .onClick(() => {
            this.showManual = false;
            this.issuer = '';
            this.accountName = '';
            this.secret = '';
          })
        Blank()
        Text('添加')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(Theme.PRIMARY)
          .padding({ left: 18, right: 18, top: 8, bottom: 8 })
          .borderRadius(16)
          .onClick(() => {
            if (this.secret.trim().length === 0) {
              return;
            }
            this.onAddManual(this.issuer, this.accountName, this.secret);
            this.showManual = false;
            this.issuer = '';
            this.accountName = '';
            this.secret = '';
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.CARD)
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Column({ space: 4 }) {
          Text('验证器')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY)
          Text(this.accounts.length > 0 ?
            `${this.accounts.length} 个验证器账号` : '两步验证动态码')
            .fontSize(12)
            .fontColor(Theme.TEXT_HINT)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 扫码：与加号一致的浅底圆 + 主色图标（所有设备都显示；不支持时由 Index 提示）
        Row() {
          SymbolGlyph(Icons.scan)
            .fontSize(30)
            .fontColor([Theme.PRIMARY])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.TINT)
        .onClick(() => this.onScan())

        // 手动输入：同样浅底圆
        Row() {
          SymbolGlyph(Icons.add)
            .fontSize(30)
            .fontColor([Theme.PRIMARY])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.TINT)
        .margin({ left: 10 })
        .onClick(() => {
          this.showManual = !this.showManual;
        })
      }
      .width('100%')
      .padding({ top: 8, bottom: 12 })

      if (this.showManual) {
        this.manualSheet()
        Blank().height(10)
      }

      if (this.accounts.length === 0) {
        this.emptyState()
      } else {
        List({ space: 10 }) {
          ForEach(this.accounts, (acc: TotpAccount) => {
            ListItem() {
              TotpRow({
                acc: acc,
                tick: this.tick,
                onCopyTap: (label: string, value: string) => this.onCopy(label, value),
                onDeleteTap: (target: TotpAccount) => this.confirmDelete(target)
              })
            }
          }, (acc: TotpAccount) => `${acc.id}`)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 64 })
    .backgroundColor(Theme.BACKGROUND)
  }
}
