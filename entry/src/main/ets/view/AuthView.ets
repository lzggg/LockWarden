/**
 * 认证页，两种模式共用：
 *  - login ：首次登录，需要联服务器换取 token 与账号密钥
 *  - unlock：本地离线解锁，只用主密码解密本地保存的账号密钥
 */
import { Theme } from '../common/Theme';
import { Icons } from '../common/Icons';
import { VaultStore } from '../common/VaultStore';
import { EyeToggle } from './EyeToggle';
import { errorMessage } from '../common/Api';

@Component
export struct AuthView {
  @Prop mode: string = 'login';
  @Prop email: string = '';
  @Prop server: string = '';
  @Prop bioFingerprint: boolean = false;
  @Prop bioFace: boolean = false;
  onSuccess: () => void = () => {
  };
  onSwitchAccount: () => void = () => {
  };
  /** 左上角返回 / 侧滑返回：回到「连接服务器」页 */
  onBack: () => void = () => {
  };
  @Prop canGoBack: boolean = true;

  @State password: string = '';
  @State busy: boolean = false;
  @State error: string = '';
  @State showPassword: boolean = false;
  /** 正在验证的生物识别类型：'' 表示空闲 */
  @State bioKind: string = '';

  aboutToAppear(): void {
    if (this.mode !== 'unlock') {
      return;
    }
    // 只开了一种就直接用它；两种都开则让用户自己选，不默认指纹。
    // 延时一是错开启动瞬间窗口未拿到焦点的竞态，二是确保此时 @Prop 已全部就绪
    // （在回调里读 this.*，不要用 aboutToAppear 时捕获的常量）。
    setTimeout(() => {
      const fingerprintOn: boolean = this.bioFingerprint;
      const faceOn: boolean = this.bioFace;
      if (fingerprintOn && !faceOn) {
        this.biometricUnlock('fingerprint');
      } else if (faceOn && !fingerprintOn) {
        this.biometricUnlock('face');
      }
    }, 500);
  }

  /** 生物识别解锁：kind = 'fingerprint' | 'face' */
  private async biometricUnlock(kind: string): Promise<void> {
    if (this.bioKind.length > 0 || this.busy) {
      return;
    }
    this.bioKind = kind;
    this.error = '';
    try {
      await VaultStore.unlockWithBiometric(kind);
      this.getUIContext().getPromptAction().showToast({ message: '已解锁', duration: 1500 });
      this.onSuccess();
    } catch (e) {
      const message: string = (e as Error).message;
      // 用户主动取消不算错误，不弹红字
      if (message.indexOf('取消') < 0) {
        this.error = message;
      }
    } finally {
      this.bioKind = '';
    }
  }

