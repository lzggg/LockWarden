/**
 * 多选模式的"取消选择"通道。
 *
 * 选择状态在 VaultView / TrashView 内部，外壳（MainShell）读不到；
 * 但系统返回键/侧滑是由外壳处理的。因此进入多选时把取消入口挂到这里，
 * 返回事件优先取消选择，而不是退出应用或退回主界面。
 */
class SelectionBridgeImpl {
  /** 有选择模式时非空 */
  cancel: (() => void) | null = null;

  /** 有待取消的选择时返回 true */
  get active(): boolean {
    return this.cancel !== null;
  }

  /** 取消当前选择；没有则返回 false */
  close(): boolean {
    const handler: (() => void) | null = this.cancel;
    if (handler === null) {
      return false;
    }
    handler();
    return true;
  }
}

export const SelectionBridge: SelectionBridgeImpl = new SelectionBridgeImpl();
