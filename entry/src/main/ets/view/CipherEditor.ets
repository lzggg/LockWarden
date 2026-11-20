/**
 * 条目编辑器：新建与编辑合一，支持 Bitwarden 的四种条目类型
 * （登录 / 卡片 / 身份 / 安全笔记），并支持文件夹归属、收藏、自定义字段。
 *
 * 与存储层之间只交换明文 CipherDraft，加密在 VaultStore 内完成。
 */
import { Theme } from '../common/Theme';
import { Responsive } from '../common/Responsive';
import { Icons, typeSymbol } from '../common/Icons';
import {
  CipherDraft, CipherType, VaultField, VaultFolder, VaultCard, VaultIdentity, emptyDraft
} from '../common/Models';
import { PasswordGeneratorPanel } from './PasswordGeneratorPanel';
import { EyeToggle } from './EyeToggle';
import { EditorBridge } from '../common/EditorBridge';
import { mediaquery } from '@kit.ArkUI';
import { BrandAvatar, LogoPickerDialog, logoRawOf, isLogoField } from './LogoBits';
import { LOGO_FIELD_NAME, matchBrand, logoPresetValue } from '../common/BrandLogos';

/** 带标签的单行输入；@Prop 保证外部改值（如生成密码）能刷新 */
@Component
struct TextField {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop placeholder: string = '';
  /** 0=普通 1=网址 2=数字 */
  @Prop kind: number = 0;
  onValue: (value: string) => void = () => {
  };

  build() {
    Column({ space: 6 }) {
      Text(this.label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
      TextInput({ text: this.value, placeholder: this.placeholder })
        .fontColor(Theme.TEXT_PRIMARY)
        .placeholderColor(Theme.TEXT_HINT)
        .type(this.kind === 1 ? InputType.URL : (this.kind === 2 ? InputType.Number : InputType.Normal))
        .height(46)
        .borderRadius(Theme.RADIUS_SMALL)
        .backgroundColor(Theme.CARD)
        .fontSize(Theme.FONT_BODY)
        .onChange((v: string) => this.onValue(v))
    }
    .width('100%')
  }
}

@Component
export struct CipherEditor {
  @Prop initial: CipherDraft = emptyDraft(1);
  @Prop folders: VaultFolder[] = [];
  random: (bound: number) => number = (bound: number) => Math.floor(Math.random() * bound);
  onClose: () => void = () => {
  };
  onSave: (draft: CipherDraft) => Promise<void> = async () => {
  };
  /** 新建文件夹：返回新文件夹 id，失败抛错 */
  onCreateFolder: (name: string) => Promise<string> = async () => '';

  @State type: number = 1;
  @State name: string = '';
  @State favorite: boolean = false;
  @State folderId: string = '';
  @State notes: string = '';
  // 登录
  @State username: string = '';
  @State password: string = '';
  @State totp: string = '';
  @State uri: string = '';
  // 卡片
  @State cardholder: string = '';
  @State brand: string = '';
  @State cardNumber: string = '';
  @State expMonth: string = '';
  @State expYear: string = '';
  @State cardCode: string = '';
  // 身份
  @State idTitle: string = '';
  @State firstName: string = '';
  @State lastName: string = '';
  @State idEmail: string = '';
  @State idPhone: string = '';
  @State address: string = '';
  @State city: string = '';
  @State postalCode: string = '';
  @State country: string = '';
  // 自定义字段
  @State fields: VaultField[] = [];
  /** 与 fields 一一对应：隐藏字段是否临时显示明文 */
  @State fieldReveal: boolean[] = [];

  /** 宽屏时类型切换条靠左，手机上沿用居中的观感 */
  @State wide: boolean = false;
  private wideListener: mediaquery.MediaQueryListener | null = null;

