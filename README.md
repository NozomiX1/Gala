<p align="center">
  <img src="Gala/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Gala">
</p>

<h1 align="center">Gala</h1>

<p align="center">
  macOS 原生 Galgame 启动器<br>
  添加游戏，点击启动。Wine 配置、字体、引擎适配全部自动完成。
</p>

---

> **开发动机**：这个项目的起因是想在 Mac 上玩[秽翼のユースティア](https://vndb.org/v3770)。
>
> **测试声明**：目前只测试了两款游戏（秽翼のユースティア / BGI 引擎、千恋万花 / KiriKiri 引擎），兼容性数据非常有限。如果你测试了其他游戏，无论成功还是失败，都欢迎[提 Issue](https://github.com/NozomiX1/Gala/issues) 反馈。

## 已知问题

测试环境：M1 Pro MacBook Pro

**千恋万花（KiriKiri）** — 体验良好，字体可修改，未发现明显问题。

**秽翼のユースティア（BGI）** — 已完整通关，可正常游玩，但存在以下问题：
- 启动加载较慢（~40s），详见下方性能分析
- 字体无法修改（BGI 引擎限制）
- 少数场景切换时音频加载会卡住数秒（游戏呈现假死状态，等待后恢复）
- OP 动画未播放（被跳过）

**通用问题**：
- Wine 运行时有一定 CPU 占用，在被动散热机型（MacBook Air 等）上的表现未知，欢迎反馈

## 功能

- **一键启动** — 自动配置 Wine 前缀、中日文 locale / codepage / 字体
- **引擎识别** — 自动检测 KiriKiri、SiglusEngine、CatSystem2、BGI 等 10+ 引擎，应用最佳 Wine 预设
- **VNDB 集成** — 搜索匹配游戏，自动拉取封面、简介、标签和评分
- **游戏库管理** — 网格视图，支持搜索、收藏、右键菜单快捷操作
- **游戏时间统计** — 自动记录游玩时长
- **原生引擎支持** — Ren'Py / RPG Maker / Unity 游戏无需 Wine，直接原生启动
- **非 ASCII 路径** — 中日文游戏目录通过 Wine 驱动器映射自动处理

## 截图

> TODO

## 系统要求

- macOS 14 (Sonoma) 或更高版本
- Apple Silicon Mac (M1+)

## 安装

1. 下载 [Gala.dmg](https://github.com/NozomiX1/Gala/releases/latest)，打开后将 Gala 拖入 Applications
2. 前往访达 → 应用程序，双击 Gala 启动（首次需确认打开）
3. 首次启动自动下载 Wine 和 CJK 字体

## 构建

```bash
open Gala.xcodeproj
# Xcode → Build & Run
```

## 依赖

首次启动时**自动下载**，无需手动安装：

| 依赖 | 版本 | 用途 | 许可证 |
|------|------|------|--------|
| [Wine Staging](https://github.com/Gcenx/macOS_Wine_builds) | 11.4 (Gcenx) | 运行 Windows exe | LGPL |
| [思源黑体](https://github.com/adobe-fonts/source-han-sans) | Regular | Wine CJK 字体渲染 | OFL 1.1 |

可选：[winetricks](https://github.com/Winetricks/winetricks) — 部分引擎预设需要安装额外 Windows 组件。

## 工作原理

Gala 封装 Wine Staging 运行 Windows 视觉小说。每个游戏拥有独立的 Wine 前缀（bottle），根据游戏语言自动配置 codepage 和字体映射：

- **中文游戏** — GBK (936)
- **日文游戏** — Shift-JIS (932)

## 架构

```
Gala/           SwiftUI 应用（Views, ViewModels）
GalaKit/        Swift Package — Wine 管理、引擎检测、VNDB 客户端
```

## 性能分析

### 启动时间实测

| 游戏 | 引擎 | 启动总时间 | 说明 |
|------|------|-----------|------|
| 秽翼のユースティア | BGI | ~40s | 7s 启动器 + 33s 引擎初始化 |
| 千恋万花 | KiriKiri | ~20s | 较轻量的初始化 |

Gala 自身的代码路径几乎为零开销（resolve + fork 约 16ms）。瓶颈在于游戏引擎的 x86 代码经过两层翻译：Wine（Win32→POSIX）+ Rosetta 2（x86→ARM）。

### BGI 引擎 40s 启动分解

| 阶段 | 耗时 | 可优化？ |
|------|------|----------|
| Wine 基础设施 | ~2s | 微小 |
| wineserver 序列化 | ~12s | 理论上可以（极难） |
| MoltenVK 双重初始化 | ~1.5s | 可以（winevulkan=d） |
| **引擎内部 x86 代码（黑洞）** | **14.9s** | **不可能 — Rosetta 2 极限** |
| DirectSound 83 个缓冲区创建 | ~4.7s | 有限 |
| 其他 | ~5s | 部分 |

14.9s 的「黑洞」期间 BGI 在做引擎内部初始化（加载游戏数据、建立 GDI 渲染表面），没有任何 Wine API 调用，完全是 Rosetta 2 翻译 x86 代码的开销。

### 可行但收益有限的优化（未实施）

经过详细 profiling，以下优化理论可行但收益太小（总计仅 3-4s），未纳入代码：

| 优化项 | 理论节省 | 原理 |
|--------|----------|------|
| wineserver 常驻 | ~2s | 免去冷启动初始化 |
| `winevulkan=d` | ~1.5s | BGI 是纯 GDI，跳过无用的 MoltenVK 探测 |
| 禁用不必要的 Wine 服务 | ~0.5s | plugplay/svchost/rpcss 对 VN 引擎无用 |
| 跳过失败音频驱动 | ~0.1s | macOS 上 pulse/alsa/oss 必定失败 |

即使全部实施也只能从 40s 降到 ~36s，用户体感改善有限，且增加维护复杂度。

### 排除的优化方案

**魔改 Wine（fork/recompile）**：编译一次 60-75 分钟，Wine Staging 254 个补丁每两周需要 rebase，维护成本相当于全职工作。参考 Proton-GE（个人维护者）和 CrossOver（整个公司 + Valve 资助）。

**DLL 替换**：Wine 的 WINEDLLOVERRIDES 机制可以无需重编译替换 DLL，但 BGI 引擎是纯 GDI 渲染（91万行 trace 实测：GDI 调用 90.8%，DirectDraw 调用 0%），所以 cnc-ddraw、DXVK、D3DMetal 等替换 DLL 全部无效。KiriKiri 使用 DirectDraw，cnc-ddraw 可能有效但仅改善帧渲染，不影响启动时间。

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

所有 GPTK 版本（1.0–3.0）使用相同的 Wine 7.7 基础，D3DMetal 版本号的升级不影响 Wine 层。几乎所有商业日系 galgame 都是 32-bit PE32 可执行文件，因此 **Wine Staging 11.4（Gcenx 构建）是目前唯一可行的方案**。

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
