<p align="center">
  <img src="Gala/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Gala">
</p>

<h1 align="center">Gala</h1>

<p align="center">
  macOS 原生 Galgame 启动器<br>
  添加游戏，配置环境，点击启动。Wine、字体、引擎适配全部自动完成。
</p>

---

> **开发动机**：这个项目的起因是想在 Mac 上玩[秽翼のユースティア](https://vndb.org/v3770)。
>
> **测试声明**：目前只测试了少量游戏（BGI、Leaf/AQUAPLUS、KiriKiri、Ikura GDL / Family Project、Artemis D3D11），兼容性数据仍然有限。如果你测试了其他游戏，无论成功还是失败，都欢迎[提 Issue](https://github.com/NozomiX1/Gala/issues) 反馈。

## 测试情况与已知问题

测试环境：M1 Pro MacBook Pro，Wine Staging 11.6

| 游戏 | 引擎 | 状态 |
|------|------|------|
| 秽翼のユースティア | BGI/Ethornell | 已完整通关；启动和 OP 播放正常；字体无法修改，少数场景切换时音频加载会卡住数秒 |
| 大図書館の羊飼い | BGI/Ethornell | 启动和 OP 播放正常；使用 `common` profile |
| WHITE ALBUM2 | Leaf/AQUAPLUS | 启动、字体、OP/视频播放正常 |
| 家族計画 追憶 | Ikura GDL / Family Project | 启动和 OP 播放正常；使用独立 `do-kizunar` profile |
| 千恋万花 | KiriKiri | 体验良好，字体可修改，未发现明显问题 |
| 甜蜜女友3 / アマカノ3 | Artemis D3D11 / iarsys | 启动、开屏动画和 OP 播放正常；使用独立 `artemis-mf-d3d11` profile、DXMT 与 Media Foundation 媒体兼容缓存 |

- Wine 运行时有一定 CPU 占用，在被动散热机型（MacBook Air 等）上的表现未知，欢迎反馈

## 功能

- **显式运行环境** — 添加游戏后按需配置 Wine 前缀、中日文 locale / codepage / 字体
- **运行环境检查与修复** — 检查 Wine、字体、辅助工具和 bottle 状态，缺失时可重新下载
- **手动更新检查** — 从 GitHub Releases 检查新版本，查看更新说明并打开最新 DMG
- **引擎识别** — 自动检测 KiriKiri、BGI、Leaf/AQUAPLUS、Artemis、SiglusEngine 等 10+ 引擎，本地特征使用打分合并，并用 VNDB release 信息作为保守 fallback
- **VNDB 集成** — 搜索匹配游戏，自动拉取封面、简介、标签和评分
- **游戏库管理** — 网格视图，支持搜索、收藏、移除运行环境和从库中移除
- **空间清理** — 可清理 Wine 配置，或在卸载前清除所有 Gala 本地数据
- **游戏时间统计** — 自动记录游玩时长
- **原生引擎支持** — Ren'Py / RPG Maker / Unity 游戏无需 Wine，直接原生启动
- **非 ASCII 路径** — 中日文游戏目录通过 Wine 驱动器映射自动处理

## 截图

![游戏库](Gala.png)

![秽翼のユースティア 运行中](Eustia.png)

## 系统要求

- macOS 14 (Sonoma) 或更高版本
- Apple Silicon Mac (M1+)

## 安装

1. 下载 [Gala.dmg](https://github.com/NozomiX1/Gala/releases/latest)，打开后将 Gala 拖入 Applications
2. 前往访达 → 应用程序，双击 Gala 启动（首次需确认打开）
3. 首次启动会自动准备 Wine 运行时、CJK 字体和辅助工具，并显示当前下载项目与进度

## 使用指南

1. 首次启动
   - 打开 Gala
   - 等待自动准备 Wine、字体、辅助工具
   - 准备过程中会显示当前下载项目和进度
   - 首次下载建议打开 VPN 或代理；部分依赖来自海外上游，速度可能较慢
   - 如果失败，进入「运行环境」页面点击修复

2. 添加游戏
   - 点击添加
   - 选择游戏目录里的 `.exe`
   - 匹配 VNDB 信息，或者跳过
   - 游戏会先进入库，但还不能直接启动

3. 配置环境
   - 进入游戏详情页
   - 点击「配置环境」
   - Gala 会创建或复用对应的 Wine bottle
   - 首次配置会安装引擎预设，可能下载 DirectShow / LAV / DXMT 等组件，耗时会比较久
   - 配置完成后，按钮会变成「启动」

4. 启动游戏
   - 点击「启动」
   - 游戏运行时按钮会显示「运行中」
   - 原生引擎游戏不需要 Wine，会直接启动

5. 管理游戏
   - 「移除运行环境」会保留游戏记录和游玩时间，只清理运行配置
   - 「从库中移除」会删除库记录、封面和游玩记录
   - 如果 Wine bottle 仍被其他游戏使用，Gala 不会删除这个共享环境

6. 清理与修复
   - 「运行环境」页面可以检查 Wine、字体、辅助工具和 bottle 状态
   - 可以检查 Gala 新版本，并打开最新 DMG 或发布页
   - 缺失依赖可以在这里重新下载
   - 可以清理所有 Wine 配置，让相关游戏回到「配置环境」状态
   - 卸载前可以清除所有 Gala 本地数据，释放 Wine 运行时、bottle、缓存和封面占用的空间

7. 更新 Gala
   - 在「运行环境」页面点击「检查更新」
   - 下载新版 DMG 后退出 Gala
   - 将新版 Gala.app 拖入 Applications 覆盖旧版
   - 覆盖安装只替换应用本体，不会删除 `~/Library/Application Support/Gala` 里的游戏库、游玩时间、收藏、Wine 运行时和 bottle

## 构建

```bash
open Gala.xcodeproj
# Xcode → Build & Run
```

## 依赖

Gala 会自动下载并管理这些运行时依赖：

| 依赖 | 版本 | 用途 | 许可证 |
|------|------|------|--------|
| [Wine Staging](https://github.com/Gcenx/macOS_Wine_builds) | 11.6 (Gcenx) | 运行 Windows exe | LGPL |
| [思源黑体](https://github.com/adobe-fonts/source-han-sans) | Regular | Wine CJK 字体渲染 | OFL 1.1 |
| [winetricks](https://github.com/Winetricks/winetricks) | 20260125 | 安装引擎需要的 Windows 组件 | LGPL |
| cabextract | deps-v1 | 提取 winetricks 需要的 Windows 组件 | GPL |
| [DXMT](https://github.com/3Shain/dxmt) | v0.80 builtin | Artemis/iarsys D3D11 到 Metal 图形层 | MIT |
| Gala MF Runtime | deps-v3 | `artemis-mf-d3d11` 的 GStreamer/FFmpeg 媒体运行时和 WMV 音频缓存工具 | LGPL/GPL 组件组合 |

Wine、字体、`winetricks`、`cabextract`、DXMT 和 Gala MF Runtime 由 Gala 从自己的 release 资产下载，避免用户本机缺少辅助工具或第三方仓库变动时配置失败。DXMT 只会在配置 `artemis-d3d11` / `artemis-mf-d3d11` profile 时下载，并缓存到 Gala 本地目录；Gala MF Runtime 只会在配置 `artemis-mf-d3d11` profile 时下载。普通 `common` / `kirikiri` / `leaf` profile 不会安装它们。部分旧式引擎的 OP/视频播放需要 DirectShow / LAV 组件，Gala 会在创建 bottle 时通过 winetricks 安装这些组件；这些第三方组件由 winetricks 按其上游规则下载，并缓存到 Gala 自己的目录：

```bash
~/Library/Application Support/Gala/Cache/winetricks
```

这个缓存可被不同 bottle 复用，清除所有 Gala 本地数据时会一起删除。如果下载失败，「运行环境」页面会显示缺失，并可一键重新下载。

## 工作原理

Gala 封装 Wine Staging 运行 Windows 视觉小说。Wine 游戏会按运行环境 profile 共享 Wine 前缀（bottle），避免每个游戏都复制一套完整环境。未识别或老式 DirectShow 视频链常见的引擎会落到 `common`，例如 BGI、旧式 Artemis、NScripter、YU-RIS、RealLive、Majiro、AdvHD、QLIE 和 Unknown。需要额外兼容策略的引擎会拆到独立 profile；例如 Leaf/AQUAPLUS 使用 `leaf`，家族计划使用 `do-kizunar`，现代 iarsys/D3D11 Artemis 按媒体链路分到 `artemis-d3d11` 或 `artemis-mf-d3d11` 并使用 DXMT，避免它们的 DLL/图形/视频配置影响 `common` 或彼此污染。每个 bottle 会根据默认中文环境配置 codepage 和字体映射：

- **中文游戏** — GBK (936)
- **日文游戏** — Shift-JIS (932)

每个 Wine bottle 都会安装 Source Han Sans SC Regular，并将常见 Windows CJK / 旧式 UI 字体映射到它，避免中文、日文菜单和系统对话框显示为方框。

添加游戏后，Gala 会先保存游戏库记录。用户需要在详情页点击「配置环境」来创建或复用对应 bottle；配置完成后按钮会变为「启动」。如果清理了 Wine 配置，相关游戏会回到「配置环境」状态。

Gala 更新时不会自动删除游戏库或 Wine bottle。资料库迁移写回前会创建备份；如果读取失败，Gala 会显示错误并避免把现有资料库覆盖成空库。

### 引擎分流规则

Gala 会先检查本地文件特征，例如 XP3、BGI 可执行文件、Leaf/WHITE ALBUM2 文件组、家族计划的 `KIZUNAR`/`kzn_sc` 文件组等。本地识别结果优先级最高，并会合并多个特征打分：单独 XP3 会进入 KiriKiri，但 `iarsys64.dll`、`.pfs`、E-mote DLL 和可执行文件里的 `D3D11CreateDevice` / `D3DCompile` 字符串会把现代 Artemis D3D11 游戏分到专用 profile，避免汉化补丁的 XP3 抢占判断。如果同目录可执行文件还包含 `MFCreateMediaSession`、`MFStartup`、`MF.dll` 或 `MFPlat.DLL` 等 Media Foundation 信号，则进入 `artemis-mf-d3d11`；否则进入 DirectShow 型的 `artemis-d3d11`。

如果本地特征不足，Gala 才会读取 VNDB release 的 `engine` 字段作为 fallback。这个 fallback 只采纳 Windows release，并忽略 patch release，避免主机平台移植版或补丁包把游戏分到错误 profile。

少数 VNDB 引擎名会被额外保护：`Ikura GDL` 只有在本地也检测到家族计划文件时才进入 `do-kizunar`；`AQUAPLUS Engine` 只有在本地也检测到 Leaf/WHITE ALBUM2 文件时才进入 `leaf`。VNDB 的 `Artemis Engine` 只作为旧式 Artemis fallback；`artemis-d3d11` / `artemis-mf-d3d11` 必须由本地 iarsys/D3D11 特征触发。这样可以避免一个宽泛的 VNDB 引擎标签把其他游戏错误地放进特殊 Wine 环境。

当前主要 profile：

| Profile | 适用范围 | 关键配置 |
|---------|----------|----------|
| `common` | BGI、Artemis、NScripter、YU-RIS、RealLive、Majiro、AdvHD、QLIE、Unknown | `quartz` / `amstream` / `lavfilters`，DirectShow `native,builtin`，LAV Audio WMA 开关 |
| `kirikiri` | KiriKiri | 通用视频组件，`quartz=native` |
| `artemis-d3d11` | DirectShow 型 Artemis/iarsys D3D11 游戏，例如 ハミダシクリエイティブ凸 | `d3dcompiler_47=native,builtin`，DXMT Wine 变体，DXMT PE DLL 覆盖，DirectShow/LAV 视频链 |
| `artemis-mf-d3d11` | Media Foundation 型 Artemis/iarsys D3D11 游戏，例如 甜蜜女友3 / アマカノ3 | 独立 DXMT profile，不安装 DirectShow/LAV 预设；启用 Wine MF FFmpeg backend，并为 `movie/*.wmv` 生成只转换音频轨的兼容缓存 |
| `leaf` | Leaf/AQUAPLUS、WHITE ALBUM2 | builtin DirectShow、禁用 Wine 自带 WMA/WMV 解码器、LAV RGB 输出和 WMA 音频 |
| `do-kizunar` | 家族計画 追憶 | builtin `quartz`，`HKCU\Software\DO\KIZUNAR` 指向 `G:\` |

## 卸载与空间清理

macOS 不会在拖拽删除 `Gala.app` 时自动清理应用支持目录。Gala 下载的 Wine 运行时、bottle、字体和工具位于：

```bash
~/Library/Application Support/Gala
```

可以在 Gala 的「运行环境」页面清理 Wine 配置，或在卸载前清除所有 Gala 本地数据。如果已经卸载 Gala，也可以手动删除该目录来彻底释放空间。

清除所有 Gala 本地数据会移除游戏库、封面缓存、Wine 运行时、bottle、字体、辅助工具和 winetricks 缓存。清理完成后，Gala 会显示「重新安装运行环境」和「退出 Gala」两个入口，避免在目录刚被删除后自动触发新的安装流程。

## 架构

```
Gala/           SwiftUI 应用（Views, ViewModels）
GalaKit/        Swift Package — Wine 管理、引擎检测、VNDB 客户端
```

## 兼容性说明

Gala 自身的启动路径开销很小，主要成本来自 Wine 和游戏引擎本身。早期测试中，秽翼のユースティア（BGI）曾出现启动后长时间黑屏、OP 被跳过的问题；后续排查确认，原因是旧式 DirectShow / LAV 视频链路没有正确配置，而不是单纯的引擎初始化慢。

当前旧式视频预设会自动安装 `quartz`、`amstream`、`lavfilters`，覆盖 BGI、KiriKiri、SiglusEngine、旧式 Artemis、NScripter、YU-RIS、RealLive 等依赖旧式视频播放链路的引擎。`common` 会启用 LAV Audio 的 WMA / WMA Pro / WMA Lossless 开关，减少 OP 只有画面没有声音的情况。Leaf/AQUAPLUS 额外使用更严格的 DirectShow / LAV RGB 输出配置，以修复 WHITE ALBUM2 的 OP/视频播放问题。家族计划独立使用 `do-kizunar`，因为它需要 builtin `quartz` 和 D.O. 的安装路径注册表。

现代 Artemis/iarsys D3D11 游戏的黑屏问题不属于 OP/DirectShow 链路；Gala 会为这类游戏在 Wine Staging 11.6 上叠加 DXMT v0.80，并使用原生 `d3dcompiler_47`。其中 Hamidashi 这类 DirectShow/ASF `.dat` 视频会进入 `artemis-d3d11`，甜蜜女友3这类 Media Foundation/WMV 视频会进入 `artemis-mf-d3d11`，避免两类视频链路共用同一个 bottle。

`artemis-mf-d3d11` 额外使用 Gala MF Runtime。启动前，Gala 会在 `~/Library/Application Support/Gala/MediaOverlays/<game-id>` 生成 per-game overlay：非视频资源用符号链接指回原游戏目录，`movie/*.wmv` 保留 WMV3 视频流并只把 WMA/WMA Lossless 音频轨转换为 PCM。原始游戏文件不会被修改；缓存会在源视频文件或 runtime 版本变化后重建。

第一次启动 `artemis-mf-d3d11` 游戏时，Wine / GStreamer 可能会生成媒体插件缓存；甜蜜女友3 的 OP 曾出现声音先播放、画面短暂黑屏后才同步的情况。第二次启动后缓存已存在，音画会恢复同步。

### 排除的方案

**魔改 Wine（fork/recompile）**：编译一次 60-75 分钟，Wine Staging 补丁每两周需要 rebase，维护成本相当于全职工作。参考 Proton-GE（个人维护者）和 CrossOver（整个公司 + Valve 资助）。

**原生引擎移植**：
- krkrsdl2（KiriKiri）：无 XP3 解密、缺少商业插件，README 明确写「不支持商业游戏」
- openbgi（BGI）：仅能运行 1 个试玩版，仍需 DLL 注入真实 BGI.exe
- 所有主流引擎（Artemis、SiglusEngine）均闭源，无法移植

## 为什么不用 GPTK

[Game Porting Toolkit](https://developer.apple.com/game-porting-toolkit/) 的 Wine 基础是 7.7（来自 CrossOver 22.1.1），其 32on64 WoW64 翻译层对日系 VN 引擎有根本性问题：

| 引擎 | 现象 | 根因 |
|------|------|------|
| BGI | 进程运行但窗口永远不出现 | 32on64 层无法处理 BGI 的窗口创建 |
| KiriKiri | 启动时崩溃（virtual.c 断言失败） | 虚拟内存管理器无法处理 KiriKiri 的内存分配模式 |

所有 GPTK 版本（1.0–3.0）使用相同的 Wine 7.7 基础，D3DMetal 版本号的升级不影响 Wine 层。几乎所有商业日系 galgame 都是 32-bit PE32 可执行文件，因此 **Wine Staging 11.6（Gcenx 构建）是目前唯一可行的方案**。

## 日系 Galgame 引擎现状

| 引擎 | 市场份额 | 趋势 | 原生移植 |
|------|----------|------|----------|
| KiriKiri Z | ~30%（~6800 作品） | 稳定，最大 | krkrsdl2 存在但无法运行商业游戏 |
| BGI/Ethornell | ~10-15% | 衰退，无新作 | openbgi 不可用 |
| Artemis | ~5-10% | 快速增长，业界迁移目标 | 闭源，不可能 |
| SiglusEngine | ~3-5% | 稳定（VisualArts 专用） | 无重实现 |
| CatSystem2 | ~3-5% | 缩小 | FelineSystem2 早期阶段 |

值得关注：Artemis 引擎支持 Win/Switch/PS4/PS5/iOS/Android/WebAssembly，若未来推出 64-bit Windows exe，GPTK 路径将重新可行。

## 许可证

MIT
