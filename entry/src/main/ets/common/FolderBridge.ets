/**
 * 文件夹页的返回分级。
 *
 * 文件夹页是覆盖层，内部还有两级：文件夹内的条目详情 → 文件夹里的条目列表 → 文件夹列表。
 * 系统返回键先到 MainShell.handleBack()，它只知道"覆盖层开着"，不知道里面走到第几层，
 * 于是通过这个总线问一下文件夹页：能不能先在内部退一层？
 *
 * 约定：返回 true 表示已消费（内部退了一层），false 表示已经到最外层。
 */
export type FolderBackHandler = () => boolean;

class FolderBridgeImpl {
  private handler: FolderBackHandler | null = null;

  register(handler: FolderBackHandler): void {
    this.handler = handler;
  }

  unregister(): void {
    this.handler = null;
  }

  /** 返回 true 表示文件夹页在内部消费了这次返回 */
  close(): boolean {
    if (this.handler === null) {
      return false;
    }
    return this.handler();
  }
}

export const FolderBridge: FolderBridgeImpl = new FolderBridgeImpl();
