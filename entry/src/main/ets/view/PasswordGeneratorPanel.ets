/**
 * 密码生成面板（生成器页与「新建条目」弹层共用）。
 *
 * 控件：密码预览、重新生成、长度滑杆、最少数字/特殊字符、四组字符集开关。
 * 底部主按钮的文案与行为由外部注入：
 *  - 生成器页：'复制'
 *  - 新建条目弹层：'使用此密码'
 *
 * 宽屏（平板）时用 horizontal=true 走左右两栏，一屏放得下、不用滚。
 *
 * 随机源同样由外部注入（真机为密码学安全随机数），本组件不依赖任何原生模块。
 */
import { Theme } from '../common/Theme';
import { Icons } from '../common/Icons';
import {
  PasswordOptions, PASSWORD_MIN_LENGTH, PASSWORD_MAX_LENGTH, generatePassword, defaultPasswordOptions
} from '../common/PasswordGenerator';

/**
 * 单个复选框。
 *
 * 必须做成独立组件而不是 @Builder：@Builder 的按值参数不会触发刷新，
 * 勾选状态（on）作为参数传进去时，点击后界面不会重绘，看起来就是"点了没反应"。
 */
@Component
struct CheckToggle {
  @Prop label: string = '';
  @Prop checked: boolean = false;
  onFlip: () => void = () => {
  };

  build() {
    Row({ space: 8 }) {
      Stack() {
        // 勾号常驻，用透明度+缩放做进出动画，避免"瞬间出现"的突兀感
        SymbolGlyph(Icons.check)
          .fontSize(12)
          .fontColor([Color.White])
          .opacity(this.checked ? 1 : 0)
          .scale({ x: this.checked ? 1 : 0.4, y: this.checked ? 1 : 0.4 })
          .animation({ duration: 160, curve: Curve.EaseOut })
      }
      .width(20)
      .height(20)
      .borderRadius(6)
      .borderWidth(1.5)
      .borderColor(this.checked ? Theme.PRIMARY : Theme.DIVIDER)
      .backgroundColor(this.checked ? Theme.PRIMARY : Color.Transparent)
      .scale({ x: this.checked ? 1 : 0.92, y: this.checked ? 1 : 0.92 })
      .animation({ duration: 160, curve: Curve.EaseOut })

      Text(this.label)
        .fontSize(Theme.FONT_CAPTION)
        .fontColor(this.checked ? Theme.TEXT_PRIMARY : Theme.TEXT_SECONDARY)
        .animation({ duration: 160, curve: Curve.EaseOut })
    }
    .width('50%')
    .height(40)
    .padding({ right: 4 })
    .onClick(() => this.onFlip())
  }
}

/**
 * 滑块行：标题在上，滑块在下，数值做成跟随滑块位置浮动的小气泡。
 * 独立组件：数值作为参数传入，@Builder 不会随参数刷新。
 */
@Component
struct SliderRow {
  @Prop label: string = '';
  @Prop value: number = 0;
  @Prop minValue: number = 0;
  @Prop maxValue: number = 64;
  @Prop active: boolean = true;
  onChange: (value: number) => void = () => {
  };

  /** 滑块轨道宽度（vp），用于把气泡定位到滑块正上方 */
  @State trackWidth: number = 0;

  /** 气泡左偏移：滑块中心 - 半个气泡宽，并夹在轨道范围内 */
  private bubbleOffset(): number {
    const bubbleWidth: number = 26;
    const thumbSize: number = 24;
    const usable: number = Math.max(0, this.trackWidth - thumbSize);
    const ratio: number = this.maxValue > this.minValue ?
      (this.value - this.minValue) / (this.maxValue - this.minValue) : 0;
    const thumbCenter: number = thumbSize / 2 + usable * ratio;
    const left: number = thumbCenter - bubbleWidth / 2;
    return Math.max(0, Math.min(Math.max(0, this.trackWidth - bubbleWidth), left));
  }

