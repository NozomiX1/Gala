<p align="center">
  <img src="Gala/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Gala">
</p>

<h1 align="center">Gala</h1>

<p align="center">
  macOS 原生 Galgame 启动器<br>
  添加游戏，点击启动。Wine 配置、字体、引擎适配全部自动完成。
</p>

---

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

## 许可证

MIT
