/**
 * 图标与配色映射。
 *
 * 图标全部使用系统矢量符号（SymbolGlyph + sys.symbol.*），不引入任何图片资源：
 *  - 可随主题/状态自动着色，不用为每种颜色准备一套切图；
 *  - 体积极小，且不存在第三方美术资源的授权问题。
 *
 * 下面这些名字都在 DevEco SDK 26 里逐个编译验证过（不存在的名字会直接编译报错）。
 */

/** 条目类型对应的主题色（仿 Bitwarden 各类条目圆形头像的配色） */
export function typeColor(type: number): string {
  switch (type) {
    case 1:
      return '#0A59F7'; // 登录：蓝
    case 2:
      return '#F5A623'; // 笔记：橙
    case 3:
      return '#7B61FF'; // 卡片：紫
    case 4:
      return '#00A870'; // 身份：绿
    default:
      return '#6B7785';
  }
}

/** 条目类型图标 */
export function typeSymbol(type: number): Resource {
  switch (type) {
    case 1:
      return $r('sys.symbol.key');
    case 2:
      return $r('sys.symbol.doc_text');
    case 3:
      return $r('sys.symbol.creditcard');
    case 4:
      return $r('sys.symbol.person');
    default:
      return $r('sys.symbol.doc_plaintext');
  }
}

/** 首页/导航常用图标 */
export class Icons {
  static readonly vault: Resource = $r('sys.symbol.lock');
  static readonly lock: Resource = $r('sys.symbol.lock');
  static readonly generator: Resource = $r('sys.symbol.wand_and_stars');
  static readonly shield: Resource = $r('sys.symbol.security_shield');
  static readonly settings: Resource = $r('sys.symbol.gearshape');
  static readonly search: Resource = $r('sys.symbol.magnifyingglass');
  /** 扫码添加（验证器） */
  static readonly scan: Resource = $r('sys.symbol.barcode_viewfinder');
  static readonly add: Resource = $r('sys.symbol.plus');
  static readonly refresh: Resource = $r('sys.symbol.arrow_clockwise');
  static readonly restore: Resource = $r('sys.symbol.arrow_counterclockwise');
  static readonly star: Resource = $r('sys.symbol.star');
  static readonly starFill: Resource = $r('sys.symbol.star_fill');
  static readonly copy: Resource = $r('sys.symbol.rectangle_on_rectangle');
  static readonly chevron: Resource = $r('sys.symbol.chevron_right');
  static readonly check: Resource = $r('sys.symbol.checkmark');
  static readonly close: Resource = $r('sys.symbol.xmark');
  static readonly folder: Resource = $r('sys.symbol.folder');
  static readonly trash: Resource = $r('sys.symbol.trash');
  /** 隐私：不允许截图（相机加斜杠） */
  static readonly privacy: Resource = $r('sys.symbol.camera_slash');
  static readonly edit: Resource = $r('sys.symbol.square_and_pencil');
  static readonly lockOpen: Resource = $r('sys.symbol.lock_open');
static readonly timer: Resource = $r('sys.symbol.timer');
static readonly clipboard: Resource = $r('sys.symbol.text_clipboard');
  static readonly touchId: Resource = $r('sys.symbol.touchid');
  static readonly faceId: Resource = $r('sys.symbol.face');
}
