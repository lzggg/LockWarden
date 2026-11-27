/**
 * 保险库页（仿 Bitwarden Android 的视觉结构）：
 *   标题栏（同步 / 锁定） → 搜索框 → 文件夹筛选条 → 条目列表（圆形类型头像） → 右下角 +
 */
import { Theme, CipherMeta, syncLabel, hostOf } from '../common/Theme';
import { Pill } from './Pill';
import { confirmDanger } from '../common/Dialog';
import { VaultItem, VaultFolder } from '../common/Models';
import { Icons, typeColor, typeSymbol } from '../common/Icons';
import { SelectionBridge } from '../common/SelectionBridge';
import { BrandAvatar, logoRawFor } from './LogoBits';
import { SwipeActions } from './SwipeActions';
import { mediaquery } from '@kit.ArkUI';
import { Responsive } from '../common/Responsive';

/**
 * 筛选 chip。
 *
 * 同样必须独立成组件：@Builder 的按值参数（active）变化不会触发重绘，
 * 会出现"点了但选中态不切换"的问题。
 */
function sortLabel(mode: string): string {
  if (mode === 'created') {
    return '按新增时间';
  }
  if (mode === 'updated') {
    return '按修改时间';
  }
  return '按名称';
}

@Component
struct FilterChip {
  @Prop label: string = '';
  @Prop active: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Text(this.label)
      .fontSize(Theme.FONT_CAPTION)
      .fontColor(this.active ? Color.White : Theme.TEXT_SECONDARY)
      .backgroundColor(this.active ? Theme.PRIMARY : Theme.CARD)
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .margin({ right: 8 })
      .onClick(() => this.onTap())
  }
}

@Component
export struct VaultView {
  @Prop items: VaultItem[] = [];
  @Prop folders: VaultFolder[] = [];
  @Prop syncAt: number = 0;
  @Prop syncing: boolean = false;
  @Prop demo: boolean = false;
  @Prop localMode: boolean = false;
  /** 排序方式：name | created | updated */
  @Prop sortMode: string = 'name';


  onSortChange: (mode: string) => void = () => {
  };
  /** 批量收藏 / 批量删除（选择模式下使用） */
  onBatchFavorite: (items: VaultItem[], favorite: boolean) => void = () => {
  };
  onBatchDelete: (items: VaultItem[]) => void = () => {
  };

  /** 选择模式 */
  @State selecting: boolean = false;
  @State selectedIds: string[] = [];

  private isSelected(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  /** 仅用于驱动"同步完成 HH:mm"随时间重算（ArkUI 只在状态变化时重建） */
  @State tick: number = 0;
  private clockTimer: number = -1;
  /** 平板/分屏等宽屏：筛选条靠左；手机上仍居中，保持原来的观感 */
  @State wide: boolean = false;
  private wideListener: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    this.clockTimer = setInterval(() => {
      this.tick = this.tick + 1;
    }, 30000);
    this.wide = Responsive.isWideNow();
    // 横竖屏切换时自动重排筛选 chip
    this.wideListener = Responsive.watchWide(this.getUIContext(), (wide: boolean) => {
      this.wide = wide;
    });
  }

  aboutToDisappear(): void {
    if (this.wideListener !== null) {
      this.wideListener.off('change');
      this.wideListener = null;
    }
    if (this.clockTimer >= 0) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
    SelectionBridge.cancel = null;
  }

  /** 同步状态文案（读一下 tick 以建立刷新依赖） */
  private syncText(): string {
    const stamp: number = this.tick;
    if (this.localMode) {
      return this.syncing ? '正在整理…' : '本机存储';
    }
    return syncLabel(this.syncAt + 0 * stamp, this.syncing);
  }

