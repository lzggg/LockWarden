/**
 * 通知栏「复制对应密码」快捷入口。
 *
 * 场景：在条目详情里复制了用户名，切到别的 App 粘贴后往往还需要密码。
 * 这里发一条 30 秒后自动消失的通知，点一下回到应用并把该条目的密码复制好。
 *
 * 注意：
 *  - 通知正文不写条目名，避免锁屏预览泄露"你在用哪个网站"；
 *  - 用户拒绝通知授权时静默跳过，不影响复制本身；
 *  - 点击通知走 WantAgent 启动 EntryAbility，凭 parameters 里的条目 id 交给页面处理；
 *  - 先直接 publish，失败再请求授权后重试（不依赖 isNotificationEnabled，
 *    那个接口在某些设备上会长时间不返回）。
 */
import { notificationManager } from '@kit.NotificationKit';
import { common, wantAgent, WantAgent, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

const BUNDLE_NAME: string = 'com.example.lockwarden';
const NOTIFICATION_ID: number = 1001;
const DEFAULT_KEEP_SECONDS: number = 30;
/** 通知点击后发出的公共事件：应用在后台订阅它，直接复制密码，不切前台 */
export const COPY_EVENT: string = 'com.example.lockwarden.action.COPY_PASSWORD';

/** 是否已经弹过授权框，避免每次都问 */
let prompted: boolean = false;
let dismissTimer: number = -1;
/** 通知存在期间申请短时任务，保证后台仍能响应点击事件 */
let delayId: number = -1;

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

function acquireDelay(): void {
  if (delayId >= 0) {
    return;
  }
  try {
    const info: backgroundTaskManager.DelaySuspendInfo =
      backgroundTaskManager.requestSuspendDelay('通知栏快捷复制', () => {
        // 系统即将冻结时无需额外处理
      });
    delayId = info.requestId;
  } catch (e) {
    delayId = -1;
  }
}

/** 确保存在高优先级通道（SOCIAL_COMMUNICATION → 状态栏图标 + 横幅） */
async function ensureSlot(): Promise<void> {
  try {
    await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION);
  } catch (e) {
    // 已存在或系统不允许时忽略
  }
}

/** 发一条「点按复制密码」的通知；返回是否成功 */
async function publishHint(itemId: string, keepSeconds: number): Promise<boolean> {
  const aliveMs: number = Math.max(10, keepSeconds) * 1000;
  try {
    const want: Want = {
      bundleName: BUNDLE_NAME,
      action: COPY_EVENT,
      parameters: { 'copyPasswordItemId': itemId }
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [want],
      operationType: wantAgent.OperationType.SEND_COMMON_EVENT,
      requestCode: 1
    };
    const agent: WantAgent = await wantAgent.getWantAgent(info);
    await ensureSlot();
    await notificationManager.publish({
      id: NOTIFICATION_ID,
      // SOCIAL_COMMUNICATION 对应 LEVEL_HIGH：状态栏图标 + 横幅（弹窗），无需下拉通知栏
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      tapDismissed: true,
      isAlertOnce: true,
      // 常驻 2 分钟，方便用户错过横幅后回通知栏点按；横幅本身弹出时长由系统决定
      isOngoing: true,
      autoDeletedTime: Date.now() + aliveMs,
      actionButtons: [{ title: '复制密码', wantAgent: agent }],
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: '用户名已复制',
          text: '点按这里复制同一账号的密码'
        }
      },
      wantAgent: agent
    });
    acquireDelay();
    if (dismissTimer >= 0) {
      clearTimeout(dismissTimer);
    }
    dismissTimer = setTimeout(() => {
      dismissTimer = -1;
      releaseDelay();
      notificationManager.cancel(NOTIFICATION_ID).catch(() => {
      });
    }, aliveMs);
    return true;
  } catch (e) {
    hilog.warn(0x0001, 'LockWarden', 'notify publish failed: %{public}s', (e as Error).message);
    return false;
  }
}

/** 复制用户名后调用：发通知，点按可复制同一账号的密码 */
export async function offerPasswordCopy(context: common.UIAbilityContext, itemId: string,
  keepSeconds: number = DEFAULT_KEEP_SECONDS): Promise<void> {
  if (itemId.length === 0) {
    return;
  }
  if (await publishHint(itemId, keepSeconds)) {
    return;
  }
  if (prompted) {
    return;
  }
  prompted = true;
  try {
    await notificationManager.requestEnableNotification(context);
  } catch (e) {
    hilog.warn(0x0001, 'LockWarden', 'notify permission failed: %{public}s', (e as Error).message);
    return;
  }
  await publishHint(itemId, keepSeconds);
}
