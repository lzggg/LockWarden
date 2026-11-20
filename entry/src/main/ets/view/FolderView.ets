/**
 * 文件夹管理：列出文件夹与条目数，可新建文件夹；点进去在本页查看该文件夹的条目
 * （与保险库同款列表 + 搜索），点条目直接在本页打开详情，不跳回保险库。
 * 删除入口在详情页右上角「管理」菜单，删除文件夹会把里面的条目一并移到回收站。
 */
import { Theme, CipherMeta } from '../common/Theme';
import { Pill } from './Pill';
import { confirmDanger } from '../common/Dialog';
import { VaultItem, VaultFolder } from '../common/Models';
import { Icons, typeColor, typeSymbol } from '../common/Icons';
import { DetailView } from './DetailView';
import { BrandAvatar, logoRawOf } from './LogoBits';
import { SelectionBridge } from '../common/SelectionBridge';
import { FolderBridge } from '../common/FolderBridge';
import { SwipeActions } from './SwipeActions';

/** 文件夹名称弹窗（新建 / 重命名共用）：聚焦输入，避免在列表里内联展开 */
@CustomDialog
struct NewFolderDialog {
  controller?: CustomDialogController;
  onSubmit: (name: string) => void = () => {
  };
  /** 弹窗标题 */
  title: string = '新建文件夹';
  /** 确认按钮文案 */
  submitText: string = '创建';
  /** 初始值（重命名时带入原名） */
  initial: string = '';
  @State value: string = '';

  aboutToAppear(): void {
    this.value = this.initial;
  }

