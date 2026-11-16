/**
 * 列表条目左滑露出的两个操作按钮（左边一个、右边一个）。
 *
 * 保险库列表、文件夹内的条目、回收站三处共用这一个组件，保证左滑的手感与外观完全一致：
 * 外层用 8vp 下内边距抵消卡片底部的 8vp 间距，让按钮与卡片等高；
 * 按钮组四角圆角，和卡片圆角对齐。
 *
 * 颜色与图标由调用方给，因此「收藏/取消收藏」「删除/恢复」都能复用同一套布局。
 */
import { Theme } from '../common/Theme';
import { Icons } from '../common/Icons';

@Component
export struct SwipeActions {
  @Prop leftLabel: string = '收藏';
  @Prop leftIcon: Resource = Icons.star;
  @Prop leftColor: ResourceColor = Theme.FAVORITE;
  @Prop rightLabel: string = '删除';
  @Prop rightIcon: Resource = Icons.trash;
  @Prop rightColor: ResourceColor = Theme.DANGER;
  onLeftTap: () => void = () => {
  };
  onRightTap: () => void = () => {
  };

  @Builder
  actionButton(label: string, icon: Resource, color: ResourceColor, handler: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: 5 }) {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([Color.White])
        Text(label)
          .fontSize(12)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
      }
    }
    .width(78)
    .height('100%')
    .padding(0)
    .borderRadius(0)
    .backgroundColor(color)
    .onClick(() => handler())
  }

  build() {
    Column() {
      Row() {
        this.actionButton(this.leftLabel, this.leftIcon, this.leftColor, this.onLeftTap)
        this.actionButton(this.rightLabel, this.rightIcon, this.rightColor, this.onRightTap)
      }
      .height('100%')
      .borderRadius(Theme.RADIUS)
      .clip(true)
    }
    .height('100%')
    .padding({ bottom: 8 })
    .justifyContent(FlexAlign.Start)
  }
}
