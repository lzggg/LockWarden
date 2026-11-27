/**
 * 生成器页（底部导航第二个 Tab）。
 * 控件全部来自 PasswordGeneratorPanel，与「新建条目」弹层保持一致。
 *
 * 布局按「本页实际可用区域」判定，而不是整块屏幕：
 *  - 宽度 >= 860vp                      → 左右两栏
 *  - 宽度 >= 620vp 且高度 < 700vp        → 左右两栏（大折叠展开、折叠横屏这类"宽但矮"的形态）
 *  - 其余                                → 单列
 *  - 高度 < 700vp 时进入 compact，压缩预览区/按钮高度，避免内容被截
 *  - 内容仍放不下时由 Scroll 兜底（隐藏滚动条，能放下时完全不滚动）
 */
import { Theme } from '../common/Theme';
import { PasswordGeneratorPanel } from './PasswordGeneratorPanel';
import { Responsive } from '../common/Responsive';

/** 宽度达到该值就用两栏 */
const TWO_COLUMN_WIDTH: number = 860;
/** "宽但矮"形态的两栏阈值：宽度下限 */
const NARROW_TWO_COLUMN_WIDTH: number = 620;
/** 高度低于该值时压缩控件，并允许"宽但矮"的形态改两栏 */
const SHORT_HEIGHT: number = 700;
/** 超大屏内容最大宽度，避免控件被拉得过宽 */
const MAX_CONTENT_WIDTH: number = 1180;

@Component
export struct GeneratorView {
  /** 返回 [0, bound) 的随机整数 */
  random: (bound: number) => number = (bound: number) => Math.floor(Math.random() * bound);
  onCopy: (label: string, value: string) => void = () => {
  };

  /** 宽屏：面板走左右两栏 */
  @State wide: boolean = Responsive.isWideNow();
  /** 高度偏矮：压缩控件高度，保证一屏放得下 */
  @State compact: boolean = !Responsive.isWideNow() && Responsive.isCompactNow();

  /** 按可用区域重新决定布局（横竖屏、折叠展开、分屏都会触发） */
  private applyLayout(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    const two: boolean = width >= TWO_COLUMN_WIDTH ||
      (width >= NARROW_TWO_COLUMN_WIDTH && height < SHORT_HEIGHT);
    const narrow: boolean = height < SHORT_HEIGHT;
    if (this.wide !== two) {
      this.wide = two;
    }
    if (this.compact !== narrow) {
      this.compact = narrow;
    }
  }

  build() {
    Column() {
      Row() {
        Text('生成器')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
      }
      .width('100%')
      .padding({ top: 8, bottom: 16 })

      // 内容区：能放下时不滚动；超大屏限制最大宽度并居中
      Scroll() {
        Column() {
          PasswordGeneratorPanel({
            random: (bound: number) => this.random(bound),
            actionLabel: '复制',
            showClose: false,
            horizontal: this.wide,
            compact: this.compact,
            onAction: (password: string) => this.onCopy('密码', password)
          })
            .margin({ top: this.compact ? 8 : 16 })

          Text('密码在设备本地生成，不会上传到服务器')
            .fontSize(12)
            .fontColor(Theme.TEXT_HINT)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 16, bottom: 96 })
        }
        .width('100%')
        .constraintSize({ maxWidth: MAX_CONTENT_WIDTH })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: Theme.PAGE_PADDING, right: Theme.PAGE_PADDING })
    .backgroundColor(Theme.BACKGROUND)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.applyLayout(Number(newValue.width), Number(newValue.height));
    })
  }
}
