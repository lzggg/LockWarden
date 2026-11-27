/**
 * 自动锁定可选值：
 *  - -1：每次退出应用（切到后台）立即锁定
 *  -  0：从不
 *  - >0：无操作若干分钟后锁定，最长 6 小时
 */
export const LOCK_OPTIONS: number[] = [-1, 0, 1, 5, 10, 15, 30, 60, 120, 240, 360];

export function lockLabel(minutes: number): string {
  if (minutes < 0) {
    return '退出时';
  }
  if (minutes === 0) {
    return '从不';
  }
  if (minutes < 60) {
    return `${minutes} 分钟`;
  }
  return `${minutes / 60} 小时`;
}

export function lockOptions(): SelectOption[] {
  const list: SelectOption[] = [];
  for (let i = 0; i < LOCK_OPTIONS.length; i++) {
    list.push({ value: lockLabel(LOCK_OPTIONS[i]) });
  }
  return list;
}

export function lockIndex(minutes: number): number {
  const found: number = LOCK_OPTIONS.indexOf(minutes);
  if (found >= 0) {
    return found;
  }
  const fallback: number = LOCK_OPTIONS.indexOf(5);
  return fallback >= 0 ? fallback : 0;
}
