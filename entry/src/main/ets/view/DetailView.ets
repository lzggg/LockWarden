/**
 * 条目详情（仿 Bitwarden Android 详情页）：
 *   顶栏返回 → 类型头像/名称 → 操作条（收藏 / 编辑 / 删除）
 *   → 按类型展示字段卡片（登录/卡片/身份） → 自定义字段 → 历史密码 → 备注
 *
 * 复制能力由外部注入（onCopy），因此本页不依赖 pasteboard，预览器可直接渲染。
 */
import { Theme, CipherMeta } from '../common/Theme';
import { VaultItem, CipherType, VaultField } from '../common/Models';
import { Icons, typeColor, typeSymbol } from '../common/Icons';
import { generateTotpSync, secondsRemaining } from '../common/Totp';
import { EyeToggle } from './EyeToggle';
import { BrandAvatar, logoRawOf, isLogoField } from './LogoBits';
import { CopyButton } from './CopyButton';

/**
 * 字段卡片。
 *
 * 独立组件而非 @Builder：遮罩状态（revealed）通过 @Prop 传入才能触发重绘，
 * 否则点击"眼睛"后密码不会变成明文。
 */
@Component
struct FieldCard {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop masked: boolean = false;
  @Prop revealed: boolean = false;
  @Prop showCopy: boolean = true;
  onCopyTap: () => void = () => {
  };
  onToggleReveal: () => void = () => {
  };