  // Logo
  @State logoRaw: string = '';
  private logoManual: boolean = false;
  private logoPicker: CustomDialogController = new CustomDialogController({
    builder: LogoPickerDialog({
      onPick: (raw: string) => {
        this.logoRaw = raw;
        this.logoManual = true;
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  });

  @State showPassword: boolean = false;
  @State showGenerator: boolean = false;
  @State busy: boolean = false;
  @State error: string = '';
  // 新建文件夹
  @State showFolderInput: boolean = false;
  @State newFolderName: string = '';
  @State folderBusy: boolean = false;
  private swipeStartX: number = 0;

  aboutToAppear(): void {
    this.wide = Responsive.isWideNow();
    // 横竖屏切换时自动重排编辑区
    this.wideListener = Responsive.watchWide(this.getUIContext(), (wide: boolean) => {
      this.wide = wide;
    });
    const d: CipherDraft = this.initial;
    this.type = d.type;
    this.name = d.name;
    this.favorite = d.favorite;
    this.folderId = d.folderId;
    this.notes = d.notes;
    this.username = d.username;
    this.password = d.password;
    this.totp = d.totp;
    this.uri = d.uri;
    this.cardholder = d.card.cardholderName;
    this.brand = d.card.brand;
    this.cardNumber = d.card.number;
    this.expMonth = d.card.expMonth;
    this.expYear = d.card.expYear;
    this.cardCode = d.card.code;
    this.idTitle = d.identity.title;
    this.firstName = d.identity.firstName;
    this.lastName = d.identity.lastName;
    this.idEmail = d.identity.email;
    this.idPhone = d.identity.phone;
    this.address = d.identity.address;
    this.city = d.identity.city;
    this.postalCode = d.identity.postalCode;
    this.country = d.identity.country;
    this.logoRaw = logoRawOf(d.fields);
    const visibleFields: VaultField[] = [];
    for (let i = 0; i < d.fields.length; i++) {
      if (!isLogoField(d.fields[i])) {
        visibleFields.push(d.fields[i]);
      }
    }
    this.fields = visibleFields;
    // 让外壳（返回键/侧滑）能走"未保存确认"
    EditorBridge.requestClose = () => this.tryClose();
  }

  aboutToDisappear(): void {
    if (this.wideListener !== null) {
      this.wideListener.off('change');
      this.wideListener = null;
    }
    EditorBridge.requestClose = null;
  }

  /** 与打开时相比是否有未保存的改动 */
  private isDirty(): boolean {
    const d: CipherDraft = this.initial;
    if (this.type !== d.type || this.name !== d.name || this.notes !== d.notes ||
      this.favorite !== d.favorite || this.folderId !== d.folderId) {
      return true;
    }
    if (this.username !== d.username || this.password !== d.password ||
      this.totp !== d.totp || this.uri !== d.uri) {
      return true;
    }
    const c: VaultCard = d.card;
    if (this.cardholder !== c.cardholderName || this.brand !== c.brand ||
      this.cardNumber !== c.number || this.expMonth !== c.expMonth ||
      this.expYear !== c.expYear || this.cardCode !== c.code) {
      return true;
    }
    const i: VaultIdentity = d.identity;
    if (this.idTitle !== i.title || this.firstName !== i.firstName ||
      this.lastName !== i.lastName || this.idEmail !== i.email ||
      this.idPhone !== i.phone || this.address !== i.address ||
      this.city !== i.city || this.postalCode !== i.postalCode ||
      this.country !== i.country) {
      return true;
    }
    if (this.fields.length !== d.fields.length) {
      return true;
    }
    for (let k = 0; k < this.fields.length; k++) {
      if (this.fields[k].name !== d.fields[k].name || this.fields[k].value !== d.fields[k].value) {
        return true;
      }
    }
    return false;
  }

  /** 关闭前确认：没改动直接关；有改动先问一句，避免误退丢数据 */
  private tryClose(): void {
    // 有弹出层就先把弹出层收掉，再退编辑器
    if (this.showGenerator) {
      this.showGenerator = false;
      return;
    }
    if (this.showFolderInput) {
      this.showFolderInput = false;
      return;
    }
    if (!this.isDirty()) {
      this.onClose();
      return;
    }
    AlertDialog.show({
      title: '放弃更改？',
      message: '这个条目还没有保存，返回会丢失刚才的修改。',
      autoCancel: true,
      primaryButton: {
        value: '继续编辑',
        action: () => {
        }
      },
      secondaryButton: {
        value: '放弃',
        fontColor: Theme.DANGER,
        action: () => this.onClose()
      }
    });
  }

  private isEditing(): boolean {
    return this.initial.id.length > 0;
  }

  private title(): string {
    const verb: string = this.isEditing() ? '编辑' : '新建';
    if (this.type === CipherType.Card) {
      return `${verb}卡片`;
    }
    if (this.type === CipherType.Identity) {
      return `${verb}身份`;
    }
    if (this.type === CipherType.SecureNote) {
      return `${verb}笔记`;
    }
    return `${verb}登录`;
  }

  private buildDraft(): CipherDraft {
    const card: VaultCard = {
      cardholderName: this.cardholder,
      brand: this.brand,
      number: this.cardNumber,
      expMonth: this.expMonth,
      expYear: this.expYear,
      code: this.cardCode
    };
    const identity: VaultIdentity = {
      title: this.idTitle,
      firstName: this.firstName,
      lastName: this.lastName,
      email: this.idEmail,
      phone: this.idPhone,
      address: this.address,
      city: this.city,
      postalCode: this.postalCode,
      country: this.country
    };
    const draft: CipherDraft = {
      id: this.initial.id,
      type: this.type,
      name: this.name,
      username: this.username,
      password: this.password,
      totp: this.totp,
      uri: this.uri,
      notes: this.notes,
      favorite: this.favorite,
      folderId: this.folderId,
      card: card,
      identity: identity,
      fields: this.withLogoField()
    };
    return draft;
  }

  private async save(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      await this.onSave(this.buildDraft());
      this.getUIContext().getPromptAction().showToast({
        message: this.isEditing() ? '已保存修改' : '已加入保险库',
        duration: 1500
      });
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.busy = false;
    }
  }

  /** 在编辑器里直接新建文件夹，建好即选中 */
  private async createFolderNow(): Promise<void> {
    const name: string = this.newFolderName.trim();
    if (name.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入文件夹名称', duration: 1500 });
      return;
    }
    if (this.folderBusy) {
      return;
    }
    this.folderBusy = true;
    try {
      const id: string = await this.onCreateFolder(name);
      if (id.length > 0) {
        this.folderId = id;
      }
      this.newFolderName = '';
      this.showFolderInput = false;
      this.getUIContext().getPromptAction().showToast({
        message: `已创建「${name}」并选中`,
        duration: 1800
      });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: (e as Error).message,
        duration: 2200
      });
    } finally {
      this.folderBusy = false;
    }
  }