  build() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        Text(this.label)
          .fontSize(Theme.FONT_BODY)
          .fontColor(this.active ? Theme.TEXT_PRIMARY : Theme.TEXT_HINT)
        Blank()
      }
      .width('100%')

      Stack({ alignContent: Alignment.Start }) {
        Slider({
          value: this.value,
          min: this.minValue,
          max: this.maxValue,
          step: 1,
          style: SliderStyle.OutSet
        })
          .width('100%')
          .selectedColor(this.active ? Theme.PRIMARY : Theme.TEXT_HINT)
          .trackThickness(10)
          .trackBorderRadius(5)
          .blockSize({ width: 24, height: 24 })
          .blockColor(Color.White)
          .onChange((value: number) => {
            // 即使这一行看起来是灰的（对应字符集未勾选），拖动也要生效：
            // 外层会顺手把字符集打开，避免"拖了没反应"
            const next: number = Math.round(value);
            if (next !== this.value) {
              this.onChange(next);
            }
          })

        // 浮动的数值气泡
        Text(`${this.value}`)
          .fontSize(11)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .width(26)
          .padding({ top: 1, bottom: 1 })
          .borderRadius(8)
          .backgroundColor(this.active ? Theme.PRIMARY : Theme.TEXT_HINT)
          .offset({ x: this.bubbleOffset(), y: -22 })
          .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const width: number = Number(newValue.width);
        if (!Number.isNaN(width) && width > 0) {
          this.trackWidth = width;
        }
      })
    }
    .width('100%')
    .padding({ top: 2, bottom: 0 })
    .opacity(this.active ? 1 : 0.45)
  }
}

@Component
export struct PasswordGeneratorPanel {
  random: (bound: number) => number = (bound: number) => Math.floor(Math.random() * bound);
  actionLabel: string = '复制';
  onAction: (password: string) => void = () => {
  };
  showClose: boolean = false;
  onClose: () => void = () => {
  };
  title: string = '密码生成器';
  /** 宽屏（平板横屏）用左右两栏，避免一页放不下还要滚动 */
  @Prop horizontal: boolean = false;
  /** 高度紧张（大折叠展开/小平板横屏）时压缩预览和按钮高度 */
  @Prop compact: boolean = false;

  @State password: string = '';
  @State length: number = 16;
  @State useUpper: boolean = true;
  @State useLower: boolean = true;
  @State useDigits: boolean = true;
  @State useSymbols: boolean = false;
  /** 至少包含的数字 / 特殊字符个数 */
  @State minDigits: number = 0;
  @State minSymbols: number = 0;

  aboutToAppear(): void {
    const defaults: PasswordOptions = defaultPasswordOptions();
    this.length = defaults.length;
    this.useUpper = defaults.upper;
    this.useLower = defaults.lower;
    this.useDigits = defaults.digits;
    this.useSymbols = defaults.symbols;
    this.minDigits = defaults.minDigits;
    this.minSymbols = defaults.minSymbols;
    this.regenerate();
  }

  private options(): PasswordOptions {
    const options: PasswordOptions = {
      length: this.length,
      upper: this.useUpper,
      lower: this.useLower,
      digits: this.useDigits,
      symbols: this.useSymbols,
      minDigits: this.useDigits ? this.minDigits : 0,
      minSymbols: this.useSymbols ? this.minSymbols : 0
    };
    return options;
  }

  private regenerate(): void {
    if (!this.useUpper && !this.useLower && !this.useDigits && !this.useSymbols) {
      this.useLower = true;
    }
    this.password = generatePassword(this.options(), this.random);
  }

  /**
   * 切换某一组字符。
   * 最后一种字符不允许关掉：否则会静默还原勾选状态，看起来像"点了没反应"。
   * 这里改为明确提示，并保持勾选。
   */
  private toggleCharset(kind: string): void {
    const active: number = (this.useUpper ? 1 : 0) + (this.useLower ? 1 : 0) +
      (this.useDigits ? 1 : 0) + (this.useSymbols ? 1 : 0);
    let current: boolean = false;
    if (kind === 'upper') {
      current = this.useUpper;
    } else if (kind === 'lower') {
      current = this.useLower;
    } else if (kind === 'digits') {
      current = this.useDigits;
    } else {
      current = this.useSymbols;
    }
    if (current && active <= 1) {
      this.getUIContext().getPromptAction().showToast({
        message: '至少要保留一种字符类型',
        duration: 1600
      });
      return;
    }
    if (kind === 'upper') {
      this.useUpper = !this.useUpper;
    } else if (kind === 'lower') {
      this.useLower = !this.useLower;
    } else if (kind === 'digits') {
      this.useDigits = !this.useDigits;
      if (!this.useDigits) {
        this.minDigits = 0;
      }
    } else {
      this.useSymbols = !this.useSymbols;
      if (!this.useSymbols) {
        this.minSymbols = 0;
      }
    }
    this.clampMinCounts();
    this.regenerate();
  }

  /** 两个最小值之和不能超过密码长度 */
  private clampMinCounts(): void {
    if (this.minDigits + this.minSymbols > this.length) {
      this.minSymbols = Math.max(0, this.length - this.minDigits);
      if (this.minDigits + this.minSymbols > this.length) {
        this.minDigits = Math.max(0, this.length - this.minSymbols);
      }
    }
  }

