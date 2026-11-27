# LockWarden（Vaultwarden HarmonyOS 客户端）

用 **ArkTS / ArkUI** 为华为鸿蒙（HarmonyOS，Stage 模型，SDK 26.0.0 / API 26）编写的
**Vaultwarden 客户端**，包名 `com.***.lockwarden`，在 DevEco Studio 中可直接编译、
自动签名、部署到模拟器或真机。当前版本 **1.3.0**（versionCode 1000004）。

> 先澄清一个前提：**Vaultwarden 本身是服务端，不能被"编译成鸿蒙 App"**（见第 1 节）。
> 本仓库交付的是与之配套的鸿蒙客户端。

---

## 1. 先澄清：Vaultwarden 是服务端，不是 App

> **本机模式**：没有服务器也能用 —— 连接页选「没有服务器？在本机使用」，数据只加密存在设备里，条目/文件夹/回收站/生成器/验证器与服务器模式功能一致。

| | Vaultwarden | 鸿蒙 App |
|---|---|---|
| 形态 | 常驻服务的 HTTP 服务端 | 受 ArkTS 沙箱约束的 UI 应用 |
| 语言/栈 | Rust（axum + diesel + SQLite） | ArkTS / ArkUI |
| 产物 | Linux/Windows 可执行文件、Docker 镜像 | `.hap` 安装包，上架用 `.app` |
| 运行位置 | NAS、云主机、树莓派 | 手机 / 平板 |

`vaultwarden-main/src/main.rs` 启动的是一个监听端口的 axum 服务，全仓库没有一处鸿蒙入口，
所以不存在"把 vaultwarden 仓库编译成一个鸿蒙 App"的路径：

1. **语言层**：鸿蒙应用层只执行 ArkTS 字节码，Rust 代码无法成为应用入口。
2. **运行时层**：即使交叉编译成 `aarch64-unknown-linux-ohos` 的 `.so` 用 NAPI 挂进应用，
   它也只是"库"；要自己做端口监听、常驻后台，而鸿蒙会在切后台/锁屏时冻结进程。
3. **系统层**：手机做服务端还叠加 NAT、动态 IP、耗电与证书问题，即便跑通也不是可用形态。

正确分工：**服务器继续跑 Vaultwarden，手机装本客户端**。

---

## 2. 界面结构（对齐 Bitwarden Android）

底部四个 Tab，与 Bitwarden 安卓客户端的导航结构一致：

| Tab | 内容 |
|---|---|
| **保险库** | 标题栏（同步 / 锁定）→ 搜索框 → 筛选条（全部 / 收藏 / 无文件夹 / 各文件夹）→ 条目列表 → 右下角 `+` |
| **生成器** | 长度滑杆（5–64）、大写/小写/数字/符号开关、一键复制、重新生成 |
| **验证器** | 两步验证动态码列表（详见下方功能表）。原「发送」占位页已按需求移除 |
| **设置** | 账号/服务器/条目数/上次同步/KDF、立即同步、锁定、退出并清空 |

条目行采用 Bitwarden 的样式：**圆形类型头像 + 名称 + 副标题 + 收藏星标**；
类型配色为登录=蓝、笔记=橙、卡片=紫、身份=绿。详情页是字段卡片（用户名/密码/网址），
每行右侧有复制按钮，密码支持明码切换；TOTP 独立成卡，含 30 秒进度条与倒计时。

### 关于图标

图标全部使用**系统矢量符号**（`SymbolGlyph` + `sys.symbol.*`），没有引入任何图片切图：

- 可随状态着色，不必为每种颜色准备一套图；
- 体积极小，且规避了复制第三方美术资源的授权问题（Bitwarden 客户端为 GPL-3.0，
  其图标/插画另有商标约束，不适宜直接搬运）；
- 本项目用到的 24 个符号名都在 SDK 26 上**逐个编译验证过**（不存在的名字会直接编译报错），
  确认可用的有：`magnifyingglass`、`plus`、`gearshape`、`key`、`creditcard`、`person`、
  `doc_text`、`star`、`star_fill`、`eye`、`eye_slash`、`lock`、`chevron_right`、
  `wand_and_stars`、`paperplane`、`arrow_clockwise`、`folder`、`trash`、
  `square_grid_2x2`、`xmark`、`checkmark`、`doc_plaintext`、`rectangle_on_rectangle`、`paperplane_fill`；
  不存在的是：`globe`、`ellipsis`、`doc_on_doc`、`number`、`shield_lefthalf_filled`、`person_crop_circle`。