  /** 把 logo 作为保留字段一起存进条目 */
  private withLogoField(): VaultField[] {
    const result: VaultField[] = [];
    for (let i = 0; i < this.fields.length; i++) {
      if (!isLogoField(this.fields[i])) {
        result.push(this.fields[i]);
      }
    }
    if (this.logoRaw.length > 0) {
      const logoField: VaultField = { name: LOGO_FIELD_NAME, value: this.logoRaw, type: 0 };
      result.push(logoField);
    }
    return result;
  }
  private addField(): void {
    const field: VaultField = { name: '', value: '', type: 0 };
    const next: VaultField[] = this.fields.slice(0);
    next.push(field);
    this.fields = next;
    const reveal: boolean[] = this.fieldReveal.slice(0);
    reveal.push(false);
    this.fieldReveal = reveal;
  }

  private isFieldRevealed(index: number): boolean {
    return index < this.fieldReveal.length ? this.fieldReveal[index] : false;
  }

  private toggleFieldReveal(index: number): void {
    const reveal: boolean[] = this.fieldReveal.slice(0);
    while (reveal.length <= index) {
      reveal.push(false);
    }
    reveal[index] = !reveal[index];
    this.fieldReveal = reveal;
  }

  /** 切换该字段是否"和密码一样隐藏" */
  private toggleFieldHidden(index: number): void {
    const next: VaultField[] = this.fields.slice(0);
    next[index].type = next[index].type === 1 ? 0 : 1;
    this.fields = next;
    if (next[index].type === 0) {
      const reveal: boolean[] = this.fieldReveal.slice(0);
      while (reveal.length <= index) {
        reveal.push(false);
      }
      reveal[index] = false;
      this.fieldReveal = reveal;
    }
  }

  private removeField(index: number): void {
    const next: VaultField[] = [];
    const reveal: boolean[] = [];
    for (let i = 0; i < this.fields.length; i++) {
      if (i !== index) {
        next.push(this.fields[i]);
        reveal.push(this.isFieldRevealed(i));
      }
    }
    this.fields = next;
    this.fieldReveal = reveal;
  }

  private updateFieldName(index: number, value: string): void {
    const next: VaultField[] = this.fields.slice(0);
    next[index].name = value;
    this.fields = next;
  }