  private async submit(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.password.length === 0) {
      this.error = '请输入主密码';
      return;
    }
    this.busy = true;
    this.error = '';
    // 600000 次 PBKDF2 在主线程上要跑几秒，先让界面把「处理中…」画出来
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), 60);
    });
    this.getUIContext().getPromptAction().showToast({
      message: '正在校验主密码，请稍候…',
      duration: 2000
    });
    try {
      if (this.mode === 'login') {
        await VaultStore.login(this.password);
      } else {
        await VaultStore.unlock(this.password);
      }
      this.password = '';
      this.getUIContext().getPromptAction().showToast({
        message: this.mode === 'login' ? '登录成功' : '已解锁',
        duration: 1500
      });
      this.onSuccess();
    } catch (e) {
      // 兜底：某些错误对象 message 为空，用 JSON 露出真实内容便于排查
      const message: string = errorMessage(e);
      this.error = message;
      // 页内红字 + 弹窗双重提示：主密码错误这类问题必须让用户明确看到
      AlertDialog.show({
        title: this.mode === 'login' ? '无法登录' : '无法解锁',
        message: message,
        autoCancel: true,
        confirm: {
          value: '知道了',
          action: () => {
          }
        }
      });
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column() {
      // 顶部返回：回到服务器 / 邮箱设置页
      Row({ space: 4 }) {
        if (this.canGoBack) {
          SymbolGlyph(Icons.chevron)
            .fontSize(16)
            .fontColor([Theme.PRIMARY])
            .rotate({ angle: 180 })
          Text('连接服务器')
            .fontSize(Theme.FONT_BODY)
            .fontColor(Theme.PRIMARY)
        }
      }
      .width('100%')
      .height(48)
      .justifyContent(FlexAlign.Start)
      .onClick(() => {
        if (this.canGoBack) {
          this.onBack();
        }
      })

      SymbolGlyph(this.mode === 'login' ? Icons.lockOpen : Icons.lock)
        .fontSize(46)
        .fontColor([Theme.PRIMARY])
      Text(this.mode === 'login' ? '登录到你的保险库' : '解锁保险库')
        .fontSize(Theme.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT_PRIMARY)
        .margin({ top: 12 })

      Text(this.email)
        .fontSize(Theme.FONT_CAPTION)
        .fontColor(Theme.TEXT_SECONDARY)
        .margin({ top: 8 })
      Text(this.server)
        .fontSize(12)
        .fontColor(Theme.TEXT_HINT)
        .margin({ top: 2 })

      Column({ space: 8 }) {
        Row() {
          TextInput({ text: this.password, placeholder: '主密码' })
            .fontColor(Theme.TEXT_PRIMARY)
            .placeholderColor(Theme.TEXT_HINT)
            .type(this.showPassword ? InputType.Normal : InputType.Password)
            .showPasswordIcon(false)
            .height(48)
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .fontSize(Theme.FONT_BODY)
            .onChange((value: string) => {
              this.password = value;
            })
            .onSubmit(() => {
              this.submit();
            })
          EyeToggle({
            revealed: this.showPassword,
            onToggle: () => {
              this.showPassword = !this.showPassword;
            }
          })
        }
        .width('100%')
        .height(48)
        .borderRadius(Theme.RADIUS_SMALL)
        .backgroundColor(Theme.CARD)
      }
      .width('100%')
      .margin({ top: 28 })

      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(Theme.FONT_CAPTION)
          .fontColor(Theme.DANGER)
          .width('100%')
          .margin({ top: 10 })
      }

      Button(this.busy ? '处理中…' : (this.mode === 'login' ? '登录' : '解锁'))
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

      if (this.mode === 'unlock' && this.bioFingerprint && this.bioFace) {
        Text('两种方式都已开启，请选择验证方式')
          .fontSize(Theme.FONT_CAPTION)
          .fontColor(Theme.TEXT_HINT)
          .margin({ top: 14 })
      }

      if (this.mode === 'unlock' && this.bioFingerprint) {
        Row({ space: 8 }) {
          SymbolGlyph(Icons.touchId)
            .fontSize(20)
            .fontColor([Theme.PRIMARY])
          Text(this.bioKind === 'fingerprint' ? '验证中…' : '用指纹解锁')
            .fontSize(Theme.FONT_BODY)
            .fontColor(Theme.PRIMARY)
        }
        .width('100%')
        .height(46)
        .borderRadius(23)
        .justifyContent(FlexAlign.Center)
        .borderWidth(1.5)
        .borderColor(Theme.PRIMARY)
        .margin({ top: 12 })
        .onClick(() => {
          this.biometricUnlock('fingerprint');
        })
      }

      if (this.mode === 'unlock' && this.bioFace) {
        Row({ space: 8 }) {
          SymbolGlyph(Icons.faceId)
            .fontSize(20)
            .fontColor([Theme.PRIMARY])
          Text(this.bioKind === 'face' ? '验证中…' : '用面容解锁')
            .fontSize(Theme.FONT_BODY)
            .fontColor(Theme.PRIMARY)
        }
        .width('100%')
        .height(46)
        .borderRadius(23)
        .justifyContent(FlexAlign.Center)
        .borderWidth(1.5)
        .borderColor(Theme.PRIMARY)
        .margin({ top: 12 })
        .onClick(() => {
          this.biometricUnlock('face');
        })
      }

      if (this.mode === 'unlock') {
        Text('使用其他账号')
          .fontSize(Theme.FONT_CAPTION)
          .fontColor(Theme.PRIMARY)
          .margin({ top: 18 })
          .onClick(() => this.onSwitchAccount())
      }

      Blank()

      Text('主密码仅在本机参与密钥派生，不会上传')
        .fontSize(12)
        .fontColor(Theme.TEXT_HINT)
        .margin({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: Theme.PAGE_PADDING, right: Theme.PAGE_PADDING })
    .backgroundColor(Theme.BACKGROUND)
    // 左缘向右滑同样返回服务器设置页
    .parallelGesture(
      PanGesture({ direction: PanDirection.Right, distance: 30 })
        .onActionEnd((event: GestureEvent) => {
          if (this.canGoBack && event.offsetX > 120) {
            this.onBack();
          }
        })
    )
  }
}
