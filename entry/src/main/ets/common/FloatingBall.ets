/**
 * 闪控球（FloatingBall）封装 —— 需要 ACL 权限 ohos.permission.USE_FLOAT_BALL。
 *
 * 用途：复制用户名后，在屏幕边缘悬浮一个小球，点一下复制该账号密码；
 * 若条目带验证器，则接着在黑球上显示动态码，点一下复制验证码并关闭。
 *
 * 系统限制：
 *  - 仅应用在前台时可启动；一个应用同时只能有一个球
 *  - 只提供系统模板（图标 + 文本），不能自绘 UI；只开放单击事件
 */
import { floatingBall } from '@kit.ArkUI';
import { common, abilityAccessCtrl, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'LockWarden';
const PERMISSION: Permissions = 'ohos.permission.USE_FLOAT_BALL';

class FloatingBallImpl {
  private controller: floatingBall.FloatingBallController | null = null;
  private started: boolean = false;
  private updating: boolean = false;
  private denied: boolean = false;
  private clickHandler: (() => void) | null = null;

  isStarted(): boolean {
    return this.started;
  }

  supported(): boolean {
    try {
      return floatingBall.isFloatingBallEnabled();
    } catch (e) {
      return false;
    }
  }

  setOnClick(handler: () => void): void {
    this.clickHandler = handler;
  }

  async ensurePermission(context: common.UIAbilityContext): Promise<boolean> {
    if (this.denied) {
      return false;
    }
    try {
      const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult =
        await manager.requestPermissionsFromUser(context, [PERMISSION]);
      const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
      if (!granted) {
        this.denied = true;
      }
      return granted;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'float ball permission failed: %{public}s', (e as Error).message);
      return false;
    }
  }

  async start(context: common.UIAbilityContext, title: string, content: string,
    background: string = '', titleColor: string = ''): Promise<boolean> {
    if (!this.supported()) {
      return false;
    }
    try {
      if (this.controller === null) {
        this.controller = await floatingBall.create({ context: context });
        this.controller.on('click', () => {
          const handler: (() => void) | null = this.clickHandler;
          if (handler !== null) {
            handler();
          }
        });
      }
      if (this.started) {
        await this.controller.updateFloatingBall(this.params(title, content, background, titleColor));
      } else {
        await this.controller.startFloatingBall(this.params(title, content, background, titleColor));
        this.started = true;
      }
      return true;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'float ball start failed: %{public}s', (e as Error).message);
      return false;
    }
  }

  async update(title: string, content: string, background: string = '', titleColor: string = ''): Promise<void> {
    if (this.controller === null || !this.started || this.updating) {
      return;
    }
    this.updating = true;
    try {
      await this.controller.updateFloatingBall(this.params(title, content, background, titleColor));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'float ball update failed: %{public}s', (e as Error).message);
    } finally {
      this.updating = false;
    }
  }

  async stop(): Promise<void> {
    if (this.controller === null || !this.started) {
      this.started = false;
      return;
    }
    try {
      await this.controller.stopFloatingBall();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'float ball stop failed: %{public}s', (e as Error).message);
    }
    this.started = false;
  }

  /**
   * 用 NORMAL 模板：标题 + 副标题，无图标占位。
   * 标题放操作提示，副标题放条目名称。
   */
  private params(title: string, content: string, background: string,
    titleColor: string): floatingBall.FloatingBallParams {
    const params: floatingBall.FloatingBallParams = {
      template: floatingBall.FloatingBallTemplate.NORMAL,
      title: title,
      content: content
    };
    if (background.length > 0) {
      params.backgroundColor = background;
    }
    if (titleColor.length > 0) {
      params.titleColor = titleColor;
      params.contentColor = titleColor;
    }
    return params;
  }
}

export const FloatingBall: FloatingBallImpl = new FloatingBallImpl();