  private updateFieldValue(index: number, value: string): void {
    const next: VaultField[] = this.fields.slice(0);
    next[index].value = value;
    this.fields = next;
  }

  @Builder
  typeTab(t: number, label: string) {
    Row({ space: 6 }) {
      SymbolGlyph(typeSymbol(t))
        .fontSize(16)
        .fontColor([this.type === t ? Color.White : Theme.TEXT_SECONDARY])
      Text(label)
        .fontSize(Theme.FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.type === t ? Color.White : Theme.TEXT_SECONDARY)
    }
    .padding({ left: 12, right: 14, top: 8, bottom: 8 })
    .borderRadius(18)
    .backgroundColor(this.type === t ? Theme.PRIMARY : Theme.CARD)
    .margin({ right: 8 })
    .onClick(() => {
      this.type = t;
    })
  }

  @Builder
  generatorSheet() {
    Column() {
      PasswordGeneratorPanel({
        random: (bound: number) => this.random(bound),
        actionLabel: '使用此密码',
        showClose: true,
        title: '生成密码',
        onClose: () => {
          this.showGenerator = false;
        },
        onAction: (value: string) => {
          this.password = value;
          this.showPassword = true;
          this.showGenerator = false;
        }
      })
    }
    .width('100%')
    .padding({ left: Theme.PAGE_PADDING, right: Theme.PAGE_PADDING, top: 16, bottom: 24 })
    .borderRadius({ topLeft: 20, topRight: 20 })
    .backgroundColor(Theme.BACKGROUND)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 顶栏
        Row() {
          Text('取消')
            .fontSize(Theme.FONT_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_SECONDARY)
            .onClick(() => this.tryClose())
          Blank()
          Text(this.title())
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_PRIMARY)
          Blank()
          Text(this.busy ? '保存中…' : '保存')
            .fontSize(Theme.FONT_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.busy ? Theme.TEXT_HINT : Theme.PRIMARY)
            .onClick(() => {
              this.save();
            })
        }
        .width('100%')
        .height(52)

