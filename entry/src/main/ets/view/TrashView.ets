/**
 * 回收站：软删除的条目在这里，可恢复或彻底删除（不可逆）。
 */
import { Theme, CipherMeta } from '../common/Theme';
import { Pill } from './Pill';
import { confirmDanger } from '../common/Dialog';
import { VaultItem } from '../common/Models';
import { Icons, typeColor, typeSymbol } from '../common/Icons';
import { SelectionBridge } from '../common/SelectionBridge';
import { BrandAvatar, logoRawFor } from './LogoBits';
import { SwipeActions } from './SwipeActions';

@Component
export struct TrashView {
  @Prop items: VaultItem[] = [];
  onBack: () => void = () => {
  };
  onRestore: (item: VaultItem) => void = () => {
  };
  onPurge: (item: VaultItem) => void = () => {
  };
  /** 批量恢复 / 批量彻底删除 */
  onBatchRestore: (items: VaultItem[]) => void = () => {
  };
  onBatchPurge: (items: VaultItem[]) => void = () => {
  };

  @State selecting: boolean = false;
  @State selectedIds: string[] = [];
  /** 用于操作完成后收起左滑（ListScroller 才有 closeAllSwipeActions） */
  private itemScroller: ListScroller = new ListScroller();

  private isSelected(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private enterSelect(id: string): void {
    this.selecting = true;
    // 让返回键/侧滑优先取消选择，而不是退出回收站
    SelectionBridge.cancel = () => this.exitSelect();
    if (!this.isSelected(id)) {
      this.selectedIds.push(id);
      this.selectedIds = this.selectedIds.slice(0);
    }
  }

  private toggleSelect(id: string): void {
    const at: number = this.selectedIds.indexOf(id);
    if (at >= 0) {
      this.selectedIds.splice(at, 1);
    } else {
      this.selectedIds.push(id);
    }
    this.selectedIds = this.selectedIds.slice(0);
    if (this.selectedIds.length === 0) {
      this.exitSelect();
    }
  }

  /** 全选（取消选择统一用「取消」按钮） */
  private selectAll(): void {
    const ids: string[] = [];
    for (let i = 0; i < this.items.length; i++) {
      ids.push(this.items[i].id);
    }
    this.selecting = true;
    this.selectedIds = ids;
    SelectionBridge.cancel = () => this.exitSelect();
  }

  private exitSelect(): void {
    this.selecting = false;
    this.selectedIds = [];
    SelectionBridge.cancel = null;
  }

  private selectedItems(): VaultItem[] {
    const result: VaultItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.isSelected(this.items[i].id)) {
        result.push(this.items[i]);
      }
    }
    return result;
  }

  private applyRestore(): void {
    const targets: VaultItem[] = this.selectedItems();
    if (targets.length === 0) {
      return;
    }
    this.exitSelect();
    this.onBatchRestore(targets);
  }

  private applyPurge(): void {
    const targets: VaultItem[] = this.selectedItems();
    if (targets.length === 0) {
      return;
    }
    confirmDanger('彻底删除', `已选 ${targets.length} 个条目，将被永久删除且无法恢复。`, '永久删除', () => {
            this.exitSelect();
            this.onBatchPurge(targets);
    });
  }

  private swipeStartX: number = 0;

  /** 按 id 取当前最新对象，避免左滑按钮闭包里拿到过期数据 */
  private freshItem(id: string): VaultItem | null {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        return this.items[i];
      }
    }
    return null;
  }

  /** 左滑：左边彻底删除、右边恢复（与保险库列表同一套按钮组件） */
  @Builder
  swipeActions(item: VaultItem) {
    SwipeActions({
      leftLabel: '删除',
      leftIcon: Icons.trash,
      leftColor: Theme.DANGER,
      rightLabel: '恢复',
      rightIcon: Icons.restore,
      rightColor: Theme.SUCCESS,
      onLeftTap: () => {
        this.itemScroller.closeAllSwipeActions();
        const target: VaultItem | null = this.freshItem(item.id);
        if (target !== null) {
          this.confirmPurge(target);
        }
      },
      onRightTap: () => {
        this.itemScroller.closeAllSwipeActions();
        const target: VaultItem | null = this.freshItem(item.id);
        if (target !== null) {
          this.onRestore(target);
        }
      }
    })
  }

  private confirmPurge(item: VaultItem): void {
    confirmDanger('彻底删除', `「${item.name}」将被永久删除，无法恢复。`, '永久删除', () => this.onPurge(item));
  }

  @Builder
  row(item: VaultItem, selected: boolean) {
    Row({ space: 12 }) {
      // 选择模式：左侧勾选圆点
      if (this.selecting) {
        Row() {
          if (selected) {
            SymbolGlyph(Icons.check)
              .fontSize(13)
              .fontColor([Color.White])
          }
        }
        .width(20)
        .height(20)
        .borderRadius(10)
        .borderWidth(selected ? 0 : 1.5)
        .borderColor(Theme.TEXT_HINT)
        .backgroundColor(selected ? Theme.PRIMARY : Color.Transparent)
        .justifyContent(FlexAlign.Center)
      }

      BrandAvatar({
        raw: logoRawFor(item.uri, item.name),
        name: item.name,
        fallbackIcon: typeSymbol(item.type),
        fallbackColor: typeColor(item.type),
        diameter: 36
      })

      Column({ space: 3 }) {
        Text(item.name)
          .fontSize(Theme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(item.username.length > 0 ? item.username : CipherMeta.label(item.type))
          .fontSize(Theme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_SECONDARY)
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

    }
    .width('100%')
    .padding(12)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.CARD)
    .margin({ bottom: 8 })
    .onClick(() => {
      if (this.selecting) {
        this.toggleSelect(item.id);
      }
    })
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        SymbolGlyph(Icons.chevron)
          .fontSize(16)
          .fontColor([Theme.PRIMARY])
          .rotate({ angle: 180 })
        Text('设置')
          .fontSize(Theme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.PRIMARY)
      }
      .width('100%')
      .height(48)
      .onClick(() => this.onBack())

      Row() {
        Text('回收站')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
        Blank()
        Text(`${this.items.length} 项`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_HINT)
      }
      .width('100%')
      .padding({ bottom: 14 })

      // 选择模式工具条
      if (this.selecting) {
        Row({ space: 8 }) {
          Pill({ label: '删除', textColor: '#FFFFFF', fill: Theme.DANGER, onTap: () => this.applyPurge() })
          Pill({ label: `已选 ${this.selectedIds.length} 项`, textColor: Theme.TEXT_PRIMARY, stretch: true })
          Pill({ label: '取消', textColor: Theme.TEXT_SECONDARY, fill: Theme.BACKGROUND, onTap: () => this.exitSelect() })
          Pill({ label: '全选', textColor: Theme.PRIMARY, fill: Theme.TINT, onTap: () => this.selectAll() })
          Pill({ label: '恢复', textColor: '#FFFFFF', fill: Theme.PRIMARY, onTap: () => this.applyRestore() })
        }
        .width('100%')
        .padding({ bottom: 10 })
      }

      if (this.items.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph(Icons.trash)
            .fontSize(40)
            .fontColor([Theme.TEXT_HINT])
          Text('回收站是空的')
            .fontSize(Theme.FONT_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_SECONDARY)
          Text('删除的条目会先放在这里，30 天后由服务端清理')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_HINT)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.itemScroller }) {
          ForEach(this.items, (item: VaultItem) => {
            ListItem() {
              this.row(item, this.isSelected(item.id))
            }
            .swipeAction({
              end: {
                builder: (): void => {
                  this.swipeActions(item);
                }
              },
              edgeEffect: SwipeEdgeEffect.Spring
            })
            .gesture(LongPressGesture({ repeat: false, duration: 420 })
              .onAction(() => {
                if (this.selecting) {
                  this.toggleSelect(item.id);
                } else {
                  this.enterSelect(item.id);
                }
              }))
          }, (item: VaultItem) => `${item.id}:${item.revisionDate}:${this.selecting ? 1 : 0}:${this.isSelected(item.id) ? 1 : 0}`)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .padding({ bottom: 96 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: Theme.PAGE_PADDING, right: Theme.PAGE_PADDING })
    .backgroundColor(Theme.BACKGROUND)
    .parallelGesture(
      PanGesture({ direction: PanDirection.Right, distance: 30 })
        .onActionStart((event: GestureEvent) => {
          this.swipeStartX = event.fingerList.length > 0 ? event.fingerList[0].localX : 999;
        })
        .onActionEnd((event: GestureEvent) => {
          if (event.offsetX > 120) {
            // 多选状态下右滑只取消选择，不退出回收站
            if (this.selecting) {
              this.exitSelect();
            } else {
              this.onBack();
            }
          }
        })
    )
  }
}
