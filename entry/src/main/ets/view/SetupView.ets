/**
 * 服务器配置页：填写 Vaultwarden 地址与账号邮箱。
 * 点「连接」会真实请求 /api/config 与 /identity/accounts/prelogin，
 * 因此地址写错会立刻暴露，而不是等到登录时才报错。
 */
import { Theme } from '../common/Theme';
import { Icons } from '../common/Icons';
import { VaultStore } from '../common/VaultStore';

@Component
export struct SetupView {
  @Prop initialServer: string = '';
  @Prop initialEmail: string = '';
  onReady: (server: string, email: string) => void = () => {
  };
  onCancel: () => void = () => {
  };
  onDemo: () => void = () => {
  };
  /** 没有服务器，改在本机使用 */
  onLocal: () => void = () => {
  };
  @Prop allowCancel: boolean = false;

  @State server: string = '';
  @State email: string = '';
  @State busy: boolean = false;
  @State error: string = '';

  aboutToAppear(): void {
    this.server = this.initialServer.length > 0 ? this.initialServer : 'https://';
    this.email = this.initialEmail;
  }

  /** 统一成 https:// 开头的地址：没写协议自动补 https，末尾斜杠去掉 */
  private normalizedServer(): string {
    let text: string = this.server.trim();
    if (text.length === 0) {
      throw new Error('请填写服务器地址');
    }
    if (!/^https?:\/\//i.test(text)) {
      text = `https://${text}`;
    }
    // 只有协议没有主机：先在去掉斜杠前判断，否则 https:// 会被裁成 https:
    if (/^https?:\/\/\s*$/i.test(text)) {
      throw new Error('请补全服务器地址，例如 https://vault.example.com');
    }
    text = text.replace(/\/+$/, '');
    if (text.indexOf('://') <= 0 || text.length <= text.indexOf('://') + 3) {
      throw new Error('请补全服务器地址，例如 https://vault.example.com');
    }
    return text;
  }

  private async submit(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const server: string = this.normalizedServer();
      this.server = server;
      await VaultStore.configure(server, this.email);
      this.getUIContext().getPromptAction().showToast({
        message: '已连接',
        duration: 2000
      });
      this.onReady(server, this.email);
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column() {
      Row() {
        if (this.allowCancel) {
          Text('取消')
            .fontSize(Theme.FONT_BODY)
            .fontColor(Theme.TEXT_SECONDARY)
            .onClick(() => this.onCancel())
        }
      }
      .width('100%')
      .height(44)

      Column() {
        SymbolGlyph(Icons.lock)
          .fontSize(46)
          .fontColor([Theme.PRIMARY])
          .margin({ bottom: 12 })
        Text('连接服务器')
          .fontSize(Theme.FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
        Text('这是一台你自己部署的密码服务器')
          .fontSize(Theme.FONT_CAPTION)
          .fontColor(Theme.TEXT_SECONDARY)
          .margin({ top: 6 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 32, bottom: 28 })

      Column({ space: 8 }) {
        Text('服务器地址')
          .fontSize(Theme.FONT_CAPTION)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
        TextInput({ text: this.server, placeholder: 'https://vault.example.com' })
          .fontColor(Theme.TEXT_PRIMARY)
          .placeholderColor(Theme.TEXT_HINT)
          .type(InputType.URL)
          .height(48)
          .borderRadius(Theme.RADIUS_SMALL)
          .backgroundColor(Theme.CARD)
          .fontSize(Theme.FONT_BODY)
          .onChange((value: string) => {
            this.server = value;
          })
        Text('默认以 https:// 开头；不写协议会自动补全，局域网可用 http://192.168.1.100:8222')
          .fontSize(12)
          .fontColor(Theme.TEXT_HINT)
          .width('100%')
      }
      .width('100%')
      .margin({ bottom: 16 })

      Column({ space: 8 }) {
        Text('账号邮箱')
          .fontSize(Theme.FONT_CAPTION)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
        TextInput({ text: this.email, placeholder: 'you@example.com' })
          .fontColor(Theme.TEXT_PRIMARY)
          .placeholderColor(Theme.TEXT_HINT)
          .type(InputType.Email)
          .height(48)
          .borderRadius(Theme.RADIUS_SMALL)
          .backgroundColor(Theme.CARD)
          .fontSize(Theme.FONT_BODY)
          .onChange((value: string) => {
            this.email = value;
          })
      }
      .width('100%')
      .margin({ bottom: 8 })

      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(Theme.FONT_CAPTION)
          .fontColor(Theme.DANGER)
          .width('100%')
          .margin({ top: 8 })
      }

      Button(this.busy ? '连接中…' : '连接并继续')
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor(this.busy ? '#8FB4FB' : Theme.PRIMARY)
        .fontColor(Color.White)
        .fontSize(Theme.FONT_BODY)
        .enabled(!this.busy)
        .margin({ top: 24 })
        .onClick(() => {
          this.submit();
        })

      // 次要按钮：与「连接并继续」同尺寸同圆角，用浅色底区分主次
      Button('没有服务器？在本机使用', { type: ButtonType.Capsule })
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor(Theme.TINT)
        .fontColor(Theme.PRIMARY)
        .fontSize(Theme.FONT_BODY)
        .margin({ top: 12 })
        .onClick(() => this.onLocal())

      Blank()

      Text('先看看演示界面（不连接服务器）')
        .fontSize(Theme.FONT_CAPTION)
        .fontColor(Theme.TEXT_SECONDARY)
        .margin({ bottom: 12 })
        .onClick(() => this.onDemo())

      Text('客户端只与你的服务器通信，主密码不会离开本机')
        .fontSize(12)
        .fontColor(Theme.TEXT_HINT)
        .textAlign(TextAlign.Center)
        .margin({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: Theme.PAGE_PADDING, right: Theme.PAGE_PADDING })
    .backgroundColor(Theme.BACKGROUND)
  }
}
