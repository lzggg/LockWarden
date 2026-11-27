/** 统一配色与尺寸，避免各页面散落魔法值 */
export class Theme {
  // 颜色走资源引用（resources/base|dark/element/color.json），
  // 这样切换深色 / 浅色模式时系统会自动换色，不需要每处代码判断。
  static readonly PRIMARY: Resource = $r('app.color.app_primary');
  static readonly BACKGROUND: Resource = $r('app.color.app_background');
  static readonly CARD: Resource = $r('app.color.app_card');
  static readonly TEXT_PRIMARY: Resource = $r('app.color.app_text_primary');
  static readonly TEXT_SECONDARY: Resource = $r('app.color.app_text_secondary');
  static readonly TEXT_HINT: Resource = $r('app.color.app_text_hint');
  static readonly DIVIDER: Resource = $r('app.color.app_divider');
  static readonly DANGER: Resource = $r('app.color.app_danger');
  static readonly SUCCESS: Resource = $r('app.color.app_success');
  /** 浅色蓝底（chips / 选中态背景） */
  static readonly TINT: Resource = $r('app.color.app_tint');
  /** 收藏星标的橙黄 */
  static readonly FAVORITE: Resource = $r('app.color.app_favorite');
  static readonly RADIUS: number = 16;
  static readonly RADIUS_SMALL: number = 10;
  static readonly PAGE_PADDING: number = 16;
  static readonly FONT_TITLE: number = 24;
  static readonly FONT_BODY: number = 16;
  static readonly FONT_CAPTION: number = 13;
}

/** 条目类型 -> 展示用图标与名称 */
export class CipherMeta {
  static label(type: number): string {
    switch (type) {
      case 1:
        return '登录';
      case 2:
        return '笔记';
      case 3:
        return '卡片';
      case 4:
        return '身份';
      default:
        return '其他';
    }
  }
}

/** 北京时间（UTC+8）的 年月日，不依赖设备时区 */
export function beijingDate(timestamp: number): string {
  const offset: number = 8 * 60 * 60 * 1000;
  const d: Date = new Date(timestamp + offset);
  return `${d.getUTCFullYear()}年${d.getUTCMonth() + 1}月${d.getUTCDate()}日`;
}

/** 北京时间（UTC+8）的 HH:mm，不依赖设备时区 */
export function beijingClock(timestamp: number): string {
  const offset: number = 8 * 60 * 60 * 1000;
  const d: Date = new Date(timestamp + offset);
  const hh: number = d.getUTCHours();
  const mm: number = d.getUTCMinutes();
  const hhText: string = hh < 10 ? `0${hh}` : `${hh}`;
  const mmText: string = mm < 10 ? `0${mm}` : `${mm}`;
  return `${hhText}:${mmText}`;
}

/**
 * 保险库标题下的同步状态：
 * 同步中 → “正在同步…”；一分钟内 → “刚刚同步”；否则 → “同步完成 2026年11月14日 22:59”
 */
export function syncLabel(timestamp: number, syncing: boolean): string {
  if (syncing) {
    return '正在同步…';
  }
  if (timestamp <= 0) {
    return '尚未同步';
  }
  if (Date.now() - timestamp < 60 * 1000) {
    return '刚刚同步';
  }
  return `同步完成 ${beijingDate(timestamp)} ${beijingClock(timestamp)}`;
}

/** 从 URI 里提取主机名，用于列表副标题 */
export function hostOf(uri: string): string {
  if (uri.length === 0) {
    return '';
  }
  let text: string = uri;
  const scheme: number = text.indexOf('://');
  if (scheme >= 0) {
    text = text.substring(scheme + 3);
  }
  const slash: number = text.indexOf('/');
  if (slash >= 0) {
    text = text.substring(0, slash);
  }
  return text;
}