---

## 3. 已实现 / 未实现

| 已实现 | 说明 |
|---|---|
| 服务器配置 | 真实探测 `GET /api/config`，失败即时反馈 |
| KDF 预取 | `POST /identity/accounts/prelogin` |
| 主密码登录 | 本地派生 → 口令摘要 → `POST /identity/connect/token` |
| 离线解锁 | 仅用主密码解密本地加密账号密钥，MAC 校验即密码校验 |
| 全量同步 | `GET /api/sync`，逐条解密 type-2 EncString |
| 保险库 | 搜索、文件夹筛选、收藏置顶、空态、无法解密态 |
| 条目详情 | 登录/卡片/身份字段、自定义字段、历史密码、密码明码切换、TOTP 实时验证码 |
| 新建 / 编辑 | 四种类型（登录/卡片/身份/笔记）、文件夹归属、收藏、自定义字段；编辑走 `PUT /api/ciphers/<id>` |
| **在编辑器里新建文件夹** | 文件夹行右侧「+ 新建文件夹」→ 输入名称 → 确定，`POST /api/folders` 后立即选中新文件夹；空名称会提示 |
| **文件夹重命名** | 文件夹行右侧「⋯」→ 重命名，或进入文件夹后右上角「管理」→ 重命名文件夹；弹窗预填原名，保存走 `PUT /api/folders/<id>`（名称加密）后重新同步 |

