# Gala

macOS 原生 Galgame（视觉小说）启动器，基于 Wine 运行 Windows 视觉小说。

添加游戏，点击启动。Gala 自动处理 Wine 前缀配置、CJK 语言环境、字体安装和引擎适配。

## 功能

- **一键启动** — 自动配置 Wine 前缀，设置中文/日文 locale、codepage 和字体
- **引擎识别** — 自动检测 KiriKiri、SiglusEngine、CatSystem2、BGI 等 10+ 引擎，应用最佳 Wine 预设
- **VNDB 集成** — 搜索并匹配游戏，自动拉取封面、简介、标签和评分
- **游戏时间统计** — 自动记录游玩时长和最后启动时间
- **游戏库管理** — 网格视图，支持搜索、筛选和排序
- **原生引擎支持** — Ren'Py、RPG Maker MV/MZ、Unity 游戏无需 Wine，直接原生启动
- **非 ASCII 路径支持** — 中文/日文游戏目录自动通过 Wine 驱动器映射处理

## 系统要求

- macOS 14 (Sonoma) 或更高版本
- Apple Silicon Mac (M1 或更高)

## 依赖

以下依赖由 Gala 在首次启动时**自动下载**，无需手动安装：

| 依赖 | 版本 | 用途 | 许可证 |
|------|------|------|--------|
| [Wine Staging](https://github.com/Gcenx/macOS_Wine_builds) | 11.4 (Gcenx 构建) | 运行 Windows exe | LGPL |
| [思源黑体 (Source Han Sans SC)](https://github.com/adobe-fonts/source-han-sans) | Regular | Wine 环境 CJK 字体渲染 | OFL 1.1 |

**可选依赖（不影响基本功能）：**

| 依赖 | 用途 |
|------|------|
| [winetricks](https://github.com/Winetricks/winetricks) | 部分引擎预设需要安装额外 Windows 组件（如 quartz、lavfilters） |

## 构建

```bash
open Gala.xcodeproj
# 在 Xcode 中 Build & Run
```

## 工作原理

Gala 封装 Wine Staging 来运行 Windows 视觉小说。首次启动时自动下载预编译的 Wine 和 CJK 字体。每个游戏拥有独立的 Wine 前缀（bottle），根据游戏语言自动配置：

- **中文游戏** — codepage 936 (GBK)，语言 0804
- **日文游戏** — codepage 932 (Shift-JIS)，语言 0411

字体通过 Wine 注册表替换机制映射，将 Windows 常见字体（SimSun、MS Gothic 等）指向思源黑体。

## 架构

- **Gala** — SwiftUI 应用（UI 层）
- **GalaKit** — Swift Package，核心逻辑（Wine 管理、引擎检测、VNDB 客户端）

详见[设计文档](docs/plans/2026-03-11-gala-design.md)。

## 许可证

MIT
