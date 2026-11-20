/**
 * 本机使用（不连接服务器）的初始化页。
 *
 * 数据只用本机的主密码加密后存在设备里，不上传、不同步：
 *  - 换设备 / 卸载 / 忘记主密码都会导致数据无法恢复，页面上明确告知
 *  - 加密方式与服务器模式一致（PBKDF2 + AES-256-CBC + HMAC），
 *    因此条目、文件夹、回收站、生成器、验证器等功能表现完全一致
 */
import { Theme } from '../common/Theme';
import { Icons } from '../common/Icons';
import { VaultStore } from '../common/VaultStore';

@Component
export struct LocalSetupView {
  onCreated: () => void = () => {
  };
  onCancel: () => void = () => {
  };

  @State password: string = '';
  @State confirm: string = '';
  @State showPassword: boolean = false;
  @State busy: boolean = false;
  @State error: string = '';

  /** 提示项：圆点固定宽度，正文换行后与首行文字对齐（悬挂缩进） */
  @Builder
  hint(text: string) {
    Row({ space: 8 }) {
      // 小圆点做项目符号：与正文首行中线对齐
      Circle({ width: 5, height: 5 })
        .fill(Theme.PRIMARY)
        .margin({ top: 8 })
      Text(text)
        .fontSize(13)
        .fontColor(Theme.TEXT_SECONDARY)
        .lineHeight(20)
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  private async submit(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.error = '';
    if (this.password.length < 8) {
      this.error = '主密码至少 8 位';
      return;
    }
    if (this.password !== this.confirm) {
      this.error = '两次输入的主密码不一致';
      return;
    }
    this.busy = true;
    try {
      await VaultStore.createLocalVault(this.password);
      this.getUIContext().getPromptAction().showToast({ message: '已创建本机保险库', duration: 2000 });
      this.onCreated();
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column() {
      Row() {
        Text('取消')
          .fontSize(Theme.FONT_BODY)
          .fontColor(Theme.TEXT_SECONDARY)
          .onClick(() => this.onCancel())
      }
      .width('100%')
      .height(44)

      Column() {
        SymbolGlyph(Icons.lock)
          .fontSize(46)
          .fontColor([Theme.PRIMARY])
          .margin({ bottom: 12 })
        Text('本机使用')
          .fontSize(Theme.FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
        Text('不连接服务器，数据只加密保存在这台设备')
          .fontSize(Theme.FONT_CAPTION)
          .fontColor(Theme.TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
          .margin({ top: 6 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 24, bottom: 24 })

      Column({ space: 8 }) {
        Row() {
          Text('设置主密码')
            .fontSize(Theme.FONT_CAPTION)
            .fontColor(Theme.TEXT_SECONDARY)
            .layoutWeight(1)
          Text(this.showPassword ? '隐藏' : '显示')
            .fontSize(Theme.FONT_CAPTION)
            .fontColor(Theme.PRIMARY)
            .onClick(() => {
              this.showPassword = !this.showPassword;
            })
        }
        .width('100%')
        TextInput({ text: this.password, placeholder: '至少 8 位' })
          .type(this.showPassword ? InputType.Normal : InputType.Password)
          .fontColor(Theme.TEXT_PRIMARY)
          .placeholderColor(Theme.TEXT_HINT)
          .height(48)
          .borderRadius(Theme.RADIUS_SMALL)
          .backgroundColor(Theme.CARD)
          .fontSize(Theme.FONT_BODY)
          .onChange((value: string) => {
            this.password = value;
          })
      }
      .width('100%')
      .margin({ bottom: 16 })

      Column({ space: 8 }) {
        Text('确认主密码')
          .fontSize(Theme.FONT_CAPTION)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
        TextInput({ text: this.confirm, placeholder: '再输入一次' })
          .type(this.showPassword ? InputType.Normal : InputType.Password)
          .fontColor(Theme.TEXT_PRIMARY)
          .placeholderColor(Theme.TEXT_HINT)
          .height(48)
          .borderRadius(Theme.RADIUS_SMALL)
          .backgroundColor(Theme.CARD)
          .fontSize(Theme.FONT_BODY)
          .onChange((value: string) => {
            this.confirm = value;
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

      Button(this.busy ? '创建中…' : '创建本机保险库')
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

      Column({ space: 10 }) {
        this.hint('数据只加密保存在本机，不会上传到任何服务器')
        this.hint('忘记主密码无法找回；卸载应用或更换设备会丢数据')
        this.hint('建议创建后到「设置 → 安全」开启指纹解锁')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 14, bottom: 14, left: 14, right: 14 })
      .borderRadius(Theme.RADIUS_SMALL)
      .backgroundColor(Theme.CARD)
      .margin({ top: 24, bottom: 16 })

      Blank()

      Text('服务器模式与本机模式的功能完全一致（文件夹、回收站、生成器、验证器）')
        .fontSize(12)
        .fontColor(Theme.TEXT_HINT)
        .lineHeight(18)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: Theme.PAGE_PADDING, right: Theme.PAGE_PADDING })
    .backgroundColor(Theme.BACKGROUND)
  }
}