        Scroll() {
          Column({ space: 14 }) {
            // 类型选择
            Scroll() {
              Row() {
                this.typeTab(CipherType.Login, '登录')
                this.typeTab(CipherType.Card, '卡片')
                this.typeTab(CipherType.Identity, '身份')
                this.typeTab(CipherType.SecureNote, '笔记')
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .align(this.wide ? Alignment.TopStart : Alignment.Center)
            .width('100%')

            TextField({
              label: '名称 *',
              value: this.name,
              placeholder: '例如：GitHub',
              onValue: (v: string) => {
                this.name = v;
                if (!this.logoManual) {
                  const matched: string = matchBrand(v);
                  if (matched.length > 0) {
                    this.logoRaw = logoPresetValue(matched);
                  }
                }
              }
            })

            // Logo：自动匹配 + 手动选择
            Row({ space: 10 }) {
              BrandAvatar({
                raw: this.logoRaw,
                name: this.name,
                fallbackIcon: typeSymbol(this.type),
                fallbackColor: Theme.PRIMARY,
                diameter: 38
              })
              Column({ space: 2 }) {
                Text(this.logoRaw.length > 0 ? '已匹配 Logo' : 'Logo（可选）')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.TEXT_HINT)
                Text(this.logoRaw.length > 0 ?
                  (this.logoManual ? '手动选择' : '根据名称自动匹配') : '输入名称可自动匹配，如 Google / 微信')
                  .fontSize(11)
                  .fontColor(Theme.TEXT_HINT)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Text('选择')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.PRIMARY)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor(Theme.TINT)
                .borderRadius(14)
                .onClick(() => this.logoPicker.open())
            }
            .width('100%')
            .padding(10)
            .borderRadius(Theme.RADIUS_SMALL)
            .backgroundColor(Theme.BACKGROUND)

            if (this.type === CipherType.Login) {
              TextField({
                label: '用户名',
                value: this.username,
                placeholder: '账号或邮箱',
                onValue: (v: string) => {
                  this.username = v;
                }
              })

              // 密码：输入 + 明码切换 + 生成器
              Column({ space: 6 }) {
                Text('密码')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.TEXT_HINT)
                  .width('100%')
                Row({ space: 2 }) {
                  TextInput({ text: this.password, placeholder: '密码，或点右侧魔棒生成' })
                    .fontColor(Theme.TEXT_PRIMARY)
                    .placeholderColor(Theme.TEXT_HINT)
                    .type(this.showPassword ? InputType.Normal : InputType.Password)
                    .showPasswordIcon(false)
                    .height(46)
                    .layoutWeight(1)
                    .backgroundColor(Color.Transparent)
                    .fontSize(Theme.FONT_BODY)
                    .onChange((v: string) => {
                      this.password = v;
                    })
                  EyeToggle({
                    revealed: this.showPassword,
                    onToggle: () => {
                      this.showPassword = !this.showPassword;
                    }
                  })
                  Row() {
                    SymbolGlyph(Icons.generator)
                      .fontSize(20)
                      .fontColor([Theme.PRIMARY])
                  }
                  .width(34)
                  .height(34)
                  .borderRadius(17)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(Theme.TINT)
                  .margin({ right: 4 })
                  .onClick(() => {
                    this.showGenerator = true;
                  })
                }
                .width('100%')
                .height(46)
                .borderRadius(Theme.RADIUS_SMALL)
                .backgroundColor(Theme.CARD)
              }
              .width('100%')

              TextField({
                label: '验证器密钥（otpauth:// 或 Base32）',
                value: this.totp,
                placeholder: '可选',
                onValue: (v: string) => {
                  this.totp = v;
                }
              })

              TextField({
                label: '网址',
                value: this.uri,
                placeholder: 'https://example.com',
                kind: 1,
                onValue: (v: string) => {
                  this.uri = v;
                }
              })
            } else if (this.type === CipherType.Card) {
              TextField({
                label: '持卡人',
                value: this.cardholder,
                placeholder: '姓名',
                onValue: (v: string) => {
                  this.cardholder = v;
                }
              })
              TextField({
                label: '卡号',
                value: this.cardNumber,
                placeholder: '卡号',
                kind: 2,
                onValue: (v: string) => {
                  this.cardNumber = v;
                }
              })
              Row({ space: 10 }) {
                Column() {
                  TextField({
                    label: '品牌',
                    value: this.brand,
                    placeholder: 'Visa / 银联',
                    onValue: (v: string) => {
                      this.brand = v;
                    }
                  })
                }
                .layoutWeight(1)
                Column() {
                  TextField({
                    label: '安全码',
                    value: this.cardCode,
                    placeholder: 'CVV',
                    kind: 2,
                    onValue: (v: string) => {
                      this.cardCode = v;
                    }
                  })
                }
                .layoutWeight(1)
              }
              .width('100%')
              Row({ space: 10 }) {
                Column() {
                  TextField({
                    label: '有效期（月）',
                    value: this.expMonth,
                    placeholder: '09',
                    kind: 2,
                    onValue: (v: string) => {
                      this.expMonth = v;
                    }
                  })
                }
                .layoutWeight(1)
                Column() {
                  TextField({
                    label: '有效期（年）',
                    value: this.expYear,
                    placeholder: '2029',
                    kind: 2,
                    onValue: (v: string) => {
                      this.expYear = v;
                    }
                  })
                }
                .layoutWeight(1)
              }
              .width('100%')
            } else if (this.type === CipherType.Identity) {
              TextField({
                label: '称谓',
                value: this.idTitle,
                placeholder: '先生 / 女士',
                onValue: (v: string) => {
                  this.idTitle = v;
                }
              })
              Row({ space: 10 }) {
                Column() {
                  TextField({
                    label: '名',
                    value: this.firstName,
                    placeholder: '三',
                    onValue: (v: string) => {
                      this.firstName = v;
                    }
                  })
                }
                .layoutWeight(1)
                Column() {
                  TextField({
                    label: '姓',
                    value: this.lastName,
                    placeholder: '张',
                    onValue: (v: string) => {
                      this.lastName = v;
                    }
                  })
                }
                .layoutWeight(1)
              }
              .width('100%')
              TextField({
                label: '邮箱',
                value: this.idEmail,
                placeholder: 'you@example.com',
                onValue: (v: string) => {
                  this.idEmail = v;
                }
              })
              TextField({
                label: '电话',
                value: this.idPhone,
                placeholder: '手机号',
                kind: 2,
                onValue: (v: string) => {
                  this.idPhone = v;
                }
              })
              TextField({
                label: '地址',
                value: this.address,
                placeholder: '街道地址',
                onValue: (v: string) => {
                  this.address = v;
                }
              })
              Row({ space: 10 }) {
                Column() {
                  TextField({
                    label: '城市',
                    value: this.city,
                    placeholder: '城市',
                    onValue: (v: string) => {
                      this.city = v;
                    }
                  })
                }
                .layoutWeight(1)
                Column() {
                  TextField({
                    label: '邮编',
                    value: this.postalCode,
                    placeholder: '邮编',
                    onValue: (v: string) => {
                      this.postalCode = v;
                    }
                  })
                }
                .layoutWeight(1)
              }
              .width('100%')
              TextField({
                label: '国家/地区',
                value: this.country,
                placeholder: '中国',
                onValue: (v: string) => {
                  this.country = v;
                }
              })
            }

            // 文件夹（可选已有，也可当场新建）
            Column({ space: 10 }) {
              Row() {
                Text('文件夹')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.TEXT_HINT)
                  .layoutWeight(1)
                Row({ space: 4 }) {
                  SymbolGlyph(Icons.add)
                    .fontSize(14)
                    .fontColor([Theme.PRIMARY])
                  Text(this.showFolderInput ? '收起' : '新建文件夹')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.PRIMARY)
                }
                .onClick(() => {
                  this.showFolderInput = !this.showFolderInput;
                })
              }
              .width('100%')

              if (this.showFolderInput) {
                Row({ space: 8 }) {
                  TextInput({ text: this.newFolderName, placeholder: '输入文件夹名称' })
                    .fontColor(Theme.TEXT_PRIMARY)
                    .placeholderColor(Theme.TEXT_HINT)
                    .height(42)
                    .layoutWeight(1)
                    .borderRadius(Theme.RADIUS_SMALL)
                    .backgroundColor(Theme.CARD)
                    .fontSize(Theme.FONT_CAPTION)
                    .onChange((v: string) => {
                      this.newFolderName = v;
                    })
                    .onSubmit(() => {
                      this.createFolderNow();
                    })
                  Button(this.folderBusy ? '创建中…' : '确定')
                    .height(42)
                    .borderRadius(Theme.RADIUS_SMALL)
                    .backgroundColor(this.folderBusy ? '#8FB4FB' : Theme.PRIMARY)
                    .fontColor(Color.White)
                    .fontSize(Theme.FONT_CAPTION)
                    .enabled(!this.folderBusy)
                    .onClick(() => {
                      this.createFolderNow();
                    })
                }
                .width('100%')
              }

              Scroll() {
                Row() {
                  Row() {
                    Text('无文件夹')
                      .fontSize(Theme.FONT_CAPTION)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.folderId.length === 0 ? Color.White : Theme.TEXT_SECONDARY)
                  }
                  .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                  .borderRadius(16)
                  .backgroundColor(this.folderId.length === 0 ? Theme.PRIMARY : Theme.CARD)
                  .margin({ right: 8 })
                  .onClick(() => {
                    this.folderId = '';
                  })

                  ForEach(this.folders, (folder: VaultFolder) => {
                    Row() {
                      Text(folder.name)
                        .fontSize(Theme.FONT_CAPTION)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.folderId === folder.id ? Color.White : Theme.TEXT_SECONDARY)
                    }
                    .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                    .borderRadius(16)
                    .backgroundColor(this.folderId === folder.id ? Theme.PRIMARY : Theme.CARD)
                    .margin({ right: 8 })
                    .onClick(() => {
                      this.folderId = folder.id;
                    })
                  }, (folder: VaultFolder) => `${folder.id}:${folder.name}`)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
            }
            .width('100%')

