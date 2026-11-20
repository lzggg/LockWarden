/**
 * 剪贴板封装。
 *
 * 单独成一模块，只让「真正需要剪贴板的页面」导入：
 * DevEco 预览器没有 pasteboard 原生模块，视图组件若静态导入它就无法预览。
 */
import { pasteboard } from '@kit.BasicServicesKit';

/** 写入系统剪贴板 */
export async function copyText(text: string): Promise<void> {
  if (text.length === 0) {
    return;
  }
  const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
  await pasteboard.getSystemPasteboard().setData(data);
}
