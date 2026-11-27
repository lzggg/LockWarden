/**
 * 胶囊小按钮：多选工具条里的「删除 / 收藏 / 取消 / 全选」等都用它，尺寸与圆角保持一致。
 */
import { Theme } from '../common/Theme';

@Component
export struct Pill {
  @Prop label: string = '';
  @Prop textColor: ResourceColor = Theme.TEXT_SECONDARY;
  @Prop fill: ResourceColor = Theme.BACKGROUND;
  /** true 时占满剩余宽度（用于「已选 N 项」这种占位文字） */
  @Prop stretch: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    if (this.stretch) {
      Text(this.label)
        .fontSize(13)
        .fontColor(this.textColor)
        .layoutWeight(1)
    } else {
      Text(this.label)
        .fontSize(13)
        .fontColor(this.textColor)
        .backgroundColor(this.fill)
        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
        .borderRadius(16)
        .onClick(() => this.onTap())
    }
  }
}
