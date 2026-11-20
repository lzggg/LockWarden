/**
 * 主界面外壳：底部四个 Tab（保险库 / 生成器 / 验证器 / 设置），仿 Bitwarden Android 的导航结构。
 *
 * 本组件不直接访问网络、存储或加密模块，所有数据与动作都由外部注入，
 * 因此真机入口（pages/Index）和预览入口（pages/PreviewDemo）可以复用同一套界面。
 */
import { VaultItem, VaultFolder, CipherDraft, CipherType, emptyDraft } from '../common/Models';
import { Theme } from '../common/Theme';
import { confirmDanger } from '../common/Dialog';
import { Icons } from '../common/Icons';
import { BackBus } from '../common/BackBus';
import { EditorBridge } from '../common/EditorBridge';
import { SelectionBridge } from '../common/SelectionBridge';
import { FolderBridge } from '../common/FolderBridge';
import { VaultView } from './VaultView';
import { DetailView } from './DetailView';
import { CipherEditor } from './CipherEditor';
import { TrashView } from './TrashView';
import { SecurityView } from './SecurityView';
import { ChangePasswordView } from './ChangePasswordView';
import { FolderView } from './FolderView';
import { GeneratorView } from './GeneratorView';
import { TotpView } from './TotpView';
import { TotpAccount } from '../common/TotpStore';
import { SettingsView } from './SettingsView';

/** 把已解密条目转成编辑器草稿 */
function draftFromItem(item: VaultItem): CipherDraft {
  const draft: CipherDraft = emptyDraft(item.type);
  draft.id = item.id;
  draft.name = item.name;
  draft.notes = item.notes;
  draft.favorite = item.favorite;
  draft.folderId = item.folderId;
  draft.username = item.username;
  draft.password = item.password;
  draft.totp = item.totp;
  draft.uri = item.uri;
  if (item.card !== null && item.card !== undefined) {
    draft.card = item.card;
  }
  if (item.identity !== null && item.identity !== undefined) {
    draft.identity = item.identity;
  }
  if (item.fields !== null && item.fields !== undefined) {
    draft.fields = item.fields.slice(0);
  }
  return draft;
}

@Component
export struct MainShell {
  @Prop items: VaultItem[] = [];
  @Prop trash: VaultItem[] = [];
  @Prop folders: VaultFolder[] = [];
  @Prop email: string = '';
  @Prop server: string = '';
  @Prop syncAt: number = 0;
  @Prop syncing: boolean = false;
  @Prop totpAccounts: TotpAccount[] = [];
  onScanTotp: () => void = () => {
  };
  onAddTotp: (issuer: string, account: string, secret: string) => void = () => {
  };
  onDeleteTotp: (id: string) => void = () => {
  };
  @Prop demo: boolean = false;
  @Prop localMode: boolean = false;
  @Prop autoLockMinutes: number = 5;
  @Prop notifyKeepSeconds: number = 30;
  @Prop sortMode: string = 'name';
  @Prop bioFingerprint: boolean = false;
  @Prop bioFace: boolean = false;
  @Prop fpAvailable: boolean = false;
  @Prop faceAvailable: boolean = false;
  @Prop fpReason: string = '';
  @Prop faceReason: string = '';
  @Prop bioRev: number = 0;