  @Builder
  titleBar() {
    Row() {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_PRIMARY)
      Blank()
      Row() {
        SymbolGlyph(Icons.close)
          .fontSize(16)
          .fontColor([Theme.TEXT_SECONDARY])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Theme.BACKGROUND)
      .onClick(() => this.onClose())
    }
    .width('100%')
  }

  /** 密码预览：固定高度，一行时上下居中，两行时也能完整显示 */
  @Builder
  previewBlock() {
    Column() {
      Text(this.password)
        .fontSize(20)
        .fontColor(Theme.TEXT_PRIMARY)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
        .copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .height(this.compact ? 72 : 92)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 16, right: 16 })
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.CARD)
  }

  @Builder
  charsetBlock() {
    Column({ space: 6 }) {
      Row() {
        CheckToggle({
          label: '大写 A-Z',
          checked: this.useUpper,
          onFlip: () => this.toggleCharset('upper')
        })
        CheckToggle({
          label: '小写 a-z',
          checked: this.useLower,
          onFlip: () => this.toggleCharset('lower')
        })
      }
      .width('100%')

      Row() {
        CheckToggle({
          label: '数字 0-9',
          checked: this.useDigits,
          onFlip: () => this.toggleCharset('digits')
        })
        CheckToggle({
          label: '符号 !@#',
          checked: this.useSymbols,
          onFlip: () => this.toggleCharset('symbols')
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(this.compact ? 12 : 14)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.CARD)
  }

  /** 长度 + 最少数字 / 最少特殊字符（统一用滑块） */
  @Builder
  slidersBlock() {
    Column({ space: 2 }) {
      SliderRow({
        label: '最少数字个数',
        value: this.minDigits,
        minValue: 0,
        maxValue: this.length,
        active: this.useDigits,
        onChange: (value: number) => {
          if (!this.useDigits) {
            this.useDigits = true;
          }
          this.minDigits = value;
          // 长度固定时两类下限之和不能超过长度：抬高数字，符号自动让位
          const room: number = Math.max(0, this.length - value);
          if (this.minSymbols > room) {
            this.minSymbols = room;
          }
          this.regenerate();
        }
      })
      SliderRow({
        label: '最少特殊字符个数',
        value: this.minSymbols,
        minValue: 0,
        maxValue: this.length,
        active: this.useSymbols,
        onChange: (value: number) => {
          if (!this.useSymbols) {
            this.useSymbols = true;
          }
          this.minSymbols = value;
          // 同上：抬高符号，数字自动让位
          const room: number = Math.max(0, this.length - value);
          if (this.minDigits > room) {
            this.minDigits = room;
          }
          this.regenerate();
        }
      })
      SliderRow({
        label: '长度',
        value: this.length,
        minValue: PASSWORD_MIN_LENGTH,
        maxValue: PASSWORD_MAX_LENGTH,
        active: true,
        onChange: (value: number) => {
          this.length = value;
          this.clampMinCounts();
          this.regenerate();
        }
      })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 4, bottom: 4 })
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.CARD)
  }

  @Builder
  buttonsBlock() {
    Column({ space: 10 }) {
      // 与主按钮同尺寸的次要按钮
      Button('重新生成')
        .width('100%')
        .height(this.compact ? 42 : 46)
        .borderRadius(23)
        .backgroundColor(Theme.TINT)
        .fontColor(Theme.PRIMARY)
        .fontSize(Theme.FONT_BODY)
        .onClick(() => this.regenerate())

      Button(this.actionLabel)
        .width('100%')
        .height(this.compact ? 42 : 46)
        .borderRadius(23)
        .backgroundColor(Theme.PRIMARY)
        .fontColor(Color.White)
        .fontSize(Theme.FONT_BODY)
        .onClick(() => this.onAction(this.password))
    }
    .width('100%')
  }

  build() {
    if (this.horizontal) {
      // 宽屏：左栏密码 + 字符集，右栏滑杆 + 按钮
      Column({ space: 12 }) {
        if (this.showClose) {
          this.titleBar()
        }
        Row({ space: 16 }) {
          Column({ space: 10 }) {
            this.previewBlock()
            this.charsetBlock()
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 10 }) {
            this.slidersBlock()
            this.buttonsBlock()
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
    } else {
      Column({ space: 14 }) {
        if (this.showClose) {
          this.titleBar()
        }
        this.previewBlock()
        this.charsetBlock()
        this.slidersBlock()
        this.buttonsBlock()
      }
      .width('100%')
    }
  }
}
