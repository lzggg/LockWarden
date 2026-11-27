/**
 * Logo 展示组件。
 * 图标完全按条目的网址 / 名称自动推导（预置品牌 SVG），不写任何自定义字段，
 * 也不提供手动选择：Bitwarden 里不会出现额外的 logo 字段。
 */
import { Theme } from '../common/Theme';
import {
  BrandLogo, LOGO_FIELD_NAME, LOGO_VALUE_PREFIX, brandOf, logoSvgPath, logoPresetValue,
  matchBrand, matchBrandByUri, initialOf, colorForName
} from '../common/BrandLogos';
import { VaultField } from '../common/Models';

/** 判断是否是历史遗留的 logo 字段（展示时过滤掉，保存时丢弃） */
export function isLogoField(field: VaultField): boolean {
  return field.name === LOGO_FIELD_NAME && field.value.startsWith(LOGO_VALUE_PREFIX);
}

/** 条目该显示哪个 logo：先按网址匹配品牌、再按名称匹配；都没有则返回 ''（用首字头像） */
export function logoRawFor(uri: string, name: string): string {
  const byUri: string = matchBrandByUri(uri === undefined || uri === null ? '' : uri);
  if (byUri.length > 0) {
    return logoPresetValue(byUri);
  }
  const byName: string = matchBrand(name);
  return byName.length > 0 ? logoPresetValue(byName) : '';
}

/** 品牌/自定义/回退 三态头像 */
@Component
export struct BrandAvatar {
  @Prop raw: string = '';
  /** 条目名称：没有 Logo 时用它的首字/首字母生成图标 */
  @Prop name: string = '';
  @Prop fallbackIcon: Resource = $r('sys.symbol.key');
  @Prop fallbackColor: ResourceColor = Theme.PRIMARY;
  @Prop diameter: number = 40;

  private preset(): BrandLogo | null {
    if (!this.raw.startsWith(`${LOGO_VALUE_PREFIX}preset:`)) {
      return null;
    }
    return brandOf(this.raw.substring(LOGO_VALUE_PREFIX.length + 7));
  }

  build() {
    Stack() {
      if (this.preset() !== null) {
        // 白底 + 品牌色真实 Logo
        Image($rawfile(logoSvgPath((this.preset() as BrandLogo).svg)))
          .width(this.diameter * 0.62)
          .height(this.diameter * 0.62)
          .fillColor((this.preset() as BrandLogo).color)
          .objectFit(ImageFit.Contain)
      } else if (initialOf(this.name).length > 0) {
        // 不在内置品牌里的服务：用名称首字/首字母 + 由名称生成的颜色
        Text(initialOf(this.name))
          .fontSize(this.diameter * 0.42)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .width('100%')
          .height('100%')
          .textAlign(TextAlign.Center)
      } else {
        SymbolGlyph(this.fallbackIcon)
          .fontSize(this.diameter * 0.5)
          .fontColor([Color.White])
      }
    }
    .width(this.diameter)
    .height(this.diameter)
    .borderRadius(this.diameter / 2)
    .clip(true)
    .backgroundColor(this.preset() !== null ? Color.White :
      (this.raw.length > 0 ? Color.Transparent :
        (initialOf(this.name).length > 0 ? colorForName(this.name) : this.fallbackColor)))
    .borderWidth(this.preset() !== null ? 1 : 0)
    .borderColor(Theme.DIVIDER)
  }
}