| Argon2id KDF | 支持 PBKDF2-SHA256 与 Argon2id（盐为 SHA-256(邮箱)，NAPI 原生实现） |
| 证书信任 | 首次连接记录服务器证书指纹，证书变化时提示风险并让用户确认 |
| 修改主密码 | 本地重新派生并轮换账号密钥，旧密钥加密的数据迁移后再上报服务器 |
| 条目附件 | 详情页查看附件列表、上传（上限 500MB）、下载、删除；附件密钥/文件名/文件内容全部加密，兼容官方客户端 |
| 收藏 | 详情页一键切换，走 `PUT /api/ciphers/<id>/partial` |
| 删除 / 回收站 | 软删除进回收站（`/delete`）、恢复（`/restore`）、彻底删除（`DELETE`），均带确认弹窗；回收站里条目同样支持左滑：**左「删除」右「恢复」** |
| 密码规则约束 | 生成器（以及编辑器里的魔棒）可设「最少数字个数」「最少特殊字符个数」：先随机填满再把必需字符替换进去并洗牌，两个下限互相联动：抬高一个、另一个自动让位，保证之和不超过长度（长度上限 30）；对应字符集关掉时该行自动置灰并归零；数值做成跟随滑块浮动的小气泡（自己算偏移，不依赖 showTips） |
| 一键生成密码 | 新建/编辑页密码框右侧魔棒，弹出**与「生成器」页同一个面板**（可调长度、大小写/数字/符号） |
| 生成器 | 本地生成强随机密码（真机用 cryptoFramework 随机源） |
| 自定义字段 | 字段名 + 值两行；值旁边有「隐藏」按钮，点了就和密码一样打点，并出现眼睛图标控制明文（Bitwarden 的字段 type=1）；详情页对隐藏字段同样打点 + 眼睛切换 |
| 条目 Logo | 内置 26 个真实品牌 Logo（Google/微软/苹果/亚马逊/GitHub/微信/支付宝/淘宝/百度/QQ/小米/华为/三星/阿里云/Notion/X/Facebook/Netflix/抖音/Gmail/云端硬盘/iCloud/YouTube/B 站/知乎/网易云音乐），SVG 来自 simple-icons（CC0），放在 resources/rawfile/logos，运行时按品牌色着色显示在白底圆上；编辑器输入名称自动匹配（中英文关键词），也可手动选择或「不用」；弹窗顶部有搜索框，支持品牌名 / 中英文关键字（如 google、wechat、微信、淘宝）过滤，无结果会有提示。Logo 存进保留自定义字段 logo（加密同步），展示时被过滤；**没有 Logo 也没有内置品牌的条目，自动用名称首字/首字母生成图标**（取名称第一个字符，颜色由名称哈希稳定生成，中英文都适用） |
| 验证器（TOTP） | 独立 Authenticator：右上角两个圆形图标按钮（同一浅蓝底 + 主色图标）——扫码框（调系统 ScanKit 扫 otpauth 二维码，支持相册）、加号（手动填发行方/账号/密钥）；列表每 30 秒刷新 6 位码、剩余秒数与进度条（≤5s 变红），点击复制，长按删除。账号密钥用 userKey 加密后存本地 preferences（common/TotpStore.ets），不写明文 |
| 外观（深色 / 明亮） | 设置页「外观」三选：跟随系统 / 明亮 / 深色，立即生效并记住选择。颜色统一走 `resources/base|dark/element/color.json` 资源，组件只引用 `Theme.*`，切换时由系统换资源 |
| 应用名 / 图标 | 桌面显示名 **LockWarden**；图标为深夜蓝渐变底（#14223E → #080E1C）+ 盾形锁体（琥珀 #F5B23E、白色粗描边）+ "LW" + 深色钥匙孔。生成脚本：`tools/make_icon_lockwarden.py`（设计）与 `tools/apply_icon_navy.py`（写入资源） |
| 排序方式 | 标题下方左侧的「排序：… ▾」菜单，可选 **按名称 / 按新增时间 / 按修改时间**（时间都是新的在前，同值回落名称），选择会持久化 |
| 列表顺序 | 只按名称（同名的按 id）稳定排序，**收藏不会改变条目位置**；收藏/取消收藏只是打星标 |
| 长按多选 | 保险库/回收站里长按条目进入多选，点按勾选多个；顶部工具条：「删除」单独放最左（防误触），中间「已选 N 项」，右侧「收藏 / 取消 / 全选」三个胶囊按钮；全选只作用于当前筛选结果，取消选择统一走「取消」。保险库：收藏/取消收藏（全已收藏时按钮自动变「取消收藏」）、删除（移到回收站）；回收站：恢复、彻底删除。**多选时按返回键/侧滑只取消选择**，不会退出页面 |
| 同步状态 | 保险库标题下与设置页「上次同步」共用同一套文案：「刚刚同步」（1 分钟内）或「同步完成 2026年11月14日 23:01」，每 30 秒自动刷新；时间按固定 UTC+8 计算，不依赖设备时区 |
| 筛选 chip | 全部 / 收藏 / 「无文件夹」+ 各文件夹；**没有未归入文件夹的条目时「无文件夹」自动隐藏**（正在用该筛选时保留，避免筛选项消失） |
| 文件夹管理 | 列表显示文件夹与条目数，右上角圆形「+」按钮可建文件夹（弹窗内输入名称，聚焦创建）；点进去**在本页内**查看该文件夹的条目（与保险库同款列表 + 搜索），点条目也**在本页内**打开详情（返回栏显示「文件夹」）；删除入口在详情页右上角「管理」菜单；**文件夹卡片支持长按多选**（工具条：删除 / 已选 N 项 / 取消 / 全选），批量删除时里面的条目一并移到回收站 |
| 左滑快捷操作 | 列表行左滑露出两个按钮：**收藏**（橙黄 `#F5A623`，已收藏时显示「取消收藏」）与**删除**（红 `#E84026`，移到回收站），按钮带图标 + 文字，操作后自动收起 |
| 自动锁定 | 设置里用下拉选择：从不 / 1 / 5 / 10 / 15 / 30 分钟 / 1 / 2 / 4 / 6 小时，前台空闲计时到点自动锁定 |
| **生物识别解锁（指纹 / 面容分开）** | 设置页两个独立开关，各自校验各自开启；账号密钥用 HUKS 设备密钥加密留存（两种方式共用同一份包裹）。解锁页：**只开一种时自动拉起该方式**；两种都开时不预选，显示「请选择验证方式」+ 对应的两个按钮，用户点了才发起认证 |
| 会话安全 | 手动锁定、退出清空、refresh_token 轮换 |

**未实现**：组织共享条目（需 RSA 私钥）、**Send**、双因子登录、密码历史回滚、**用户名生成器**。

生物识别相关的前提与边界：

- 设备未录入面容/指纹时，设置页的开关是禁用态并提示"本机未录入面容或指纹"；
- 生物识别失败或取消会退回主密码输入，不会把人挡在门外；
- 更换设备、清除应用数据、关闭生物识别都会让 HUKS 密钥失效，需要重新用主密码登录并重新开启。

