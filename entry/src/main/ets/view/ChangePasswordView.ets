/**
 * 修改主密码。
 *
 * 两种模式行为不同：
 *  - 本机模式：验证当前主密码 → 换新盐重新派生密钥 → 用新密钥重新包裹账号密钥（条目不重新加密）
 *  - 服务器模式：主密码由服务端统一校验与保存，客户端无法安全地改，
 *    这里只提示去网页端修改，并给出当前服务器地址
 */
import { Theme } from '../common/Theme';
import { Icons } from '../common/Icons';
import { VaultStore } from '../common/VaultStore';

@Component
export struct ChangePasswordView {
  onBack: () => void = () => {
  };

  @State localMode: boolean = VaultStore.localMode;
  @State server: string = VaultStore.server;
  @State oldPassword: string = '';
  @State newPassword: string = '';
  @State confirm: string = '';
  @State showPassword: boolean = false;
  @State busy: boolean = false;
  @State error: string = '';

  private async submit(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.error = '';
    if (this.oldPassword.length === 0) {
      this.error = '请输入当前主密码';
      return;
    }
    if (this.newPassword.length < 8) {
      this.error = '新主密码至少 8 位';
      return;
    }
    if (this.newPassword !== this.confirm) {
      this.error = '两次输入的新主密码不一致';
      return;
    }
    this.busy = true;
    try {
      await VaultStore.changeLocalPassword(this.oldPassword, this.newPassword);
      this.getUIContext().getPromptAction().showToast({ message: '主密码已修改', duration: 2000 });
      this.onBack();
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.busy = false;
    }
  }

  @Builder
  passwordField(label: string, placeholder: string, value: string,
    onChange: (text: string) => void) {
    Column({ space: 8 }) {
      Text(label)
        .fontSize(Theme.FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_SECONDARY)
        .width('100%')
      TextInput({ text: value, placeholder: placeholder })
        .type(this.showPassword ? InputType.Normal : InputType.Password)
        .fontColor(Theme.TEXT_PRIMARY)
        .placeholderColor(Theme.TEXT_HINT)
        .height(48)
        .borderRadius(Theme.RADIUS_SMALL)
        .backgroundColor(Theme.CARD)
        .fontSize(Theme.FONT_BODY)
        .onChange((text: string) => onChange(text))
    }
    .width('100%')
    .margin({ bottom: 16 })
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        SymbolGlyph(Icons.chevron)
          .fontSize(16)
          .fontColor([Theme.PRIMARY])
          .rotate({ angle: 180 })
        Text('安全')
          .fontSize(Theme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.PRIMARY)
      }
      .width('100%')
      .height(48)
      .onClick(() => this.onBack())

      Text('修改主密码')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT_PRIMARY)
        .width('100%')
      Text(this.localMode ? '本机保险库的主密码只保存在这台设备' : '服务器模式的主密码由服务器统一管理')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
        .margin({ top: 4, bottom: 20 })

      if (this.localMode) {
        Row() {
          Text('当前主密码 / 新主密码')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_HINT)
            .layoutWeight(1)
          Text(this.showPassword ? '隐藏' : '显示')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.PRIMARY)
            .onClick(() => {
              this.showPassword = !this.showPassword;
            })
        }
        .width('100%')
        .margin({ bottom: 12 })

        this.passwordField('当前主密码', '输入现在使用的主密码', this.oldPassword, (text: string) => {
          this.oldPassword = text;
        })
        this.passwordField('新主密码', '至少 8 位', this.newPassword, (text: string) => {
          this.newPassword = text;
        })
        this.passwordField('确认新主密码', '再输入一次新主密码', this.confirm, (text: string) => {
          this.confirm = text;
        })

        if (this.error.length > 0) {
          Text(this.error)
            .fontSize(Theme.FONT_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.DANGER)
            .width('100%')
            .margin({ bottom: 8 })
        }

        Button(this.busy ? '修改中…' : '保存新主密码')
          .width('100%')
          .height(48)
          .borderRadius(24)
          .backgroundColor(this.busy ? '#8FB4FB' : Theme.PRIMARY)
          .fontColor(Color.White)
          .fontSize(Theme.FONT_BODY)
          .enabled(!this.busy)
          .margin({ top: 8 })
          .onClick(() => {
            this.submit();
          })

        Text('修改后请立即用新主密码解锁一次确认；旧主密码会立刻失效。')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_HINT)
          .width('100%')
          .lineHeight(18)
          .margin({ top: 12 })
      } else {
        Column({ space: 12 }) {
          Row({ space: 10 }) {
            SymbolGlyph(Icons.lock)
              .fontSize(20)
              .fontColor([Theme.PRIMARY])
            Text('请到网页端修改')
              .fontSize(Theme.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
              .layoutWeight(1)
          }
          .width('100%')

          Text('服务器模式下，主密码用于在服务端校验并解密你的保险库密钥，' +
            '必须由服务器网页端统一修改，客户端无法安全代办。')
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
            .lineHeight(20)
            .width('100%')

          if (this.server.length > 0) {
            Text(this.server)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.PRIMARY)
              .lineHeight(20)
              .width('100%')
              .copyOption(CopyOptions.LocalDevice)
          }

          Text('步骤：浏览器登录网页保险库 → 右上角账号 → 账户设置 → 修改主密码；' +
            '改完后回到本应用，用新主密码解锁即可（旧密码立即失效）。')
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
            .lineHeight(20)
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .borderRadius(Theme.RADIUS)
        .backgroundColor(Theme.CARD)

        Button('知道了')
          .width('100%')
          .height(48)
          .borderRadius(24)
          .backgroundColor(Theme.TINT)
          .fontColor(Theme.PRIMARY)
          .fontSize(Theme.FONT_BODY)
          .margin({ top: 24 })
          .onClick(() => this.onBack())
      }

      Blank()
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
