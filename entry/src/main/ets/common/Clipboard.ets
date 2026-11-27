/**
 * 剪贴板封装。
 *
 * 单独成一个模块，只给「真正需要剪贴板的页面」导入：
 * DevEco 预览器没有 pasteboard 原生模块，视图组件若静态导入它就无法预览。
 *
 * 复制敏感内容（密码、验证码）后，可选择在若干秒后自动清空剪贴板，
 * 避免内容长期留在系统剪贴板里被其他应用或剪贴板历史读到。
 *
 * 三个关键点（都是踩过的坑）：
 *  1. 读剪贴板需要权限，普通应用 getData() 会抛错；所以不依赖"读回来比对"，
 *     到期直接 clearData()，否则会静默失败；
 *  2. 应用切后台后 JS 定时器会被系统冻结，因此复制时申请一次短时任务
 *     （requestSuspendDelay）让进程在倒计时期间保持可运行；
 *  3. 仍然保留"到期时间 + 回前台补清"的兜底，万一被系统提前冻结，
 *     回到应用时会立即清空。
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'LockWarden';

/** 自动清空秒数；0 表示不自动清空 */
let autoClearSeconds: number = 30;
/** 到期时间戳（毫秒）；0 表示当前没有待清除的内容 */
let expireAt: number = 0;
let timerId: number = -1;
/** 短时任务 id（-1 表示没有申请） */
let delayId: number = -1;

/** 由设置页调用：修改自动清空时长（秒，0 = 不清除） */
export function setAutoClearSeconds(seconds: number): void {
  autoClearSeconds = seconds;
  if (seconds <= 0) {
    expireAt = 0;
    cancelTimer();
    releaseDelay();
  }
}

function cancelTimer(): void {
  if (timerId >= 0) {
    clearTimeout(timerId);
    timerId = -1;
  }
}

/** 申请短时任务，避免应用切到后台后定时器被冻结 */
function acquireDelay(): void {
  if (delayId >= 0) {
    return;
  }
  try {
    const info: backgroundTaskManager.DelaySuspendInfo =
      backgroundTaskManager.requestSuspendDelay('剪贴板自动清除', () => {
      // 系统即将冻结时再兜底清一次
      clearIfExpired();
    });
    delayId = info.requestId;
  } catch (e) {
    delayId = -1;
    hilog.warn(DOMAIN, TAG, 'suspend delay failed: %{public}s', (e as Error).message);
  }
}

function releaseDelay(): void {
  if (delayId < 0) {
    return;
  }
  try {
    backgroundTaskManager.cancelSuspendDelay(delayId);
  } catch (e) {
    // 取消失败不影响功能
  }
  delayId = -1;
}

async function doClear(): Promise<void> {
  try {
    const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    await board.clearData();
    hilog.info(DOMAIN, TAG, '%{public}s', 'clipboard cleared');
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'clipboard clear failed: %{public}s', (e as Error).message);
  } finally {
    expireAt = 0;
    cancelTimer();
    releaseDelay();
  }
}

/** 到期则清空；应用回到前台时也调用它（后台定时器可能被挂起） */
export async function clearIfExpired(): Promise<void> {
  if (expireAt <= 0 || Date.now() < expireAt) {
    return;
  }
  await doClear();
}

/** 写入系统剪贴板，并按设置安排自动清空 */
export async function copyText(text: string): Promise<void> {
  if (text.length === 0) {
    return;
  }
  const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
  await pasteboard.getSystemPasteboard().setData(data);
  cancelTimer();
  if (autoClearSeconds > 0) {
    expireAt = Date.now() + autoClearSeconds * 1000;
    acquireDelay();
    timerId = setTimeout(() => {
      timerId = -1;
      clearIfExpired();
    }, autoClearSeconds * 1000);
    hilog.info(DOMAIN, TAG, 'clipboard copy scheduled in %{public}d s', autoClearSeconds);
  } else {
    expireAt = 0;
    releaseDelay();
  }
}