---

## 4. 目录结构

```
LockWarden/
├─ AppScope/app.json5               # bundleName: com.***.lockwarden
├─ entry/src/main/
│  ├─ module.json5                  # INTERNET 等权限
│  ├─ ets/
│  │  ├─ entryability/EntryAbility.ets
│  │  ├─ pages/
│  │  │  ├─ Index.ets               # 真机入口：阶段状态机 + 数据注入
│  │  ├─ common/
│  │  │  ├─ CryptoUtils.ets         # PBKDF2 / HMAC / HKDF-Expand / AES-CBC
│  │  │  ├─ BitwardenCrypto.ets     # 密钥层级、EncString 加解密
│  │  │  ├─ Api.ets                 # HTTP 客户端
│  │  │  ├─ VaultStore.ets          # 会话/同步/解密/本地持久化
│  │  │  ├─ Models.ets              # 与服务端 JSON 对应的模型
│  │  │  ├─ Totp.ets                # 纯 ArkTS 的 SHA-1/HMAC（RFC 6238）
│  │  │  ├─ PasswordGenerator.ets   # 密码生成算法（生成器页与新建条目页共用）
│  │  │  ├─ Clipboard.ets           # 只在真机入口引用的剪贴板封装
│  │  │  ├─ Icons.ets               # 系统符号与类型配色映射
│  │  │  ├─ DemoData.ets            # 演示数据
│  │  │  └─ Theme.ets
│  │  └─ view/
│  │     ├─ MainShell.ets           # 底部四 Tab 外壳（真机/预览共用）
│  │     ├─ PasswordGeneratorPanel.ets  # 密码生成面板（生成器页与编辑器弹层共用）
│  │     ├─ EyeToggle.ets           # 自绘卡通眼睛（密码可见性切换，三处复用）
│  │     ├─ VaultView.ets  DetailView.ets
│  │     ├─ CipherEditor.ets        # 新建/编辑（四种类型、文件夹、收藏、自定义字段）
│  │     ├─ TrashView.ets           # 回收站（恢复 / 彻底删除）
│  │     └─ GeneratorView.ets  SendView.ets  SettingsView.ets
│  └─ resources/
└─ tools/build.ps1                  # 命令行构建（等价 DevEco 的 Build Hap）
```

设计上刻意让 **view 层不直接依赖网络/存储/加密**：数据与动作（复制、随机数、保存）
都通过属性注入，`pages/Index` 只负责装配与路由。

> 早期为 DevEco 预览器准备过 `pages/PreviewDemo.ets`（预览器没有 cryptoFramework，直接预览 Index 会失败）。
> 提交审核前该页已从应用里移除（多一个 `@Entry` 页面对审核没好处），源码归档在 `tools/PreviewDemo.ets.txt`，
> 需要预览时把它拷回 `entry/src/main/ets/pages/` 并在 `main_pages.json` 里登记即可。

---

### 4.1 共用组件（避免重复实现）

| 文件 | 作用 |
|---|---|
| `view/CopyButton.ets` | 浅蓝圆底复制按钮：详情页 4 处 + 验证器页共用 |
| `view/Pill.ets` | 多选工具条胶囊按钮（删除 / 收藏 / 取消 / 全选） |
| `common/Dialog.ets` | `confirmDanger()`：取消 + 危险操作两键确认框，7 处删除确认共用 |
| `view/SwipeActions.ets` | 条目左滑按钮（两个可配置按钮）：保险库与文件夹内条目（**删除红在左 / 收藏橙黄在右**，避免误触删除）、回收站（删除红在左 / 恢复绿在右）三处共用 |
| `common/PrivacyMode.ets` | 不允许截图：`setWindowPrivacyMode`（已声明 `ohos.permission.PRIVACY_WINDOW`），选择持久化 |
| `common/WindowStyle.ets` | 全屏布局 + 系统栏配色：TabBar 铺到屏幕底部，状态栏/导航条按深浅色调整，避免底部多出一条灰边 |
| `common/ThemeMode.ets` | 外观模式（跟随系统 / 明亮 / 深色）：存 preferences，调 `applicationContext.setColorMode()` |
| `view/SecurityView.ets` | 安全子页：两节——「生物识别」（指纹 / 面容开关）与「隐私」（不允许截图），设置页只留一行「安全」入口 + 状态摘要 |
| `common/FolderBridge.ets` | 文件夹页的分层返回：条目详情 → 文件夹列表 → 关页面，供 `MainShell.handleBack()` 询问 |
| `view/LogoBits.ets` | `BrandAvatar`（品牌 / 自定义 / 首字三态头像）与 Logo 选择弹窗 |
## 4.2 多设备（手机 / 平板 / 分屏）

