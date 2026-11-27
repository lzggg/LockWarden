/**
 * 编辑器与外壳之间的"请求关闭"通道。
 *
 * 编辑器是子组件，外壳（MainShell）无法直接调用它的方法；
 * 而"是否有关未保存改动、要不要弹确认框"只有编辑器自己知道。
 * 因此编辑器打开时把自己的关闭入口挂到这里，外壳在收到返回事件时调用它。
 */
class EditorBridgeImpl {
  /** 编辑器注册的关闭入口；打开时为非空，关闭后置空 */
  requestClose: (() => void) | null = null;

  /** 有编辑器在开着时返回 true */
  get active(): boolean {
    return this.requestClose !== null;
  }

  /** 请求关闭当前编辑器（由编辑器决定直接关还是先弹确认） */
  close(): void {
    const handler: (() => void) | null = this.requestClose;
    if (handler !== null) {
      handler();
    }
  }
}

export const EditorBridge: EditorBridgeImpl = new EditorBridgeImpl();
