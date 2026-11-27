/**
 * 返回事件分发。
 *
 * 鸿蒙的侧滑/返回键最终会走 @Entry 组件的 onBackPress()。
 * 本应用是单页多态结构（详情、编辑器、回收站都是覆盖层），
 * 这些覆盖层在 MainShell 内部，而 onBackPress 只能写在 @Entry（pages/Index）里，
 * 因此用一个极简的总线把"谁来消费这次返回"接到 MainShell。
 *
 * 约定：处理函数返回 true 表示已消费（不再交给系统），false 表示继续上抛。
 */
export type BackHandler = () => boolean;

class BackBusImpl {
  private handler: BackHandler | null = null;

  register(handler: BackHandler): void {
    this.handler = handler;
  }

  unregister(): void {
    this.handler = null;
  }

  /** 返回 true 表示有覆盖层被关掉 */
  dispatch(): boolean {
    if (this.handler === null) {
      return false;
    }
    return this.handler();
  }
}

export const BackBus: BackBusImpl = new BackBusImpl();