| 项 | 配置 |
|---|---|
| 设备类型 | `entry/module.json5` → `deviceTypes: ["phone", "tablet"]` |
| 窗口模式 | `supportWindowMode: ["fullscreen", "split", "floating"]`，支持平板分屏与悬浮窗 |
| 宽屏适配 | 四个 Tab 内容与全部覆盖层（详情 / 编辑器 / 回收站 / 文件夹）加 `constraintSize({ maxWidth: 860 })` 居中；连接服务器页与解锁页用 `Stack + Column(maxWidth: 560)` 居中，平板上表单不会被拉满屏 |
| 方向 | 未锁定方向，跟随系统（平板横屏、分屏拖动都正常重排） |
## 5. 编译、签名与部署

### 5.1 命令行编译

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1
```

自动把 DevEco 的 JBR、Node 加入 PATH 并设置 `DEVECO_SDK_HOME`。
已验证：DevEco Studio 26.0.0.865（DS-261）、SDK 26.0.0 / API 26、hvigor 6.26.9。

### 5.2 签名（本地配置，不入库）

仓库中的 `build-profile.json5` 是脱敏模板：`signingConfigs` 为空，不包含证书、Profile、密钥库或口令。

签名材料只保留在本地，分两套：

| 配置 | 用途 | 要求 |
|---|---|---|
| `default` | 调试安装、`hdc install` | 调试证书 + 调试 Profile；Profile 登记目标设备 UDID，并包含 `ohos.permission.USE_FLOAT_BALL` ACL |
| `release` | 上架 AGC | 发布证书 + 发布 Profile；包含 `USE_FLOAT_BALL` ACL |

配置方式：

1. DevEco：`File → Project Structure → Signing Configs`，选择自己的 p12、证书、Profile。
2. 命令行：复制 `docs/signing.example.json5` 为 `signing.local.json5`（已被 `.gitignore` 排除），填入本地路径，再把 `signingConfigs` 合并到 `build-profile.json5`。

注意：

- `build-profile.json5` 里的密码字段即使由 DevEco 加密，也属于本机凭据，不要提交；
- 换机器、换证书或换 Profile 后重新选择一次；
- `hdc install` 报 `9568322` 通常是用发布证书装了调试包，调试安装请使用 `default` 产品（`tools/build.ps1` 不带 `-Release`）。

### 5.3 在 DevEco 里预览（不需要设备）

**直接预览 `pages/Index.ets` 会失败**，报「预览失败：不支持或编译错误」——不是代码错误。
预览器只内置 `preferences / fs / http / util` 等少量系统模块，
**没有 `security`（cryptoFramework）与 `pasteboard`**，而真机入口会静态导入它们，
模块加载阶段就抛异常，IDE 只能给出笼统提示。

正确姿势：把 `tools/PreviewDemo.ets.txt` 拷回 `entry/src/main/ets/pages/PreviewDemo.ets`，
在 `main_pages.json` 的 `src` 里加上 `"pages/PreviewDemo"` → 打开该文件 → 点右上角 **Previewer** →
确认面板顶部页面是 `pages/PreviewDemo`。它会渲染同一个 `MainShell`：
四个 Tab、列表、详情、TOTP 都能看（复制会退化为 Toast 提示）。

已用脚本核对：预览链路（PreviewDemo → MainShell → 各 view）**零 `@kit`/`@ohos` 导入**。

---

### 5.4 打包发布（提交审核）

前置条件：`build-profile.json5` 的 `release` 产品中启用：

```json5
"buildOption": {
  "packOptions": {
    "appWithSignedPkg": true
  }
}
```

否则 hvigor 会把**未签名 HAP** 打进 `.app`，AGC 上传会报 993。

出包：

```powershell
# 方式一：直接构建，产物在 build\outputs\release\
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1 -Clean -Release -App
# 上传用：build\outputs\release\LockWarden-release-all-signed.app

