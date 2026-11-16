/**
 * 通用确认框：左边「取消」、右边危险操作（红色）。
 * 删除/彻底删除/批量删除等场景统一走这里，避免每个页面各写一份 AlertDialog。
 */
import { Theme } from './Theme';

export function confirmDanger(title: string, message: string, actionLabel: string,
  onConfirm: () => void): void {
  AlertDialog.show({
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