            // 收藏
            Row() {
              SymbolGlyph(this.favorite ? Icons.starFill : Icons.star)
                .fontSize(18)
                .fontColor([this.favorite ? '#FFB300' : Theme.TEXT_HINT])
              Text('收藏')
                .fontSize(Theme.FONT_BODY)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TEXT_PRIMARY)
                .margin({ left: 10 })
              Blank()
            }
            .width('100%')
            .padding(14)
            .borderRadius(Theme.RADIUS)
            .backgroundColor(Theme.CARD)
            .onClick(() => {
              this.favorite = !this.favorite;
            })

            // 备注
            Column({ space: 6 }) {
              Text('备注')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TEXT_HINT)
                .width('100%')
              TextArea({ text: this.notes, placeholder: '可选' })
                .fontColor(Theme.TEXT_PRIMARY)
                .placeholderColor(Theme.TEXT_HINT)
                .height(88)
                .borderRadius(Theme.RADIUS_SMALL)
                .backgroundColor(Theme.CARD)
                .onChange((v: string) => {
                  this.notes = v;
                })
            }
            .width('100%')

            // 自定义字段
            Column({ space: 8 }) {
              Row() {
                Text('自定义字段')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.TEXT_HINT)
                  .layoutWeight(1)
                Row({ space: 4 }) {
                  SymbolGlyph(Icons.add)
                    .fontSize(14)
                    .fontColor([Theme.PRIMARY])
                  Text('添加')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.PRIMARY)
                }
                .onClick(() => this.addField())
              }
              .width('100%')

              ForEach(this.fields, (field: VaultField, index: number) => {
                Column({ space: 8 }) {
                  Row({ space: 8 }) {
                    TextInput({ text: field.name, placeholder: '字段名' })
                      .fontColor(Theme.TEXT_PRIMARY)
                      .placeholderColor(Theme.TEXT_HINT)
                      .height(42)
                      .layoutWeight(1)
                      .borderRadius(Theme.RADIUS_SMALL)
                      .backgroundColor(Theme.CARD)
                      .fontSize(14)
                      .onChange((v: string) => this.updateFieldName(index, v))
                    Row() {
                      SymbolGlyph(Icons.trash)
                        .fontSize(16)
                        .fontColor([Theme.DANGER])
                    }
                    .width(32)
                    .height(32)
                    .justifyContent(FlexAlign.Center)
                    .onClick(() => this.removeField(index))
                  }
                  .width('100%')

                  Row({ space: 8 }) {
                    TextInput({ text: field.value, placeholder: '值' })
                      .fontColor(Theme.TEXT_PRIMARY)
                      .placeholderColor(Theme.TEXT_HINT)
                      .type(field.type === 1 && !this.isFieldRevealed(index) ?
                        InputType.Password : InputType.Normal)
                      .showPasswordIcon(false)
                      .height(42)
                      .layoutWeight(1)
                      .borderRadius(Theme.RADIUS_SMALL)
                      .backgroundColor(Theme.CARD)
                      .fontSize(14)
                      .onChange((v: string) => this.updateFieldValue(index, v))
                    if (field.type === 1) {
                      EyeToggle({
                        revealed: this.isFieldRevealed(index),
                        onToggle: () => this.toggleFieldReveal(index)
                      })
                    }
                    // 是否像密码一样隐藏
                    Text(field.type === 1 ? '已隐藏' : '隐藏')
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(field.type === 1 ? Color.White : Theme.TEXT_SECONDARY)
                      .backgroundColor(field.type === 1 ? Theme.PRIMARY : Theme.BACKGROUND)
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .borderRadius(12)
                      .onClick(() => this.toggleFieldHidden(index))
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(8)
                .borderRadius(Theme.RADIUS_SMALL)
                .backgroundColor(Theme.BACKGROUND)
              }, (field: VaultField, index: number) => `${index}-${field.name}-${field.type}`)
            }
            .width('100%')
            .padding(14)
            .borderRadius(Theme.RADIUS)
            .backgroundColor(Theme.BACKGROUND)

            if (this.error.length > 0) {
              Text(this.error)
                .fontSize(Theme.FONT_CAPTION)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.DANGER)
                .width('100%')
            }

            Text('字段在离开本机前就用账号密钥加密，服务器只保存密文')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_HINT)
              .width('100%')
          }
          .width('100%')
          .padding({ top: 4, bottom: 32 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .padding({ left: Theme.PAGE_PADDING, right: Theme.PAGE_PADDING })
      .backgroundColor(Theme.BACKGROUND)

      if (this.showGenerator) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .onClick(() => {
            this.showGenerator = false;
          })
      }
      if (this.showGenerator) {
        this.generatorSheet()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BACKGROUND)
    // 左缘向内滑 → 关闭编辑器
    .parallelGesture(
      PanGesture({ direction: PanDirection.Right, distance: 30 })
        .onActionStart((event: GestureEvent) => {
          this.swipeStartX = event.fingerList.length > 0 ? event.fingerList[0].localX : 999;
        })
        .onActionEnd((event: GestureEvent) => {
          if (event.offsetX > 120 && !this.showGenerator) {
            this.tryClose();
          }
        })
    )
  }
}