  build() {
    Column({ space: 6 }) {
      Text(this.label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
      Row({ space: 10 }) {
        Text(this.masked && !this.revealed ? '••••••••••' : (this.value.length > 0 ? this.value : '—'))
          .fontSize(Theme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY)
          .layoutWeight(1)
          .copyOption(CopyOptions.LocalDevice)
        if (this.masked) {
          EyeToggle({
            revealed: this.revealed,
            onToggle: () => this.onToggleReveal()
          })
        }
        if (this.showCopy && this.value.length > 0) {
          CopyButton({ onTap: () => this.onCopyTap() })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.CARD)
    .margin({ bottom: 10 })
  }
}

/**
 * 操作条按钮（收藏 / 编辑 / 删除）。
 * 必须是组件：@Builder 的按值参数不会刷新，收藏状态切换后文字会停留在旧值。
 */
@Component
struct ActionButton {
  @Prop icon: Resource = Icons.star;
  @Prop label: string = '';
  @Prop danger: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Column({ space: 4 }) {
      SymbolGlyph(this.icon)
        .fontSize(20)
        .fontColor([this.danger ? Theme.DANGER : Theme.PRIMARY])
      Text(this.label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.danger ? Theme.DANGER : Theme.TEXT_SECONDARY)
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .onClick(() => this.onTap())
  }
}

/**
 * 普通信息卡片（卡片/身份/自定义字段）。
 * 同样必须是组件，编辑保存后才能显示新值。
 */
@Component
struct InfoCard {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop copyLabel: string = '';
  onCopyTap: (label: string, value: string) => void = () => {
  };

  build() {
    Column({ space: 6 }) {
      Text(this.label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_HINT)
        .width('100%')
      Row({ space: 10 }) {
        Text(this.value.length > 0 ? this.value : '—')
          .fontSize(Theme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY)
          .layoutWeight(1)
          .copyOption(CopyOptions.LocalDevice)
        if (this.value.length > 0) {
          CopyButton({ onTap: () => this.onCopyTap(this.copyLabel, this.value) })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.CARD)
    .margin({ bottom: 10 })
  }
}

@Component
export struct DetailView {
  @Prop item: VaultItem = {
    id: '',
    type: 1,
    name: '',
    username: '',
    password: '',
    totp: '',
    uri: '',
    notes: '',
    favorite: false,
    folderId: '',
    revisionDate: '',
    broken: false
  };
  @Prop folderName: string = '';
  /** 左上角返回按钮旁的来源名称 */
  @Prop backLabel: string = '保险库';

  /** 过滤掉保留的 logo 字段 */
  private visibleFields(): VaultField[] {
    const result: VaultField[] = [];
    const list = this.item.fields;
    if (list === null || list === undefined) {
      return result;
    }
    for (let i = 0; i < list.length; i++) {
      if (!isLogoField(list[i])) {
        result.push(list[i]);
      }
    }
    return result;
  }
  private isFieldRevealed(index: number): boolean {
    return index < this.fieldReveal.length ? this.fieldReveal[index] : false;
  }

  private toggleFieldReveal(index: number): void {
    const next: boolean[] = this.fieldReveal.slice(0);
    while (next.length <= index) {
      next.push(false);
    }
    next[index] = !next[index];
    this.fieldReveal = next;
  }
  onClose: () => void = () => {
  };
  onCopy: (label: string, value: string) => void = () => {
  };
  onEdit: () => void = () => {
  };
  onToggleFavorite: () => void = () => {
  };
  onDelete: () => void = () => {
  };

  @State revealPassword: boolean = false;
  /** 自定义隐藏字段的明文显示状态（按序号） */
  @State fieldReveal: boolean[] = [];
  @State totpCode: string = '';
  @State totpRemain: number = 0;
  @State totpError: string = '';
  @State showHistory: boolean = false;
  private timer: number = -1;
  private swipeStartX: number = 0;

  aboutToAppear(): void {
    this.refreshTotp();
    this.timer = setInterval(() => {
      this.tickTotp();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private refreshTotp(): void {
    if (this.item.totp.length === 0) {
      return;
    }
    try {
      this.totpCode = generateTotpSync(this.item.totp, 6, 30);
      this.totpRemain = secondsRemaining(30);
      this.totpError = '';
    } catch (e) {
      this.totpError = 'TOTP 密钥无法解析';
    }
  }

  private tickTotp(): void {
    if (this.item.totp.length === 0) {
      return;
    }
    this.totpRemain = secondsRemaining(30);
    if (this.totpRemain === 30) {
      this.refreshTotp();
    }
  }

  private copy(label: string, value: string): void {
    if (value.length === 0) {
      return;
    }
    this.onCopy(label, value);
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Row({ space: 4 }) {
          SymbolGlyph(Icons.chevron)
            .fontSize(16)
            .fontColor([Theme.PRIMARY])
            .rotate({ angle: 180 })
          Text(this.backLabel)
            .fontSize(Theme.FONT_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.PRIMARY)
        }
        .onClick(() => this.onClose())

        Blank()
        if (this.item.favorite) {
          SymbolGlyph(Icons.starFill)
            .fontSize(18)
            .fontColor(['#FFB300'])
        }
      }
      .width('100%')
      .height(48)

      Scroll() {
        Column() {
          // 头部
          Row({ space: 14 }) {
            BrandAvatar({
              raw: logoRawOf(this.item.fields),
              name: this.item.name,
              fallbackIcon: typeSymbol(this.item.type),
              fallbackColor: typeColor(this.item.type),
              diameter: 56
            })

            Column({ space: 4 }) {
              Text(this.item.name)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TEXT_PRIMARY)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(this.folderName.length > 0 ?
                `${CipherMeta.label(this.item.type)} · ${this.folderName}` :
                CipherMeta.label(this.item.type))
                .fontSize(12)
                .fontColor(Theme.TEXT_HINT)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .margin({ top: 4, bottom: 14 })

          // 操作条
          Row() {
            ActionButton({
              icon: this.item.favorite ? Icons.starFill : Icons.star,
              label: this.item.favorite ? '取消收藏' : '收藏',
              danger: false,
              onTap: () => this.onToggleFavorite()
            })
            ActionButton({
              icon: Icons.edit,
              label: '编辑',
              danger: false,
              onTap: () => this.onEdit()
            })
            ActionButton({
              icon: Icons.trash,
              label: '删除',
              danger: true,
              onTap: () => this.onDelete()
            })
          }
          .width('100%')
          .padding({ top: 2, bottom: 2 })
          .borderRadius(Theme.RADIUS)
          .backgroundColor(Theme.CARD)
          .margin({ bottom: 14 })

          if (this.item.broken) {
            Text('这个条目无法用当前账号密钥解密（可能来自组织共享，或密钥已轮换）')
              .fontSize(Theme.FONT_CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.DANGER)
              .padding(12)
              .width('100%')
              .borderRadius(Theme.RADIUS_SMALL)
              .backgroundColor('#FDECEA')
              .margin({ bottom: 12 })
          }

          // 登录
          if (this.item.type === CipherType.Login) {
            FieldCard({
              label: '用户名',
              value: this.item.username,
              masked: false,
              revealed: true,
              showCopy: true,
              onCopyTap: () => this.copy('用户名', this.item.username)
            })
            FieldCard({
              label: '密码',
              value: this.item.password,
              masked: true,
              revealed: this.revealPassword,
              showCopy: true,
              onCopyTap: () => this.copy('密码', this.item.password),
              onToggleReveal: () => {
                this.revealPassword = !this.revealPassword;
              }
            })
            // 没有网址就不显示这块（避免出现一条空的「—」）
            if (this.item.uri.length > 0) {
              FieldCard({
                label: '网址',
                value: this.item.uri,
                masked: false,
                revealed: true,
                showCopy: true,
                onCopyTap: () => this.copy('网址', this.item.uri)
              })
            }

            if (this.item.totp.length > 0) {
              Column({ space: 8 }) {
                Row() {
                  Text('验证器密钥')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.TEXT_HINT)
                    .layoutWeight(1)
                  CopyButton({ onTap: () => this.copy('验证码', this.totpCode) })
                }
                .width('100%')

                Text(this.totpError.length > 0 ? this.totpError :
                  (this.totpCode.length > 0 ? this.totpCode : '计算中…'))
                  .fontSize(28)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.totpError.length > 0 ? Theme.DANGER : Theme.PRIMARY)
                  .letterSpacing(6)

                Progress({ value: 30 - this.totpRemain, total: 30, type: ProgressType.Linear })
                  .width('100%')
                  .height(3)
                  .color(Theme.PRIMARY)
                Text(`${this.totpRemain} 秒后刷新`)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.TEXT_HINT)
                  .width('100%')
                  .textAlign(TextAlign.End)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(14)
              .borderRadius(Theme.RADIUS)
              .backgroundColor(Theme.CARD)
              .margin({ bottom: 10 })
            }
          }

          // 卡片
          if (this.item.type === CipherType.Card && this.item.card !== null &&
            this.item.card !== undefined) {
            InfoCard({
              label: '持卡人', value: this.item.card.cardholderName, copyLabel: '持卡人',
              onCopyTap: (l: string, v: string) => this.copy(l, v)
            })
            InfoCard({
              label: '卡号', value: this.item.card.number, copyLabel: '卡号',
              onCopyTap: (l: string, v: string) => this.copy(l, v)
            })
            InfoCard({
              label: '品牌', value: this.item.card.brand, copyLabel: '品牌',
              onCopyTap: (l: string, v: string) => this.copy(l, v)
            })
            InfoCard({
              label: '有效期',
              value: this.item.card.expMonth.length > 0 ?
                `${this.item.card.expMonth}/${this.item.card.expYear}` : '',
              copyLabel: '有效期',
              onCopyTap: (l: string, v: string) => this.copy(l, v)
            })
            InfoCard({
              label: '安全码', value: this.item.card.code, copyLabel: '安全码',
              onCopyTap: (l: string, v: string) => this.copy(l, v)
            })
          }

          // 身份
          if (this.item.type === CipherType.Identity && this.item.identity !== null &&
            this.item.identity !== undefined) {
            InfoCard({
              label: '姓名',
              value: `${this.item.identity.lastName}${this.item.identity.firstName}`,
              copyLabel: '姓名',
              onCopyTap: (l: string, v: string) => this.copy(l, v)
            })
            InfoCard({
              label: '称谓', value: this.item.identity.title, copyLabel: '称谓',
              onCopyTap: (l: string, v: string) => this.copy(l, v)
            })
            InfoCard({
              label: '邮箱', value: this.item.identity.email, copyLabel: '邮箱',
              onCopyTap: (l: string, v: string) => this.copy(l, v)
            })
            InfoCard({
              label: '电话', value: this.item.identity.phone, copyLabel: '电话',
              onCopyTap: (l: string, v: string) => this.copy(l, v)
            })
            InfoCard({
              label: '地址', value: this.item.identity.address, copyLabel: '地址',
              onCopyTap: (l: string, v: string) => this.copy(l, v)
            })
            InfoCard({
              label: '城市', value: this.item.identity.city, copyLabel: '城市',
              onCopyTap: (l: string, v: string) => this.copy(l, v)
            })
            InfoCard({
              label: '邮编', value: this.item.identity.postalCode, copyLabel: '邮编',
              onCopyTap: (l: string, v: string) => this.copy(l, v)
            })
            InfoCard({
              label: '国家/地区', value: this.item.identity.country, copyLabel: '国家/地区',
              onCopyTap: (l: string, v: string) => this.copy(l, v)
            })
          }

          // 自定义字段
          if (this.visibleFields().length > 0) {
            Text('自定义字段')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_HINT)
              .width('100%')
              .margin({ bottom: 6 })
            ForEach(this.visibleFields(), (field: VaultField, index: number) => {
              if (field.type === 1) {
                // 和密码一样隐藏：默认打点，眼睛图标切换明文
                FieldCard({
                  label: field.name.length > 0 ? field.name : '（未命名字段）',
                  value: field.value,
                  masked: true,
                  revealed: this.isFieldRevealed(index),
                  showCopy: true,
                  onCopyTap: () => this.copy(field.name, field.value),
                  onToggleReveal: () => this.toggleFieldReveal(index)
                })
              } else {
                InfoCard({
                  label: field.name.length > 0 ? field.name : '（未命名字段）',
                  value: field.value,
                  copyLabel: field.name,
                  onCopyTap: (l: string, v: string) => this.copy(l, v)
                })
              }
            }, (field: VaultField, index: number) => `${index}-${field.name}-${field.type}`)
          }

          // 历史密码
          if (this.item.history !== null && this.item.history !== undefined &&
            this.item.history.length > 0) {
            Column() {
              Row() {
                Text('历史密码')
                  .fontSize(Theme.FONT_BODY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.TEXT_PRIMARY)
                  .layoutWeight(1)
                Text(this.showHistory ? '收起' : `${this.item.history.length} 条`)
                  .fontSize(Theme.FONT_CAPTION)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.PRIMARY)
              }
              .width('100%')
              .onClick(() => {
                this.showHistory = !this.showHistory;
              })

              if (this.showHistory) {
                ForEach(this.item.history, (old: string, index: number) => {
                  Row() {
                    Text(old)
                      .fontSize(Theme.FONT_CAPTION)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.TEXT_SECONDARY)
                      .layoutWeight(1)
                      .copyOption(CopyOptions.LocalDevice)
                    Row() {
                      SymbolGlyph(Icons.copy)
                        .fontSize(14)
                        .fontColor([Theme.PRIMARY])
                    }
                    .width(28)
                    .height(28)
                    .justifyContent(FlexAlign.Center)
                    .onClick(() => this.copy('旧密码', old))
                  }
                  .width('100%')
                  .padding({ top: 8, bottom: 8 })
                }, (old: string, index: number) => `${index}-${old}`)
              }
            }
            .width('100%')
            .padding(14)
            .borderRadius(Theme.RADIUS)
            .backgroundColor(Theme.CARD)
            .margin({ bottom: 10 })
          }

          if (this.item.notes.length > 0) {
            Column({ space: 6 }) {
              Text('备注')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TEXT_HINT)
                .width('100%')
              // 复制按钮与内容同排、垂直居中，尺寸和其它字段一致（34×34）
              Row({ space: 10 }) {
                Text(this.item.notes)
                  .fontSize(Theme.FONT_BODY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.TEXT_PRIMARY)
                  .layoutWeight(1)
                  .copyOption(CopyOptions.LocalDevice)
                CopyButton({ onTap: () => this.copy('备注', this.item.notes) })
                  .alignSelf(ItemAlign.Center)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .padding(14)
            .borderRadius(Theme.RADIUS)
            .backgroundColor(Theme.CARD)
            .margin({ bottom: 10 })
          }


        }
        .width('100%')
        .padding({ bottom: 28 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: Theme.PAGE_PADDING, right: Theme.PAGE_PADDING })
    .backgroundColor(Theme.BACKGROUND)
    // 左缘向内滑 → 返回列表（不依赖系统返回手势是否被侧边栏占用）
    .parallelGesture(
      PanGesture({ direction: PanDirection.Right, distance: 30 })
        .onActionStart((event: GestureEvent) => {
          this.swipeStartX = event.fingerList.length > 0 ? event.fingerList[0].localX : 999;
        })
        .onActionEnd((event: GestureEvent) => {
          if (event.offsetX > 120) {
            this.onClose();
          }
        })
    )
  }
}
