/**
 * Logo 展示与选择相关的 UI 组件。
 * 预置品牌用 rawfile 里的真实品牌 SVG（按品牌色着色，白底圆），自定义 Logo 用 Base64 图片。
 */
import { Theme } from '../common/Theme';
import {
  BRAND_LOGOS, BrandLogo, LOGO_FIELD_NAME, LOGO_VALUE_PREFIX, brandOf, logoSvgPath, logoPresetValue
} from '../common/BrandLogos';
import { VaultField } from '../common/Models';
import { initialOf, colorForName } from '../common/BrandLogos';

/** 从自定义字段里取出 logo 字段的原始值；没有返回 '' */
export function logoRawOf(fields: VaultField[] | null | undefined): string {
  if (fields === null || fields === undefined) {
    return '';
  }
  for (let i = 0; i < fields.length; i++) {
    if (fields[i].name === LOGO_FIELD_NAME && fields[i].value.startsWith(LOGO_VALUE_PREFIX)) {
      return fields[i].value;
    }
  }
  return '';
}

/** 判断是否是保留的 logo 字段（展示时要过滤掉） */
export function isLogoField(field: VaultField): boolean {
  return field.name === LOGO_FIELD_NAME && field.value.startsWith(LOGO_VALUE_PREFIX);
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
      } else if (this.raw.startsWith(`${LOGO_VALUE_PREFIX}custom:`)) {
        Image(this.raw.substring(LOGO_VALUE_PREFIX.length + 7))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
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

/** 选择 Logo 的弹窗（预置品牌网格 + 清除） */
@CustomDialog
export struct LogoPickerDialog {
  controller?: CustomDialogController;
  onPick: (raw: string) => void = () => {
  };
  @State query: string = '';

  /** 搜索：品牌名 / key / 中英文关键字都能命中 */
  private results(): BrandLogo[] {
    const q: string = this.query.trim().toLowerCase();
    if (q.length === 0) {
      return BRAND_LOGOS;
    }
    const list: BrandLogo[] = [];
    for (let i = 0; i < BRAND_LOGOS.length; i++) {
      const brand: BrandLogo = BRAND_LOGOS[i];
      let hit: boolean = brand.label.toLowerCase().indexOf(q) >= 0 ||
        brand.key.toLowerCase().indexOf(q) >= 0;
      if (!hit) {
        for (let k = 0; k < brand.aliases.length; k++) {
          if (brand.aliases[k].indexOf(q) >= 0) {
            hit = true;
            break;
          }
        }
      }
      if (hit) {
        list.push(brand);
      }
    }
    return list;
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('选择 Logo')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('不用')
          .fontSize(13)
          .fontColor(Theme.TEXT_SECONDARY)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(Theme.BACKGROUND)
          .borderRadius(14)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
            this.onPick('');
          })
      }
      .width('100%')

      // 搜索框
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([Theme.TEXT_HINT])
        TextInput({ text: this.query, placeholder: '搜索品牌，如 google / 微信 / 淘宝' })
          .fontColor(Theme.TEXT_PRIMARY)
          .placeholderColor(Theme.TEXT_HINT)
          .layoutWeight(1)
          .height(38)
          .borderRadius(10)
          .backgroundColor(Color.Transparent)
          .fontSize(14)
          .padding(0)
          .onChange((v: string) => {
            this.query = v;
          })
        if (this.query.length > 0) {
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(16)
            .fontColor([Theme.TEXT_HINT])
            .onClick(() => {
              this.query = '';
            })
        }
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 2, bottom: 2 })
      .borderRadius(10)
      .backgroundColor(Theme.BACKGROUND)

      Grid() {
        ForEach(this.results(), (brand: BrandLogo) => {
          GridItem() {
            Column({ space: 6 }) {
              Stack() {
                Image($rawfile(logoSvgPath(brand.svg)))
                  .width(28)
                  .height(28)
                  .fillColor(brand.color)
                  .objectFit(ImageFit.Contain)
              }
              .width(46)
              .height(46)
              .borderRadius(23)
              .backgroundColor(Color.White)
              .borderWidth(1)
              .borderColor(Theme.DIVIDER)

              Text(brand.label)
                .fontSize(10)
                .fontColor(Theme.TEXT_SECONDARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .onClick(() => {
              if (this.controller !== undefined) {
                this.controller.close();
              }
              this.onPick(logoPresetValue(brand.key));
            })
          }
        }, (brand: BrandLogo) => brand.key)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsGap(12)
      .columnsGap(8)
      .height(360)
      .width('100%')

      if (this.results().length === 0) {
        Text('没有匹配的品牌，可换个关键词')
          .fontSize(13)
          .fontColor(Theme.TEXT_HINT)
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('92%')
    .padding(16)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.CARD)
  }
}
