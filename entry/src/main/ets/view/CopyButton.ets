/**
 * 通用的"复制"小圆钮（浅蓝底 + 复制图标）。
 * 详情页、验证器页等多处复用，避免每处重复写一遍尺寸与配色。
 */
import { Theme } from '../common/Theme';
import { Icons } from '../common/Icons';

@Component
export struct CopyButton {
  @Prop diameter: number = 34;
  @Prop iconSize: number = 18;
  onTap: () => void = () => {
  };

  build() {
    Row() {
      SymbolGlyph(Icons.copy)
        .fontSize(this.iconSize)
        .fontColor([Theme.PRIMARY])
    }
    .width(this.diameter)
    .height(this.diameter)
    .borderRadius(this.diameter / 2)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Theme.TINT)
    .onClick(() => this.onTap())
  }
}
