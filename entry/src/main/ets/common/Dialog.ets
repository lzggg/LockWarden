/**
 * 通用确认框：左边「取消」、右边危险操作（红色）。
 * 删除/彻底删除/批量删除等场景统一走这里。
 *
 * 用 UIContext.showAlertDialog 替代已废弃的 AlertDialog.show；
 * 页面启动时由 Index 调 bindDialogContext 注入 UIContext。
 */
import { UIContext } from '@kit.ArkUI';
import { Theme } from './Theme';

let dialogContext: UIContext | null = null;

/** 由根页面注入 UIContext（只需调用一次） */
export function bindDialogContext(ctx: UIContext): void {
  dialogContext = ctx;
}

export function confirmDanger(title: string, message: string, actionLabel: string,
  onConfirm: () => void): void {
  const ctx: UIContext | null = dialogContext;
  if (ctx === null) {
    return;
  }
  ctx.showAlertDialog({
    title: title,
    message: message,
    autoCancel: true,
    primaryButton: {
      value: '取消',
      action: () => {
      }
    },
    secondaryButton: {
      value: actionLabel,
      fontColor: Theme.DANGER,
      action: onConfirm
    }
  });
}
