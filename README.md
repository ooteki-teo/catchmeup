# CatchMeUp

> 原生 macOS 个人任务助理：把截图、文字、文件、文件夹、网址丢进来，自动整理成素材与待办，并帮你记住"上次做到哪、接下来做什么"。

**简体中文** · [English](README.en.md) · [Español](README.es.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

CatchMeUp 是一个**单文件原生 macOS 应用**（SwiftUI + Swift 6），不使用 Electron、不依赖 Python，除 DeepSeek API 外全部在本机完成。

---

## 功能特性

### 统一捕获（微信式，少点击）
- 一个输入框搞定：**文字 / 网址 / 文件路径 / 拖拽文件 / 拖拽文件夹 / 粘贴截图（⌘V）/ 框选截图**，自动识别类型。
- 智能路由：网址自动抓正文、文件路径自动读取、图片自动 OCR 或送视觉模型。
- 全局热键（默认 `⌘⇧M`，**可自定义**）：任意界面框选截图 → 自动唤起 App 并分析。

### AI 整理（DeepSeek）
- 支持多家 AI 提供商：**DeepSeek（默认）**、OpenAI、OpenRouter、Moonshot、Ollama，或任意 OpenAI 兼容端点；默认模型 `deepseek-flash`（支持图片）。
- 自动产出：标题、摘要、标签、分类，以及两种结构化结果：
  - **任务**：带明确时间点的待办；
  - **交接**：项目梳理（目标 / 整体逻辑 / 详细过程 / 接下来做什么 / 风险）。
- 截图优先走视觉模型，失败自动回退到本机 **Vision OCR**（中英文）。
- 目录输入自动整理为「README（有才加）+ 目录树 + 每个文件一句话说明」，不粘贴原文。

### 任务系统（日期分组，一键操作）
- 默认「任务」视图按 **已逾期 / 今天 / 明天 / 本周内 / 以后 / 无日期 / 已完成** 分组。
- 顶部一句话**回车即建**；点圆圈完成、点日期改期、点圆点调优先级。
- 到点本地通知提醒（App 关闭也会响），支持每天 / 每周 / 每月重复。
- 可选把带截止时间的任务写入**系统日历**。

### 任务交接（连续追踪）
- 每条交接素材内置「增量更新」：重新扫描来源 + 回传上次交接，保留有效进展、只补变化。
- 支持 Session 开始 / 结束与一键生成交接摘要，可复制为 Markdown。

### 其他
- 菜单栏常驻：快速记录、截图、剪贴板、即将到期。
- **Token 用量统计**（设置 → DeepSeek），按调用/输入/输出/合计显示，按模型细分。
- API Key 存储在本机应用目录，不使用系统钥匙串，**不弹授权**。
- 所有权限（通知 / 日历 / 屏幕录制）**集中放在设置里，仅在主动点击时申请**，启动不打扰。

---

## 系统要求

- macOS 14.0 或更高（Apple Silicon 已验证）
- Xcode 或 Command Line Tools（提供 Swift 6 工具链）
- 一个 [DeepSeek](https://platform.deepseek.com/) API Key
- 可选：Apple Development 证书（用于稳定的权限记忆，见下文）

---

## 快速开始

```bash
# 构建（release）并打包成 dist/CatchMeUp.app
bash scripts/build.sh

# 运行
open "dist/CatchMeUp.app"

# 测试
bash scripts/test.sh
# 或
swift test
```

首次运行后：

1. 打开「**设置 → DeepSeek**」，填入 API Key，点「保存」。
2. 打开「**设置 → 权限**」，按需点击授权：通知、日历、屏幕录制。
3. 需要时按 `⌘⇧M`（可在「设置 → 通用」修改）框选截图，自动分析。

---

## 使用说明

| 场景 | 操作 |
| --- | --- |
| 记录一段文字 | 工作台输入框输入，回车 |
| 保存网页 | 粘贴网址，回车 |
| 整理一个项目文件夹 | 把文件夹拖进来（自动按「交接」处理） |
| 截图整理 | `⌘⇧M`、相机按钮、或直接 ⌘V 粘贴截图 |
| 看某条素材详情 | 点卡片 → 独立窗口（可移动/缩放，支持「刷新」重新分析） |
| 建/改任务 | 任务页顶部输入回车；行内改期/优先级/完成 |
| 交接进度 | 「任务交接」页生成摘要，或在卡片右上角增量更新 |

---

## 项目结构

```text
catchmeup/
├── Package.swift                 # SwiftPM 清单（macOS 14+，无第三方依赖）
├── Sources/
│   ├── CatchMeUpCore/            # 核心库：模型、存储、AI、OCR、日历、提醒、流水线
│   │   ├── Models.swift          # Item / TaskItem / Session / Handoff 等
│   │   ├── Database.swift        # 基于系统 sqlite3 的持久层
│   │   ├── DeepSeekClient.swift  # DeepSeek 接口 + 提示词 + JSON 解析
│   │   ├── OCR.swift             # Vision 离线 OCR
│   │   ├── Ingest.swift          # 文本/网址/文件/文件夹/截图 读取
│   │   ├── ReminderScheduler.swift # UserNotifications 本地提醒
│   │   ├── CalendarService.swift # EventKit 日历
│   │   ├── Pipeline.swift        # 捕获 → 整理 → 存储 → 提醒/日历
│   │   ├── Secrets.swift         # 本地文件密钥 + 偏好
│   │   └── Usage.swift           # Token 用量统计
│   └── CatchMeUpApp/             # SwiftUI 应用层
│       ├── AppStore.swift        # 状态与业务入口
│       ├── WorkspaceView.swift   # 工作台（统计条 + 输入框 + 素材）
│       ├── TasksView.swift       # 任务系统
│       ├── HandoffView.swift     # 任务交接
│       ├── ItemViews.swift       # 素材卡片/列表组件
│       ├── ComposerView.swift    # 统一输入
│       ├── ComposerTextView.swift# NSTextView 封装（回车发送 / 粘贴拦截）
│       ├── GlobalHotKey.swift    # 全局热键
│       ├── HotKeyUI.swift        # 热键录制控件
│       ├── SettingsView.swift    # 设置
│       └── ...
├── Tests/CatchMeUpCoreTests/     # 单元测试（离线，联网测试需环境变量）
└── scripts/                      # build.sh / test.sh / Info.plist / make-icon.swift
```

---

## 数据与隐私

- 数据目录：`~/Library/Application Support/CatchMeUp/`
  - `catchmeup.db`（SQLite）、`storage/`（附件副本）、`secrets.json`（API Key）、`usage.json`（Token 统计）。
- API Key 存于本机 `secrets.json`（权限 0600），也可用环境变量 `DEEPSEEK_API_KEY` 覆盖。
- 只有在你主动整理内容时才会调用 DeepSeek；其余数据全部留在本机。

---

## 关于权限与签名

macOS 的「屏幕录制」等权限按应用的**代码签名**记住。若用 **ad-hoc 签名**，其指定要求是一个随每次编译变化的 `cdhash`，系统会把每次重编译当成新应用 → 反复弹权限。

`scripts/build.sh` 会优先使用你机器上的 **Apple Development 证书**签名，使权限在重编译后依然有效：

```bash
# 指定签名身份（可选）
CODESIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" bash scripts/build.sh
```

找不到证书时自动回退 ad-hoc（此时重编译后可能需要重新授权）。

---

## 常见问题

**Q：截图时反复要求屏幕录制权限？**
A：用带证书的签名重新构建（见上一节），并到「设置 → 权限」授权一次。ad-hoc 签名在每次重编译后会被系统视为新应用。

**Q：不配置权限能用吗？**
A：可以。只是不会有到点通知、不会写日历、无法截图；整理与任务本身仍可用。

**Q：可以不用 DeepSeek 吗？**
A：目前整理与交接依赖 DeepSeek API；没有 Key 时仍可手动新建/管理任务。

---

## 许可

[MIT](LICENSE)