  onSync: () => void = () => {
  };
  onLock: () => void = () => {
  };
  onSignOut: () => void = () => {
  };
  onCopy: (label: string, value: string) => void = () => {
  };
  random: (bound: number) => number = (bound: number) => Math.floor(Math.random() * bound);
  onSaveDraft: (draft: CipherDraft) => Promise<void> = async () => {
  };
  onDelete: (item: VaultItem) => Promise<void> = async () => {
  };
  onRestore: (item: VaultItem) => Promise<void> = async () => {
  };
  onPurge: (item: VaultItem) => Promise<void> = async () => {
  };
  onToggleFavorite: (item: VaultItem) => Promise<void> = async () => {
  };
  /** 批量操作（多选） */
  onBatchFavorite: (items: VaultItem[], favorite: boolean) => Promise<void> = async () => {
  };
  onBatchDelete: (items: VaultItem[]) => Promise<void> = async () => {
  };
  onBatchRestore: (items: VaultItem[]) => Promise<void> = async () => {
  };
  onBatchPurge: (items: VaultItem[]) => Promise<void> = async () => {
  };
  onDeleteFolder: (folder: VaultFolder) => Promise<void> = async () => {
  };
  onDeleteFolders: (folders: VaultFolder[]) => Promise<void> = async () => {
  };
  onAutoLock: (minutes: number) => void = () => {
  };
  onNotifyKeep: (seconds: number) => void = () => {
  };
  onSortChange: (mode: string) => void = () => {
  };
  onToggleBiometric: (kind: string, enable: boolean) => void = () => {
  };
  onCreateFolder: (name: string) => Promise<string> = async () => '';
  onScanTotpForEditor: () => Promise<string> = async () => '';
  onRenameFolder: (folder: VaultFolder, name: string) => Promise<void> = async () => {
  };
  /** 数据被外部改动（如导入）后刷新页面状态 */
  onDataChanged: () => void = () => {
  };

  @State tab: number = 0;
  @State selected: VaultItem | null = null;
  @State editing: CipherDraft | null = null;
  @State showTrash: boolean = false;
  @State showBiometric: boolean = false;
  @State showChangePassword: boolean = false;
  /** 最近一次消费返回事件的时间：同一次侧滑会被系统返回与页面手势各投递一次，用它去重 */
  private lastBackAt: number = 0;
  /** 底部导航条高度：TabBar 用同色背景盖住它，避免下面多出灰边 */
  @Prop bottomInset: number = 0;
  /** 禁止截屏开关状态 */
  @Prop noScreenshot: boolean = false;
  onToggleNoScreenshot: (on: boolean) => void = () => {
  };
  @State showFolders: boolean = false;

  aboutToAppear(): void {
    BackBus.register(() => this.handleBack());
  }

  aboutToDisappear(): void {
    BackBus.unregister();
  }

  /**
   * 返回栈：编辑器 → 详情 → 回收站 → 交还系统。
   * 返回 true 表示这一层已经被关掉，系统不再继续 pop。
   */
  private handleBack(): boolean {
    // 侧滑时 PanGesture 与系统返回会先后触发，同一动作只处理一次，避免连退两层
    const now: number = Date.now();
    if (now - this.lastBackAt < 400) {
      return true;
    }
    const consumed: boolean = this.handleBackOnce();
    if (consumed) {
      this.lastBackAt = now;
    }
    return consumed;
  }

  /** 真正的返回处理（顺序：覆盖层 → 详情 → 生物识别 → 回收站） */
  private handleBackOnce(): boolean {
    if (this.editing !== null) {
      // 交给编辑器自己决定：有改动先弹"放弃更改？"
      EditorBridge.close();
      return true;
    }
    if (SelectionBridge.close()) {
      // 多选状态下返回 = 取消选择，不退出页面
      return true;
    }
    if (this.showFolders) {
      // 先在文件夹页内部逐级后退（条目详情 → 文件夹列表），退到最外层才关页面
      if (!FolderBridge.close()) {
        this.showFolders = false;
      }
      return true;
    }
    if (this.selected !== null) {
      this.selected = null;
      return true;
    }
    if (this.showChangePassword) {
      // 修改主密码是盖在「安全」之上的，先关它才能回到安全页
      this.showChangePassword = false;
      return true;
    }
    if (this.showBiometric) {
      this.showBiometric = false;
      return true;
    }
    if (this.showTrash) {
      this.showTrash = false;
      return true;
    }
    return false;
  }

  private folderNameOf(item: VaultItem): string {
    if (item.folderId.length === 0) {
      return '';
    }
    for (let i = 0; i < this.folders.length; i++) {
      if (this.folders[i].id === item.folderId) {
        return this.folders[i].name;
      }
    }
    return '';
  }