  build() {
    Column({ space: 14 }) {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT_PRIMARY)

      TextInput({ text: this.value, placeholder: '文件夹名称' })
        .fontColor(Theme.TEXT_PRIMARY)
        .placeholderColor(Theme.TEXT_HINT)
        .width('100%')
        .height(44)
        .fontSize(Theme.FONT_BODY)
        .placeholderFont({ size: Theme.FONT_BODY })
        .backgroundColor(Theme.BACKGROUND)
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .defaultFocus(true)
        .onChange((v: string) => {
          this.value = v;
        })

      Row({ space: 10 }) {
        Text('取消')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_SECONDARY)
          .backgroundColor(Theme.BACKGROUND)
          .padding({ left: 18, right: 18, top: 9, bottom: 9 })
          .borderRadius(18)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
          })
        Text(this.submitText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(Theme.PRIMARY)
          .padding({ left: 18, right: 18, top: 9, bottom: 9 })
          .borderRadius(18)
          .onClick(() => {
            const name: string = this.value.trim();
            if (name.length === 0) {
              this.getUIContext().getPromptAction().showToast({ message: '请输入文件夹名称' });
              return;
            }
            if (this.controller !== undefined) {
              this.controller.close();
            }
            this.onSubmit(name);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('86%')
    .padding(20)
    .borderRadius(Theme.RADIUS)
    .backgroundColor(Theme.CARD)
  }
}

@Component
export struct FolderView {
  @Prop @Watch('syncOpenedItem') folders: VaultFolder[] = [];
  @Prop @Watch('syncOpenedItem') items: VaultItem[] = [];
  onBack: () => void = () => {
  };
  onDelete: (folder: VaultFolder) => void = () => {
  };
  onCopy: (label: string, value: string) => void = () => {
  };
  onToggleFavorite: (item: VaultItem) => void = () => {
  };
  onEdit: (item: VaultItem) => void = () => {
  };
  onDeleteItem: (item: VaultItem) => void = () => {
  };
  onCreateFolder: (name: string) => void = () => {
  };
  /** 文件夹改名 */
  onRenameFolder: (folder: VaultFolder, name: string) => void = () => {
  };
  /** 批量删除文件夹（里面的条目由外壳一并移到回收站） */
  onDeleteFolders: (folders: VaultFolder[]) => void = () => {
  };

  /** 用于操作完成后收起左滑（ListScroller 才有 closeAllSwipeActions） */
  private itemScroller: ListScroller = new ListScroller();

  /** 当前打开的文件夹 id；'' 表示列表模式 */
  @State openedId: string = '';
  @State query: string = '';
  /** 当前打开的条目（详情在本页内展示） */
  @State openedItem: VaultItem | null = null;
  /** 新建文件夹弹窗 */
  private newFolderDialog: CustomDialogController = new CustomDialogController({
    builder: NewFolderDialog({
      onSubmit: (name: string) => {
        this.onCreateFolder(name);
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    // 去掉系统默认弹窗底与内边距，只留自定义白卡片，避免两边露出灰底
    customStyle: true
  });

  /** 重命名弹窗：每次打开时新建，才能带上当前文件夹名作为初始值 */
  private renameDialog: CustomDialogController | null = null;

  private openRename(folder: VaultFolder): void {
    this.renameDialog = new CustomDialogController({
      builder: NewFolderDialog({
        title: '重命名文件夹',
        submitText: '保存',
        initial: folder.name,
        onSubmit: (name: string) => {
          this.onRenameFolder(folder, name);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.renameDialog.open();
  }

  aboutToAppear(): void {
    // 系统返回键先在内部逐级退：条目详情 → 文件夹列表 → 交给外壳关闭覆盖层
    FolderBridge.register(() => this.stepBack());
  }

  /** 内部返回一层：关条目详情 / 退回文件夹列表；已到最外层返回 false */
  private stepBack(): boolean {
    if (this.openedItem !== null) {
      this.openedItem = null;
      return true;
    }
    if (this.openedId.length > 0) {
      this.openedId = '';
      this.query = '';
      return true;
    }
    return false;
  }

  syncOpenedItem(): void {
    if (this.openedItem === null) {
      return;
    }
    const id: string = (this.openedItem as VaultItem).id;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        this.openedItem = this.items[i];
        return;
      }
    }
    // 条目已被删除/恢复
    this.openedItem = null;
  }

  /** 按 id 取当前最新对象，避免左滑按钮闭包里拿到过期数据 */
  private freshItem(id: string): VaultItem | null {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        return this.items[i];
      }
    }
    return null;
  }

  private countOf(id: string): number {
    let n: number = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].folderId === id) {
        n++;
      }
    }
    return n;
  }

  private itemsOf(id: string): VaultItem[] {
    const keyword: string = this.query.trim().toLowerCase();
    const result: VaultItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item: VaultItem = this.items[i];
      if (item.folderId !== id) {
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
    return result;
  }

  private openedFolder(): VaultFolder | null {
    for (let i = 0; i < this.folders.length; i++) {
      if (this.folders[i].id === this.openedId) {
        return this.folders[i];
      }
    }
    return null;
  }

  /** ---- 长按多选 ---- */
  @State selecting: boolean = false;
  @State selectedIds: string[] = [];

  private isSelected(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  aboutToDisappear(): void {
    SelectionBridge.cancel = null;
    FolderBridge.unregister();
  }

  private enterSelect(id: string): void {
    this.selecting = true;
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

  private exitSelect(): void {
    this.selecting = false;
    this.selectedIds = [];
    SelectionBridge.cancel = null;
  }

  private selectAll(): void {
    const ids: string[] = [];
    for (let i = 0; i < this.folders.length; i++) {
      ids.push(this.folders[i].id);
    }
    this.selecting = true;
    this.selectedIds = ids;
    SelectionBridge.cancel = () => this.exitSelect();
  }

  private selectedFolders(): VaultFolder[] {
    const result: VaultFolder[] = [];
    for (let i = 0; i < this.folders.length; i++) {
      if (this.isSelected(this.folders[i].id)) {
        result.push(this.folders[i]);
      }
    }
    return result;
  }

  private applyDeleteSelected(): void {
    const targets: VaultFolder[] = this.selectedFolders();
    if (targets.length === 0) {
      return;
    }
    let itemCount: number = 0;
    for (let i = 0; i < targets.length; i++) {
      itemCount += this.countOf(targets[i].id);
    }
    confirmDanger('删除文件夹', itemCount > 0 ? `已选 ${targets.length} 个文件夹，其中的 ${itemCount} 个条目会一并移到回收站（可在回收站恢复）。` : `已选 ${targets.length} 个文件夹，确定全部删除？`, '删除', () => {
            const list: VaultFolder[] = targets.slice(0);
            this.exitSelect();
            this.onDeleteFolders(list);
    });
  }
  private confirmDelete(folder: VaultFolder): void {
    const count: number = this.countOf(folder.id);
    confirmDanger('删除文件夹', count > 0 ? `「${folder.name}」里有 ${count} 个条目，删除文件夹会把这些条目一并移到回收站（可在回收站恢复）。` : `确定删除文件夹「${folder.name}」？`, '删除', () => {
            this.openedId = '';
            this.query = '';
            this.onDelete(folder);
    });
  }

  /** 左滑露出的按钮：删除（红）在左、收藏（橙黄）在右（与保险库列表同一组件） */
  @Builder
  itemSwipeActions(item: VaultItem) {
    SwipeActions({
      leftLabel: '删除',
      leftIcon: Icons.trash,
      leftColor: Theme.DANGER,
      rightLabel: item.favorite ? '取消收藏' : '收藏',
      rightIcon: item.favorite ? Icons.starFill : Icons.star,
      rightColor: '#F5A623',
      onRightTap: () => {
        this.itemScroller.closeAllSwipeActions();
        const target: VaultItem | null = this.freshItem(item.id);
        if (target !== null) {
          this.onToggleFavorite(target);
        }
      },
      onLeftTap: () => {
        this.itemScroller.closeAllSwipeActions();
        const target: VaultItem | null = this.freshItem(item.id);
        if (target !== null) {
          this.onDeleteItem(target);
        }
      }
    })
  }

  @Builder
  itemRow(item: VaultItem) {
    Row({ space: 14 }) {
      BrandAvatar({
        raw: logoRawOf(item.fields),
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
        Text(item.username.length > 0 ? item.username : CipherMeta.label(item.type))
          .fontSize(Theme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
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
      SymbolGlyph(Icons.chevron)
        .fontSize(14)
        .fontColor([Theme.TEXT_HINT])
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 12, bottom: 12 })
    .backgroundColor(Theme.CARD)
    .borderRadius(Theme.RADIUS)
    .margin({ bottom: 8 })
    .onClick(() => {
      this.openedItem = item;
    })
  }

  build() {
    Stack() {
      Column() {
        // 返回
        Row({ space: 4 }) {
          SymbolGlyph(Icons.chevron)
            .fontSize(16)
            .fontColor([Theme.PRIMARY])
            .rotate({ angle: 180 })
          Text(this.openedId.length > 0 ? '文件夹' : '设置')
            .fontSize(Theme.FONT_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.PRIMARY)
        }
        .width('100%')
        .height(48)
        .onClick(() => {
          // 逐级退：条目详情 → 文件夹列表 → 由外壳关闭本页
          if (!this.stepBack()) {
            this.onBack();
          }
        })

        // 标题栏：标题 + 数量 + 管理/新建
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text(this.openedId.length > 0 ?
              (this.openedFolder() === null ? '文件夹' : (this.openedFolder() as VaultFolder).name) : '文件夹')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.openedId.length > 0 ? `${this.itemsOf(this.openedId).length} 项` : `${this.folders.length} 个文件夹`)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_HINT)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.openedId.length > 0) {
            Text('管理')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.PRIMARY)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .bindMenu([
                {
                  value: '重命名文件夹',
                  action: () => {
                    const folder: VaultFolder | null = this.openedFolder();
                    if (folder !== null) {
                      this.openRename(folder);
                    }
                  }
                },
                {
                  value: '删除文件夹',
                  action: () => {
                    const folder: VaultFolder | null = this.openedFolder();
                    if (folder !== null) {
                      this.confirmDelete(folder);
                    }
                  }
                }
              ])
          } else {
            Row() {
              SymbolGlyph(Icons.add)
                .fontSize(20)
                .fontColor([Color.White])
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(Theme.PRIMARY)
            .onClick(() => {
              this.newFolderDialog.open();
            })
          }
        }
        .width('100%')
        .padding({ top: 4, bottom: 14 })

        // 多选工具条
        if (this.selecting) {
          Row({ space: 8 }) {
            Pill({ label: '删除', textColor: '#FFFFFF', fill: Theme.DANGER, onTap: () => this.applyDeleteSelected() })
            Pill({ label: `已选 ${this.selectedIds.length} 项`, textColor: Theme.TEXT_PRIMARY, stretch: true })
            Pill({ label: '取消', textColor: Theme.TEXT_SECONDARY, fill: Theme.BACKGROUND, onTap: () => this.exitSelect() })
            Pill({ label: '全选', textColor: Theme.PRIMARY, fill: Theme.TINT, onTap: () => this.selectAll() })
          }
          .width('100%')
          .padding({ bottom: 10 })
        }

        if (this.openedId.length > 0) {
          // 搜索框（与保险库一致）
          Row({ space: 8 }) {
            SymbolGlyph(Icons.search)
              .fontSize(16)
              .fontColor([Theme.TEXT_HINT])
            TextInput({ text: this.query, placeholder: '搜索该文件夹' })
              .fontColor(Theme.TEXT_PRIMARY)
              .layoutWeight(1)
              .height(40)
              .backgroundColor(Color.Transparent)
              .fontSize(Theme.FONT_BODY)
              .placeholderFont({ size: Theme.FONT_BODY })
              .placeholderColor(Theme.TEXT_HINT)
              .padding(0)
              .onChange((value: string) => {
                this.query = value;
              })
          }
          .width('100%')
          .padding({ left: 14, right: 14 })
          .backgroundColor(Theme.CARD)
          .borderRadius(20)
          .margin({ bottom: 12 })

          if (this.itemsOf(this.openedId).length === 0) {
            Column({ space: 10 }) {
              SymbolGlyph(Icons.folder)
                .fontSize(40)
                .fontColor([Theme.TEXT_HINT])
              Text(this.query.length > 0 ? '没有匹配的条目' : '这个文件夹是空的')
                .fontSize(Theme.FONT_BODY)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TEXT_SECONDARY)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            List({ scroller: this.itemScroller }) {
              ForEach(this.itemsOf(this.openedId), (item: VaultItem) => {
                ListItem() {
                  this.itemRow(item)
                }
                .swipeAction({
                  end: {
                    builder: (): void => {
                      this.itemSwipeActions(item);
                    }
                  },
                  edgeEffect: SwipeEdgeEffect.Spring
                })
              }, (item: VaultItem) => `${item.id}:${item.revisionDate}:${item.favorite ? 1 : 0}`)
            }
            .layoutWeight(1)
            .width('100%')
            .scrollBar(BarState.Off)
            .padding({ bottom: 96 })
          }
        } else if (this.folders.length === 0) {
          Column({ space: 10 }) {
            SymbolGlyph(Icons.folder)
              .fontSize(40)
              .fontColor([Theme.TEXT_HINT])
            Text('还没有文件夹')
              .fontSize(Theme.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_SECONDARY)
            Text('点右上角「新建」即可创建')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_HINT)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.folders, (folder: VaultFolder) => {
              ListItem() {
                Row({ space: 12 }) {
                  if (this.selecting) {
                    Row() {
                      if (this.isSelected(folder.id)) {
                        SymbolGlyph(Icons.check)
                          .fontSize(13)
                          .fontColor([Color.White])
                      }
                    }
                    .width(20)
                    .height(20)
                    .borderRadius(10)
                    .borderWidth(this.isSelected(folder.id) ? 0 : 1.5)
                    .borderColor(Theme.TEXT_HINT)
                    .backgroundColor(this.isSelected(folder.id) ? Theme.PRIMARY : Color.Transparent)
                    .justifyContent(FlexAlign.Center)
                  }
                  SymbolGlyph(Icons.folder)
                    .fontSize(20)
                    .fontColor([Theme.PRIMARY])
                  Column({ space: 3 }) {
                    Text(folder.name)
                      .fontSize(Theme.FONT_BODY)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.TEXT_PRIMARY)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                    Text(`${this.countOf(folder.id)} 项`)
                      .fontSize(Theme.FONT_CAPTION)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.TEXT_SECONDARY)
                      .width('100%')
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  // 行内更多操作：重命名 / 删除（选择模式下不显示，避免和勾选冲突）
                  if (!this.selecting) {
                    Text('⋯')
                      .fontSize(20)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.TEXT_HINT)
                      .padding({ left: 10, right: 6, top: 2, bottom: 2 })
                      .bindMenu([
                        {
                          value: '重命名',
                          action: () => {
                            this.openRename(folder);
                          }
                        },
                        {
                          value: '删除文件夹',
                          action: () => {
                            this.confirmDelete(folder);
                          }
                        }
                      ])
                  }

                  SymbolGlyph(Icons.chevron)
                    .fontSize(14)
                    .fontColor([Theme.TEXT_HINT])
                }
                .width('100%')
                .padding(12)
                .borderRadius(Theme.RADIUS)
                .backgroundColor(Theme.CARD)
                .margin({ bottom: 8 })
                .onClick(() => {
                  if (this.selecting) {
                    this.toggleSelect(folder.id);
                  } else {
                    this.openedId = folder.id;
                    this.query = '';
                  }
                })
              }
              .gesture(LongPressGesture({ repeat: false, duration: 420 })
                .onAction(() => {
                  if (this.selecting) {
                    this.toggleSelect(folder.id);
                  } else {
                    this.enterSelect(folder.id);
                  }
                }))
            }, (folder: VaultFolder) => `${folder.id}:${folder.name}`)
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
          .onActionEnd((event: GestureEvent) => {
            if (event.offsetX > 120) {
              if (this.openedItem !== null) {
                this.openedItem = null;
              } else if (this.openedId.length > 0) {
                this.openedId = '';
                this.query = '';
              } else {
                this.onBack();
              }
            }
          })
      )

      // 条目详情：直接在本页内打开
      if (this.openedItem !== null) {
        DetailView({
          item: this.openedItem as VaultItem,
          folderName: this.openedFolder() === null ? '' : (this.openedFolder() as VaultFolder).name,
          backLabel: '文件夹',
          onCopy: (label: string, value: string) => this.onCopy(label, value),
          onToggleFavorite: () => {
            this.onToggleFavorite(this.openedItem as VaultItem);
          },
          onEdit: () => {
            const target: VaultItem = this.openedItem as VaultItem;
            this.openedItem = null;
            this.onEdit(target);
          },
          onDelete: () => {
            const target: VaultItem = this.openedItem as VaultItem;
            this.openedItem = null;
            this.onDeleteItem(target);
          },
          onClose: () => {
            this.openedItem = null;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