# 方式二：构建 + 校验 + 复制到 dist（推荐）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\release.ps1
# 产物：dist\LockWarden-<version>-release-signed.app
```

注意：

- 只上传 `LockWarden-release-all-signed.app` / `dist` 里的文件；
  `LockWarden-release-signed.app` 内部是**未签名 HAP**，不要上传；
- `-Release` 使用发布证书；不带 `-Release` 使用调试证书，可直接 `hdc install`；
- 每次提交审核 `versionCode` 必须递增，`versionName` 同步修改；
- 上传前可执行 `hap-sign-tool verify-app -inFile <app> -inForm zip` 确认返回 `verify-app success`。

## 6. 安全设计

- 主密码不出本机；PBKDF2-SHA256 与 Argon2id 均在本地派生，上行是摘要。
- 落盘内容：服务器地址、邮箱、KDF 参数、设备 ID，以及
  `encUserKey`（用拉伸密钥加密的账号密钥）与 `encRefreshToken`（用账号密钥加密的 refresh_token）。
  主密码、主密钥、明文 refresh_token、明文条目都不落盘。
- 解密前先校 HMAC，用定长比较避免时序侧信道。
- 服务器证书首次信任后记录指纹，后续变化会提示风险；附件文件名、附件密钥和文件内容分别加密。
- 退出登录：清空 preferences 并删除同步缓存文件。
- 生成器随机源在真机上走 `cryptoFramework`，不是 `Math.random()`。
- **生物识别**：开启时先过系统 `userAuth` 校验，再用 **HUKS**（TEE 内生成、不可导出的 AES-256）
  把账号密钥加密后落盘；解锁时先过系统校验，再调 HUKS 解密。主密码、拉伸密钥仍然不落盘。
  当前是"设备绑定 HUKS 密钥 + 应用层生物识别闸门"，尚未把 HUKS 密钥绑定到具体生物特征
  （`HUKS_TAG_USER_AUTH_TYPE` + auth token）；要连应用自身都无法绕过，按该方式加固即可。

后续可加固：把 `encUserKey`/`encRefreshToken` 也迁到 HUKS。

---

## 7. 已知限制

1. 组织共享条目无法解密（需要 RSA 私钥），显示"无法解密"。
2. 未实现 2FA 登录、Send、密码历史回滚、用户名生成器。
3. 附件单文件上限 500MB；上传时客户端会把文件读入内存再加密，极大文件受设备可用内存限制。
4. 自签 HTTPS 证书需要先加入系统信任；证书变化会触发首次信任提示。

## 8. 验证情况

- **编译**：`tools\build.ps1` 通过，产出 debug/release HAP。
- **签名**：release `.app` 内外层 `hap-sign-tool verify-app` 均为 `verify-app success`。
- **设备**：1.3.0 已安装并启动于模拟器（Mate ***，API 26），版本号确认为 `1.3.0`。
- **附件**：真实 Vaultwarden 服务端验证 1B / 1KB / 256KB / 2MB / 8MB 上传下载字节一致；
  中文、空格、emoji 文件名正常；多附件、逐个下载、删除计数正确；
  16MB 下载保存框 0.9 秒内弹出，文件完整落盘。
- **协议/密码学**：PBKDF2 600k 迭代、Argon2id、TOTP、密码生成器均有独立脚本对照测试。
- **界面**：保险库、详情、文件夹、回收站、生成器、验证器、设置、深浅色、多设备布局均已跑通；
  闪控球在支持 ACL 的设备上验证，不支持时自动改用通知。

### 开发注意（已踩过的坑）
1. **不要用 `@Builder` 的按值参数承载状态**。`@Builder` 参数按值传递时不会触发刷新，
   表现为"点了没反应"：生成器的勾选框、保险库的筛选 chip、详情页的操作条都因此失效。
   现已改为独立组件（`@Prop` + 回调），见 `CheckToggle`、`FilterChip`、`FieldCard`、`ActionButton`、
   `SettingsInfoRow`、`SettingsActionRow`（后者曾导致"回收站数量/条目数量"不刷新），
   并给勾选框加了 160ms 的透明度/缩放过渡。
2. **生成器不允许把字符类型全关**。之前的做法是静默把"小写"重新打开，看起来就是"点了没反应"；
   现在改为弹出"至少要保留一种字符类型"并保持勾选。
3. **`TextInput` 在 `InputType.Password` 下自带一个可见性按钮**，若自己也画一个就会出现两个眼睛图标；
   需要 `showPasswordIcon(false)` 关掉内置的。
4. 预览器没有 `cryptoFramework` / `pasteboard`，所以视图层的复制、随机数、保存都是注入的。
5. **系统符号 `sys.symbol.eye` 偏拟真**，与圆润界面不协调；密码可见性按钮改为自绘卡通眼
   （椭圆眼白 + 瞳孔 + 高光，明文态叠圆头斜杠），见 `view/EyeToggle.ets`，
   在登录页、编辑器、详情页三处复用。
   解锁页顶部的锁也换成系统线性图标 `sys.symbol.lock`（原来的 emoji 太拟真），
   两个生物识别按钮分别用 `sys.symbol.touchid`（指纹）和 `sys.symbol.face`（面容）。
6. **侧滑返回必须自己接管**。`@Entry` 不实现 `onBackPress` 时，系统侧滑/返回键会直接退出应用；
   现在 `pages/Index.onBackPress` 经 `common/BackBus.ets` 分发到 `MainShell`，
   按 **编辑器 → 多选取消 → 详情 → 回收站** 的顺序退层，退到底才交还系统（多选状态通过 `common/SelectionBridge.ets` 让外壳感知）。
   **编辑器关闭前会检查未保存改动**：有改动弹「放弃更改？」（继续编辑 / 放弃），
   没改动直接关；判断与弹窗都在编辑器内部，外壳通过 `common/EditorBridge.ets` 请求关闭。
7. **覆盖层内的横向手势会被 `Tabs` 的滑动切页吃掉**。因此 `Tabs` 设了 `.scrollable(false)`
   （切页只走底部导航），覆盖层才能用 `parallelGesture` 收到"右滑返回"；
   覆盖层（详情/编辑器/回收站）在任意位置横向右滑 > 120vp 即返回上一层。
8. **HUKS 的三个坑**（都已在 `BioKeyStore.ets` 处理）：
   键不存在时 `isKeyItemExist` 会**抛错**而不是返回 false；`initSession` 必须重复声明
   `ALGORITHM`/`KEY_SIZE`/`BLOCK_MODE`/`PADDING`/`IV`，只给 `PURPOSE` 会报 `Invalid parameters`；
   `updateSession`/`finishSession` 可能返回 **null**，必须判空再取 `outData`。
9. **`userAuth` 的回调是接口不是函数**：`on('result', ...)` 要传 `IAuthCallback` 对象
   （`{ onResult: (r) => {...} }`），直接传箭头函数会报"无重载匹配"。
10. **生物识别必须声明 `ohos.permission.ACCESS_BIOMETRIC`**（system_grant/normal，声明即授予）。
    漏声明时 `getAvailableStatus`/`getEnrolledState`/`start` 全部失败，
    界面表现就是"开关永远禁用、点了没反应"。
11. **`AuthParam.authType` 只能放一个类型**：同时传 `[FACE, FINGERPRINT]` 时系统直接拒绝，
    回调返回 `result=401` 且不弹窗；只传 `[FINGERPRINT]`（或 `[FACE]`）即可正常弹出。
    现在的策略是"有指纹优先指纹，否则面容"。
12. **认证面板需要 `WidgetParam.uiContext`**，入口页启动时把 `UIAbilityContext` 注入 `Biometric`
    才稳定；否则面板可能不显示。
13. **受控开关要防"程序回写"**：`Toggle` 用 `$$` 绑内部状态时，父组件把值改回来也会触发一次
    `onChange`，必须在回调里判断 `value === this.on` 直接返回，否则会重复触发业务逻辑；
    另外父组件每次尝试后递增一个 `rev` 并配 `@Watch`，才能在"值没变但需要回弹"时把开关拉回真实状态。
14. **列表的 `ForEach` key 要带内容版本**：只用 `item.id` 时条目被复用，编辑保存后列表里仍是**旧的 item 对象**，
    点进详情会看到保存前的值（网址/备注/自定义字段"保存了但没显示"就是这么来的）。
    现在三处列表的 key 都带上 `item.revisionDate`，保存后行会重建、详情读到最新数据。
15. **`swipeAction` 里的自定义按钮**：用 `Column + onClick` 不触发，必须用 `Button` 承载；
    操作完要调 `ListScroller.closeAllSwipeActions()` 收起（`Scroller` 没有该方法，得声明成 `ListScroller`）；
    另外 builder 里拿到的是**创建时的旧 item 对象**，`favorite` 等状态可能已过期，
    必须按 `item.id` 回列表里取当前对象再操作，否则"取消收藏"会被旧值又设回收藏；
    最后把 `ForEach` 的 key 带上状态（`${item.id}:${item.favorite ? 1 : 0}`），
    否则 ListItem 被复用、左滑按钮的文案会停留在旧值（已收藏却仍显示"收藏"）。
16. **启动即拉起生物识别要延时，且别用捕获的常量**：`aboutToAppear` 里直接 `start`
    常因窗口还没拿到焦点被系统静默拒绝；应延时约 500ms，并在回调里读 `this.xxx`，
    否则会读到 `@Prop` 尚未就绪的旧值（实测会误判成"只开了面容"而自动弹面容）。
17. **覆盖层内部的"分层返回"要用总线**：文件夹页自身有两级（条目详情 → 文件夹列表），
    但系统返回键只到 `MainShell.handleBack()`，它只知道"覆盖层开着"，会直接把整页关掉（回到设置）。
    解决：`common/FolderBridge.ets` 注册一个 `stepBack()`，`handleBack` 里先问它一句：
    ```ts
    if (this.showFolders) {
      if (!FolderBridge.close()) { this.showFolders = false; }
      return true;
    }
    ```
18. **自定义组件上的 `constraintSize` 在平板/宽屏不可靠**：`FolderView({...}).constraintSize({ maxWidth: 860 })`
    不生效，内部 `width('100%')` 仍按整屏算，页面会糊到屏幕边缘。必须用容器包一层：
    ```ts
    Stack() {
      Column() { FolderView({...}) }
        .width('100%').height('100%').constraintSize({ maxWidth: 860 })
    }
    .width('100%').height('100%')
    .backgroundColor(Theme.BACKGROUND)   // 铺满全屏，否则底下 TabBar 会在两侧露白块
    ```
19. **横向 `Scroll` 会居中它里面的 `Row`**：筛选标签（全部/收藏/登陆）在平板上会漂到屏幕中间。
    但不能无脑加 `.align(Alignment.TopStart)`——手机上原本是居中的，改成下面这样按屏幕宽度切换：
    ```ts
    this.wide = display.getDefaultDisplaySync().width / densityPixels > 860;  // 与内容列宽上限一致
    ...
    .align(this.wide ? Alignment.TopStart : Alignment.Center)
    ```
    手机 1260px / 3.25 ≈ 388vp → 居中（保持原样）；平板 2560px / 2.0 = 1280vp → 靠左。


20. **文件夹改名后列表不刷新**：文件夹列表的 `ForEach` key 只有 `folder.id`，改名后 id 不变、行被复用，界面停在旧名字，退出再进才变。key 里要带上会变的字段（`${folder.id}:${folder.name}`），`VaultView` 的文件夹 chip 和编辑器里的文件夹选择器同理。
---

## 9. 来源与许可

- 协议依据：`dani-garcia/vaultwarden`（AGPL-3.0），仅放在 `third_party/` 供比对接口，
  客户端代码为独立实现，未复制其源码。
- 界面参考 Bitwarden Android 的**布局结构**，图标使用鸿蒙系统矢量符号，不复制其美术资源。

### 字体策略（结论）

应用**不设置任何 `fontFamily`**，一律使用系统默认字体（未改主题时即 HarmonyOS Sans，开源可免费商用）。

实测结论（HarmonyOS 26 / Mate 60 Pro，系统主题字体为「书宋-简」）：

- `getSystemFontList()` 能读到主题字体（`书宋-简`，`/system/fonts/ShuS-SC.ttf`）；
- 但 `Text.fontFamily('书宋-简')` **不生效**，`registerFont({familySrc: 'file:///system/fonts/...'})` 后引用同样不生效；
- 官方文档说明主题字体只能通过 ArkGraphics2D 的 `text.FontCollection.getGlobalInstance()` + `ParagraphBuilder` 使用，
  不能用于 ArkUI 的 `Text` 组件（见 https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/theme-font-arkts ）。

因此「跟随用户主题字体」在 ArkUI 层做不到；保持不设置字体 = 用户没改主题时用鸿蒙开源字体，改过主题时应用内仍是系统默认字体。