  @Builder
  tabItem(index: number, title: string, icon: Resource) {
    // 高度 = 58（正常条高）+ 手势条高度；内容在 58 的区域内垂直居中，下面留白画成同色底
    Column() {
      Column({ space: 2 }) {
        SymbolGlyph(icon)
          .fontSize(25)
          .fontColor([this.tab === index ? Theme.PRIMARY : Theme.TEXT_HINT])
        Text(title)
          .fontSize(11)
          .fontColor(this.tab === index ? Theme.PRIMARY : Theme.TEXT_HINT)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(58 + this.bottomInset)
    // 上下留白取中间值：既贴不到手势条，也不贴顶部
    .padding({ bottom: 6 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  vaultTab() {
    Stack() {
      VaultView({
        items: this.items,
        folders: this.folders,
        syncAt: this.syncAt,
        syncing: this.syncing,
        demo: this.demo,
        localMode: this.localMode,
        sortMode: this.sortMode,
        onSortChange: (mode: string) => this.onSortChange(mode),

        onSync: () => this.onSync(),
        onLock: () => this.onLock(),
        onAdd: () => {
          this.editing = emptyDraft(CipherType.Login);
        },
        onSelect: (item: VaultItem) => {
          this.selected = item;
        },
        onToggleFavorite: (item: VaultItem) => {
          this.onToggleFavorite(item).catch((e: Error) => {
            this.getUIContext().getPromptAction().showToast({ message: e.message });
          });
        },
        onDelete: (item: VaultItem) => {
          this.onDelete(item).catch((e: Error) => {
            this.getUIContext().getPromptAction().showToast({ message: e.message });
          });
        },
        onBatchFavorite: (items: VaultItem[], favorite: boolean) => {
          this.onBatchFavorite(items, favorite).catch((e: Error) => {
            this.getUIContext().getPromptAction().showToast({ message: e.message });
          });
        },
        onBatchDelete: (items: VaultItem[]) => {
          this.onBatchDelete(items).catch((e: Error) => {
            this.getUIContext().getPromptAction().showToast({ message: e.message });
          });
        }
      })

      if (this.selected !== null) {
        Stack() {
          Column() {
          DetailView({
            item: this.selected as VaultItem,
            folderName: this.folderNameOf(this.selected as VaultItem),
            onCopy: (label: string, value: string) => this.onCopy(label, value),
            onToggleFavorite: () => {
              const target: VaultItem = this.selected as VaultItem;
              const next: boolean = !target.favorite;
              this.onToggleFavorite(target).then(() => {
                // 收藏状态在重新同步后刷新
              }).catch((e: Error) => {
                this.getUIContext().getPromptAction().showToast({ message: e.message });
              });
              target.favorite = next;
              this.selected = target;
            },
            onEdit: () => {
              this.editing = draftFromItem(this.selected as VaultItem);
            },
            onDelete: () => {
              const target: VaultItem = this.selected as VaultItem;
              confirmDanger('移到回收站', `「${target.name}」将被移到回收站，可稍后恢复。`, '移到回收站', () => {
                this.onDelete(target).then(() => {
                  this.selected = null;
                }).catch((e: Error) => {
                  this.getUIContext().getPromptAction().showToast({ message: e.message });
                });
              });
            },
            onClose: () => {
              this.selected = null;
            }
          })
          }
          .width('100%')
          .height('100%')
          .constraintSize({ maxWidth: 860 })
        }
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.BACKGROUND)
      }
    }
    .width('100%')
    .height('100%')

  }
  build() {
    Stack() {
      Tabs({ barPosition: BarPosition.End, index: this.tab }) {
        TabContent() {
          Stack() {
            Column() {
            this.vaultTab()
            }
            .width('100%')
            .height('100%')
            .constraintSize({ maxWidth: 860 })
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.BACKGROUND)
        }
        .tabBar(this.tabItem(0, '保险库', Icons.vault))

        TabContent() {
          Stack() {
            Column() {
            GeneratorView({
              random: (bound: number) => this.random(bound),
              onCopy: (label: string, value: string) => this.onCopy(label, value)
            })
            }
            .width('100%')
            .height('100%')
            .constraintSize({ maxWidth: 860 })
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.BACKGROUND)
        }
        .tabBar(this.tabItem(1, '生成器', Icons.generator))

        TabContent() {
          Stack() {
            Column() {
          TotpView({
            accounts: this.totpAccounts,
            onScan: () => this.onScanTotp(),
            onAddManual: (issuer: string, account: string, secret: string) => {
              this.onAddTotp(issuer, account, secret);
            },
            onDelete: (id: string) => this.onDeleteTotp(id),
            onCopy: (label: string, value: string) => this.onCopy(label, value)
          })
            }
            .width('100%')
            .height('100%')
            .constraintSize({ maxWidth: 860 })
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.BACKGROUND)
        }
        .tabBar(this.tabItem(2, '验证器', Icons.shield))

        TabContent() {
          Stack() {
            Column() {
            SettingsView({
              email: this.email,
              server: this.server,
              syncAt: this.syncAt,
              itemCount: this.items.length,
              demo: this.demo,
              localMode: this.localMode,
              notifyKeepSeconds: this.notifyKeepSeconds,
              trashCount: this.trash.length,
              onSync: () => this.onSync(),
              onLock: () => this.onLock(),
              onOpenFolders: () => {
                this.showFolders = true;
              },
              onOpenTrash: () => {
                this.showTrash = true;
              },
              onOpenBiometric: () => {
                this.showBiometric = true;
              },
              onNotifyKeep: (seconds: number) => this.onNotifyKeep(seconds),
            })
            }
            .width('100%')
            .height('100%')
            .constraintSize({ maxWidth: 860 })
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.BACKGROUND)
        }
        .tabBar(this.tabItem(3, '设置', Icons.settings))
      }
      .barHeight(58 + this.bottomInset)
      .barBackgroundColor(Theme.CARD)
      // 关掉滑动切页：否则覆盖层（详情/编辑器/回收站）的右滑返回会被 Tabs 抢走
      .scrollable(false)
      // 切换动画设为 0，点一下立刻切换，避免蓝色高亮慢半拍
      .animationDuration(0)
      // 点 TabBar 的瞬间就更新高亮，不等页面切换完成
      .onTabBarClick((index: number) => {
        this.tab = index;
        this.selected = null;
      })
      .onChange((index: number) => {
        this.tab = index;
        this.selected = null;
      })
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.BACKGROUND)

      // 编辑器（全屏覆盖）
      if (this.editing !== null) {
        Stack() {
          Column() {
          CipherEditor({
            initial: this.editing as CipherDraft,
            folders: this.folders,
            random: (bound: number) => this.random(bound),
            onClose: () => {
              this.editing = null;
            },
            onSave: (draft: CipherDraft) => this.onSaveDraft(draft).then(() => {
              this.editing = null;
              this.selected = null;
            }),
            onCreateFolder: (name: string) => this.onCreateFolder(name),
            onScanTotpForEditor: () => this.onScanTotpForEditor()
          })
          }
          .width('100%')
          .height('100%')
          .constraintSize({ maxWidth: 860 })
        }
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.BACKGROUND)
      }

      // 文件夹管理（全屏覆盖）
      if (this.showFolders) {
        Stack() {
          Column() {
          FolderView({
            folders: this.folders,
            items: this.items,
            onBack: () => {
              this.showFolders = false;
            },
  
            onDelete: (folder: VaultFolder) => {
              this.onDeleteFolder(folder).catch((e: Error) => {
                this.getUIContext().getPromptAction().showToast({ message: e.message });
              });
            },
            onCopy: (label: string, value: string) => this.onCopy(label, value),
            onToggleFavorite: (item: VaultItem) => {
              this.onToggleFavorite(item).catch((e: Error) => {
                this.getUIContext().getPromptAction().showToast({ message: e.message });
              });
            },
            onEdit: (item: VaultItem) => {
              this.showFolders = false;
              this.tab = 0;
              this.editing = draftFromItem(item);
            },
            onDeleteItem: (item: VaultItem) => {
              this.onDelete(item).catch((e: Error) => {
                this.getUIContext().getPromptAction().showToast({ message: e.message });
              });
            },
            onCreateFolder: (name: string) => {
              this.onCreateFolder(name).catch((e: Error) => {
                this.getUIContext().getPromptAction().showToast({ message: e.message });
              });
            },
            onRenameFolder: (folder: VaultFolder, name: string) => {
              this.onRenameFolder(folder, name).then(() => {
                this.getUIContext().getPromptAction().showToast({ message: '已重命名' });
              }).catch((e: Error) => {
                this.getUIContext().getPromptAction().showToast({ message: e.message });
              });
            },
            onDeleteFolders: (folders: VaultFolder[]) => {
              this.onDeleteFolders(folders).catch((e: Error) => {
                this.getUIContext().getPromptAction().showToast({ message: e.message });
              });
            }
          })
          }
          .width('100%')
          .height('100%')
          .constraintSize({ maxWidth: 860 })
        }
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.BACKGROUND)
      }

      // 生物识别（全屏覆盖）
      if (this.showBiometric) {
        Stack() {
          Column() {
          SecurityView({
            bioFingerprint: this.bioFingerprint,
            bioFace: this.bioFace,
            fpAvailable: this.fpAvailable,
            faceAvailable: this.faceAvailable,
            fpReason: this.fpReason,
            faceReason: this.faceReason,
            bioRev: this.bioRev,
            noScreenshot: this.noScreenshot,
            onToggleNoScreenshot: (on: boolean) => this.onToggleNoScreenshot(on),
            autoLockMinutes: this.autoLockMinutes,
            onAutoLock: (minutes: number) => this.onAutoLock(minutes),
            onBack: () => {
              this.showBiometric = false;
            },
            onToggleBiometric: (kind: string, enable: boolean) => this.onToggleBiometric(kind, enable),
            onChangePassword: () => {
              this.showChangePassword = true;
            },
            localMode: this.localMode,
            onSignOut: () => this.onSignOut(),
            onImported: () => this.onDataChanged()
          })
          }
          .width('100%')
          .height('100%')
          .constraintSize({ maxWidth: 860 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.BACKGROUND)
      }

      // 修改主密码（全屏覆盖）
      if (this.showChangePassword) {
        Stack() {
          Column() {
            ChangePasswordView({
              onBack: () => {
                this.showChangePassword = false;
              }
            })
          }
          .width('100%')
          .height('100%')
          .constraintSize({ maxWidth: 860 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.BACKGROUND)
      }

      // 回收站（全屏覆盖）
      if (this.showTrash) {
        Stack() {
          Column() {
          TrashView({
            items: this.trash,
            onBack: () => {
              this.showTrash = false;
            },
            onRestore: (item: VaultItem) => {
              this.onRestore(item).catch((e: Error) => {
                this.getUIContext().getPromptAction().showToast({ message: e.message });
              });
            },
            onBatchRestore: (items: VaultItem[]) => {
              this.onBatchRestore(items).catch((e: Error) => {
                this.getUIContext().getPromptAction().showToast({ message: e.message });
              });
            },
            onBatchPurge: (items: VaultItem[]) => {
              this.onBatchPurge(items).catch((e: Error) => {
                this.getUIContext().getPromptAction().showToast({ message: e.message });
              });
            },
            onPurge: (item: VaultItem) => {
              this.onPurge(item).catch((e: Error) => {
                this.getUIContext().getPromptAction().showToast({ message: e.message });
              });
            }
          })
          }
          .width('100%')
          .height('100%')
          .constraintSize({ maxWidth: 860 })
        }
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.BACKGROUND)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BACKGROUND)
  }
}