  private enterSelect(id: string): void {
    this.selecting = true;
    // 让返回键/侧滑优先取消选择
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

  /** 全选当前筛选出来的条目（取消选择统一用「取消」按钮） */
  private selectAll(): void {
    const visible: VaultItem[] = this.visibleItems();
    const ids: string[] = [];
    for (let i = 0; i < visible.length; i++) {
      ids.push(visible[i].id);
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

  /** 当前选中的条目（按列表里的最新对象取，避免选中项被删/改后取到旧值） */
  private selectedItems(): VaultItem[] {
    const result: VaultItem[] = [];
    for (let i = 0; i < this.selectedIds.length; i++) {
      const target: VaultItem | null = this.freshItem(this.selectedIds[i]);
      if (target !== null) {
        result.push(target);
      }
    }
    return result;
  }

  /** 选中的条目是否都已收藏（决定按钮显示"收藏"还是"取消收藏"） */
  private allSelectedFavorited(): boolean {
    const targets: VaultItem[] = this.selectedItems();
    if (targets.length === 0) {
      return false;
    }
    for (let i = 0; i < targets.length; i++) {
      if (!targets[i].favorite) {
        return false;
      }
    }
    return true;
  }

  private applyFavorite(): void {
    const targets: VaultItem[] = this.selectedItems();
    if (targets.length === 0) {
      return;
    }
    const favorite: boolean = !this.allSelectedFavorited();
    this.exitSelect();
    this.onBatchFavorite(targets, favorite);
  }

  private applyDelete(): void {
    const targets: VaultItem[] = this.selectedItems();
    if (targets.length === 0) {
      return;
    }
    confirmDanger('移到回收站', `已选 ${targets.length} 个条目，全部移到回收站？`, '移到回收站', () => {
            this.exitSelect();
            this.onBatchDelete(targets);
    });
  }

  onSync: () => void = () => {
  };
  onLock: () => void = () => {
  };
  onAdd: () => void = () => {
  };
  onSelect: (item: VaultItem) => void = () => {
  };
  /** 左滑操作：收藏 / 取消收藏 */
  onToggleFavorite: (item: VaultItem) => void = () => {
  };
  /** 左滑操作：移到回收站 */
  onDelete: (item: VaultItem) => void = () => {
  };

  /** 按 id 取当前列表里的条目，避免左滑按钮拿到过期对象 */
  private freshItem(id: string): VaultItem | null {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        return this.items[i];
      }
    }
    return null;
  }

  /** 左滑露出的两个操作按钮：删除（红）在左、收藏（橙黄）在右——删除靠左更容易误触，放在内侧 */
  @Builder
  swipeActions(item: VaultItem) {
    SwipeActions({
      leftLabel: '删除',
      leftIcon: Icons.trash,
      leftColor: Theme.DANGER,
      rightLabel: item.favorite ? '取消收藏' : '收藏',
      rightIcon: item.favorite ? Icons.starFill : Icons.star,
      rightColor: '#F5A623',
      onRightTap: () => {
        this.listScroller.closeAllSwipeActions();
        const target: VaultItem | null = this.freshItem(item.id);
        if (target !== null) {
          this.onToggleFavorite(target);
        }
      },
      onLeftTap: () => {
        this.listScroller.closeAllSwipeActions();
        const target: VaultItem | null = this.freshItem(item.id);
        if (target !== null) {
          this.onDelete(target);
        }
      }
    })
  }

  @State query: string = '';
  /** '' = 全部，'favorite' = 收藏，'none' = 无文件夹，其他 = 文件夹 id */
  @State filter: string = '';
  /** 用于操作完成后收起左滑（ListScroller 才有 closeAllSwipeActions） */
  private listScroller: ListScroller = new ListScroller();

  /** 排序比较：新增/修改时间都是新的在前；同值时回落到名称，保证稳定 */
  private compareItems(a: VaultItem, b: VaultItem): number {
    if (this.sortMode === 'created') {
      const ac: string = a.creationDate === undefined ? '' : a.creationDate;
      const bc: string = b.creationDate === undefined ? '' : b.creationDate;
      if (ac !== bc) {
        return ac > bc ? -1 : 1;
      }
    } else if (this.sortMode === 'updated') {
      if (a.revisionDate !== b.revisionDate) {
        return a.revisionDate > b.revisionDate ? -1 : 1;
      }
    }
    const an: string = a.name.toLowerCase();
    const bn: string = b.name.toLowerCase();
    if (an !== bn) {
      return an < bn ? -1 : 1;
    }
    return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
  }

  /** 是否存在没有归入文件夹的条目（没有就不显示「无文件夹」筛选） */
  private hasUnfiledItems(): boolean {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].folderId.length === 0) {
        return true;
      }
    }
    return false;
  }

  private inFilter(item: VaultItem): boolean {
    if (this.filter === '') {
      return true;
    }
    if (this.filter === 'favorite') {
      return item.favorite;
    }
    if (this.filter === 'none') {
      return item.folderId.length === 0;
    }
    return item.folderId === this.filter;
  }

  private visibleItems(): VaultItem[] {
    const keyword: string = this.query.trim().toLowerCase();
    const result: VaultItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item: VaultItem = this.items[i];
      if (!this.inFilter(item)) {
        continue;
      }
      if (keyword.length > 0) {
        const haystack: string = `${item.name} ${item.username} ${item.uri}`.toLowerCase();
        if (haystack.indexOf(keyword) < 0) {
          continue;
        }
      }
      result.push(item);
    }
    result.sort((a: VaultItem, b: VaultItem): number => this.compareItems(a, b));
    return result;
  }

  private subtitleOf(item: VaultItem): string {
    if (item.username.length > 0) {
      return item.username;
    }
    if (hostOf(item.uri).length > 0) {
      return hostOf(item.uri);
    }
    return CipherMeta.label(item.type);
  }

  @Builder
  itemRow(item: VaultItem, selected: boolean) {
    Row({ space: 14 }) {
      // 选择模式：左侧勾选圆点
      if (this.selecting) {
        Row() {
          if (selected) {
            SymbolGlyph(Icons.check)
              .fontSize(14)
              .fontColor([Color.White])
          }
        }
        .width(22)
        .height(22)
        .borderRadius(11)
        .borderWidth(selected ? 0 : 1.5)
        .borderColor(Theme.TEXT_HINT)
        .backgroundColor(selected ? Theme.PRIMARY : Color.Transparent)
        .justifyContent(FlexAlign.Center)
      }

      // 圆形类型头像：Bitwarden 的条目图标位
      BrandAvatar({
        raw: logoRawFor(item.uri, item.name),
        name: item.name,
        fallbackIcon: typeSymbol(item.type),
        fallbackColor: typeColor(item.type),
        diameter: 40
      })

      Column({ space: 3 }) {
        Text(item.name)
          .fontSize(Theme.FONT_BODY)
          .fontColor(item.broken ? Theme.TEXT_HINT : Theme.TEXT_PRIMARY)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.subtitleOf(item))
          .fontSize(Theme.FONT_CAPTION)
          .fontColor(Theme.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (item.favorite) {
        SymbolGlyph(Icons.starFill)
          .fontSize(16)
          .fontColor(['#FFB300'])
      }
      if (!this.selecting) {
        SymbolGlyph(Icons.chevron)
          .fontSize(14)
          .fontColor([Theme.TEXT_HINT])
      }
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 12, bottom: 12 })
    .backgroundColor(Theme.CARD)
    .borderRadius(Theme.RADIUS)
    .margin({ bottom: 8 })
    .onClick(() => {
      if (this.selecting) {
        this.toggleSelect(item.id);
      } else {
        this.onSelect(item);
      }
    })
  }

  build() {
    Row() {
      Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // 标题栏
        Row({ space: 16 }) {
          Column({ space: 2 }) {
            Row({ space: 8 }) {
              Text('保险库')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TEXT_PRIMARY)
              if (this.demo) {
                Text('演示数据')
                  .fontSize(11)
                  .fontColor('#B26A00')
                  .backgroundColor('#FFF3E0')
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(8)
              }
            }

            Text(this.syncText())
              .fontSize(12)
              .fontColor(Theme.TEXT_HINT)


            // 排序入口：左上角、标题下方
            Text(`排序：${sortLabel(this.sortMode)} ▾`)
              .fontSize(12)
              .fontColor(Theme.PRIMARY)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(Theme.TINT)
              .borderRadius(12)
              .margin({ top: 4 })
              .bindMenu([
                {
                  value: '按名称',
                  action: () => {
                    this.onSortChange('name');
                  }
                },
                {
                  value: '按新增时间',
                  action: () => {
                    this.onSortChange('created');
                  }
                },
                {
                  value: '按修改时间',
                  action: () => {
                    this.onSortChange('updated');
                  }
                }
              ])
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.syncing) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color(Theme.PRIMARY)
          } else {
            SymbolGlyph(Icons.refresh)
              .fontSize(22)
              .fontColor([Theme.TEXT_SECONDARY])
              .onClick(() => this.onSync())
          }
          SymbolGlyph(Icons.lock)
            .fontSize(22)
            .fontColor([Theme.TEXT_SECONDARY])
            .onClick(() => this.onLock())
        }
        .width('100%')
        .padding({ top: 8, bottom: 14 })

        // 选择模式工具条
        if (this.selecting) {
          Row({ space: 8 }) {
            Pill({ label: '删除', textColor: '#FFFFFF', fill: Theme.DANGER, onTap: () => this.applyDelete() })
            Pill({ label: `已选 ${this.selectedIds.length} 项`, textColor: Theme.TEXT_PRIMARY, stretch: true })
            Pill({ label: this.allSelectedFavorited() ? '取消收藏' : '收藏', textColor: '#FFFFFF', fill: '#F5A623', onTap: () => this.applyFavorite() })
            Pill({ label: '取消', textColor: Theme.TEXT_SECONDARY, fill: Theme.BACKGROUND, onTap: () => this.exitSelect() })
            Pill({ label: '全选', textColor: Theme.PRIMARY, fill: Theme.TINT, onTap: () => this.selectAll() })
          }
          .width('100%')
          .padding({ bottom: 10 })
        }

        // 搜索框
        Row({ space: 8 }) {
          SymbolGlyph(Icons.search)
            .fontSize(16)
            .fontColor([Theme.TEXT_HINT])
            .margin({ left: 12 })
          TextInput({ text: this.query, placeholder: '搜索保险库' })
            .fontColor(Theme.TEXT_PRIMARY)
            .height(40)
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .fontSize(14)
            .placeholderColor(Theme.TEXT_HINT)
            .onChange((value: string) => {
              this.query = value;
            })
          if (this.query.length > 0) {
            // 清空按钮：点一下把搜索词全部删掉
            Row() {
              SymbolGlyph(Icons.close)
                .fontSize(13)
                .fontColor([Theme.TEXT_SECONDARY])
            }
            .width(24)
            .height(24)
            .borderRadius(12)
            .backgroundColor(Theme.DIVIDER)
            .justifyContent(FlexAlign.Center)
            .margin({ right: 8 })
            .onClick(() => {
              this.query = '';
            })
          }
        }
        .width('100%')
        .height(40)
        .borderRadius(20)
        .backgroundColor(Theme.CARD)
        .margin({ bottom: 12 })

        // 文件夹筛选条
        Scroll() {
          Row() {
            FilterChip({
              label: '全部',
              active: this.filter === '',
              onTap: () => {
                this.filter = '';
              }
            })
            FilterChip({
              label: '收藏',
              active: this.filter === 'favorite',
              onTap: () => {
                this.filter = 'favorite';
              }
            })
            if (this.hasUnfiledItems() || this.filter === 'none') {
              FilterChip({
                label: '无文件夹',
                active: this.filter === 'none',
                onTap: () => {
                  this.filter = 'none';
                }
              })
            }
            ForEach(this.folders, (folder: VaultFolder) => {
              FilterChip({
                label: folder.name,
                active: this.filter === folder.id,
                onTap: () => {
                  this.filter = folder.id;
                }
              })
            }, (folder: VaultFolder) => `${folder.id}:${folder.name}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        // 宽屏下把内容靠左，否则 Row 会被 Scroll 居中，筛选标签看起来"漂"在中间
        .align(this.wide ? Alignment.TopStart : Alignment.Center)
        .width('100%')
        .height(38)
        .margin({ bottom: 10 })

        if (this.visibleItems().length === 0) {
          Column({ space: 10 }) {
            SymbolGlyph(Icons.vault)
              .fontSize(40)
              .fontColor([Theme.TEXT_HINT])
            Text(this.items.length === 0 ? '保险库里还没有条目' : '没有匹配的条目')
              .fontSize(Theme.FONT_BODY)
              .fontColor(Theme.TEXT_SECONDARY)
            Text(this.items.length === 0 ? '点击右下角 + 新建第一条登录信息' : '换个关键词或筛选条件试试')
              .fontSize(12)
              .fontColor(Theme.TEXT_HINT)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ scroller: this.listScroller }) {
            ForEach(this.visibleItems(), (item: VaultItem) => {
              ListItem() {
                this.itemRow(item, this.isSelected(item.id))
              }
              .gesture(LongPressGesture({ repeat: false, duration: 420 })
                .onAction(() => {
                  if (this.selecting) {
                    this.toggleSelect(item.id);
                  } else {
                    this.enterSelect(item.id);
                  }
                }))
              .swipeAction({
                end: {
                  builder: (): void => {
                    this.swipeActions(item);
                  }
                },
                edgeEffect: SwipeEdgeEffect.Spring
              })
            }, (item: VaultItem) => `${item.id}:${item.revisionDate}:${item.favorite ? 1 : 0}:${this.selecting ? 1 : 0}:${this.isSelected(item.id) ? 1 : 0}`)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          // 底部只留一点点空隙：列表可以滑到 + 按钮那一行，+ 左侧不再是一条空白带
          .padding({ top: 2, bottom: 10 })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: Theme.PAGE_PADDING, right: Theme.PAGE_PADDING })

      // 右下角新建按钮
      Row() {
        SymbolGlyph(Icons.add)
          .fontSize(26)
          .fontColor([Color.White])
      }
      .width(56)
      .height(56)
      .borderRadius(18)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Theme.PRIMARY)
      .margin({ right: 20, bottom: 24 })
      .shadow({ radius: 14, color: '#330A59F7', offsetY: 6 })
      .onClick(() => this.onAdd())
      }
      .width('100%')
      .height('100%')
      // 电脑/大屏窗口：内容最宽 1180，超出部分左右留白，避免一行拉到屏幕边缘
      .constraintSize({ maxWidth: 1180 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Theme.BACKGROUND)
  }
}
