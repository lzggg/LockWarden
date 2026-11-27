/**
 * 「刚复制了哪个条目的哪个字段」的轻量提示。
 *
 * 详情页复制前写入，主页面复制完成后读取：
 * 这样不用给 onCopy 回调加参数（它被多个视图组件共用）。
 */
class CopyHintImpl {
  /** 最近一次从详情页复制时对应的条目 id */
  itemId: string = '';
  /** 最近一次复制的字段标签（用户名 / 密码 / 验证码 …） */
  label: string = '';

  set(itemId: string, label: string): void {
    this.itemId = itemId;
    this.label = label;
  }

  clear(): void {
    this.itemId = '';
    this.label = '';
  }
}

export const CopyHint = new CopyHintImpl();
