/**
 * 密码可见性切换按钮（卡通风格）。
 *
 * 系统符号（sys.symbol.eye）偏拟真，和整体圆润界面不搭，这里自绘：
 *   杏核形眼白（左右收尖）+ 圆瞳孔 + 左上高光；明文态叠一道圆头斜杠。
 *
 * 眼白用 Polygon 而不是 Path/Ellipse：
 *  - Ellipse 两端是圆的，达不到"尖一点"的效果；
 *  - Path 在本工程的 Stack 里坐标解释异常（图形被压扁并偏移），改为按公式生成顶点，
 *    "杏核"正好等于两个半径相同的大圆弧相交：y = ±(sqrt(R²-x²) - (R-ry))。
 *
 * 纯 ArkUI 图形拼接，无图片资源。
 */
import { Theme } from '../common/Theme';

const EYE_BOX_W: number = 24;
const EYE_BOX_H: number = 16;
const EYE_RX: number = 10;
const EYE_RY: number = 6;

/** 生成杏核轮廓顶点（上半弧 → 下半弧，两端为尖角） */
function almondPoints(): number[][] {
  const cx: number = EYE_BOX_W / 2;
  const cy: number = EYE_BOX_H / 2;
  // 两段半径为 R 的圆弧相交出 rx*2 宽、ry*2 高的透镜形
  const r: number = (EYE_RX * EYE_RX + EYE_RY * EYE_RY) / (2 * EYE_RY);
  const offset: number = r - EYE_RY;
  const steps: number = 16;
  const points: number[][] = [];
  for (let i = 0; i <= steps; i++) {
    const x: number = -EYE_RX + (2 * EYE_RX) * i / steps;
    const y: number = Math.sqrt(Math.max(0, r * r - x * x)) - offset;
    points.push([cx + x, cy - y]);
  }
  for (let i = steps - 1; i >= 1; i--) {
    const x: number = -EYE_RX + (2 * EYE_RX) * i / steps;
    const y: number = Math.sqrt(Math.max(0, r * r - x * x)) - offset;
    points.push([cx + x, cy + y]);
  }
  return points;
}

@Component
export struct EyeToggle {
  /** true = 当前是明文显示（按钮语义为"隐藏"） */
  @Prop revealed: boolean = false;
  onToggle: () => void = () => {
  };

  private static readonly ALMOND: number[][] = almondPoints();

  build() {
    Stack() {
      // 眼白：杏核形
      Polygon()
        .width(EYE_BOX_W)
        .height(EYE_BOX_H)
        .points(EyeToggle.ALMOND)
        .fill(Color.White)
        .stroke(this.revealed ? Theme.PRIMARY : '#7A8591')
        .strokeWidth(1.5)
        .strokeLineJoin(LineJoinStyle.Round)

      // 瞳孔
      Circle()
        .width(6.5)
        .height(6.5)
        .fill(this.revealed ? Theme.PRIMARY : '#5C6773')

      // 高光：偏左上，眼睛才"活"
      Circle()
        .width(2)
        .height(2)
        .fill(Color.White)
        .offset({ x: -1.4, y: -1.4 })

      // 明文状态：一道圆头斜杠
      if (this.revealed) {
        Line()
          .width(34)
          .height(34)
          .startPoint([8, 26])
          .endPoint([26, 8])
          .stroke(Theme.PRIMARY)
          .strokeWidth(1.9)
          .strokeLineCap(LineCapStyle.Round)
      }
    }
    .width(34)
    .height(34)
    .borderRadius(17)
    .backgroundColor(this.revealed ? Theme.TINT : Color.Transparent)
    .onClick(() => this.onToggle())
  }
}
