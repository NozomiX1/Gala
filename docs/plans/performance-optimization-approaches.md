# Gala 性能优化方案评估

## 背景

当前使用 Wine 运行 galgame 存在以下问题：
- CPU 占用高
- 启动速度慢
- 偶尔卡顿

本文档整理了所有讨论过的优化方案，包括可行性分析和推荐优先级。

---

## 方案一：Wine 配置调优（推荐首选）

**思路：** 不改 Wine 代码，通过配置和构建层面优化。

**具体手段：**
- `esync`/`msync` 减少 wineserver 同步开销
- `STAGING_SHARED_MEMORY` 等参数调优
- 精简 prefix：移除不需要的 DLL 和组件，减少启动加载量
- 预热 prefix：首次启动后缓存 wineserver，后续复用
- 裁剪构建：编译只包含 galgame 需要模块的精简 Wine（去掉网络、打印、COM 等）
- 针对特定引擎的 DLL override：用 native DLL 替换 Wine 内置实现

**工作量：** 小（天级别）
**覆盖面：** 所有游戏
**风险：** 低

---

## 方案二：Wine DLL Override（推荐重点投入）

**思路：** 保留 Wine 作为基础设施（PE 加载、线程、文件系统、注册表），只替换性能关键的图形/音频 DLL。

**架构：**
```
游戏 (.exe)
  ↓ 调用
Win32 核心 (kernel32, ntdll...)  ← Wine 处理（保留）
  ↓ 调用
ddraw.dll / d3d9.dll             ← 自研实现 → Metal
dsound.dll                       ← 自研实现 → CoreAudio
gdi32.dll (部分)                 ← 自研实现 → Core Text / Core Graphics
  ↓
macOS 原生框架
```

**优势：**
- Wine 兜底所有复杂的基础设施（PE 加载、CRT、SEH、TLS、COM 等）
- 图形/音频是性能瓶颈的核心，针对性替换效果明显
- DXVK 已证明这条路可行（替换 D3D→Vulkan）
- 覆盖面广：BGI、KiriKiri、Majiro、CatSystem2 底层都调同一套 DirectDraw/D3D9/GDI/DirectSound
- 可渐进开发，每一步都有 Wine 兜底

**Galgame 实际用到的核心调用（需通过 relay log 验证）：**
- DirectDraw: `DirectDrawCreate` → surface 管理 → `Blt`/`BltFast`
- D3D9: `Direct3DCreate9` → `CreateDevice` → `BeginScene`/`EndScene` → `DrawPrimitive`
- DirectSound: `DirectSoundCreate` → `CreateSoundBuffer` → `Lock`/`Unlock`/`Play`
- GDI: `CreateFont` → `TextOut`/`ExtTextOut`（CJK 文字渲染）

**难点：**
- 需要逆向确认每个引擎实际调用了哪些 API 和 edge case
- DirectDraw → Metal 的 surface 管理和像素格式转换
- GDI CJK 文字渲染与 Windows 行为一致性（字距、抗锯齿）
- Wine DLL override 构建工具链有学习成本

**工作量：** 中（3-6 个月出成果）
**覆盖面：** 所有使用 DirectDraw/D3D9/DirectSound 的游戏
**风险：** 中

---

## 方案三：引擎级原生重实现

**思路：** 对主流 galgame 引擎做原生 macOS 移植，直接读取游戏脚本和资源，完全绕过 Wine。

**主流引擎覆盖情况：**

| 引擎 | 大致占比 | 现有开源重实现 | 状态 |
|---|---|---|---|
| KiriKiri/吉里吉里 | ~30% | krkrsdl2 | 活跃，SDL2 跨平台 |
| NScripter | ~15% | onscripter-en | 成熟 |
| BGI/Ethornell | ~10% | 部分逆向，无完整重实现 | 缺失 |
| System4x (AliceSoft) | ~8% | xsystem4 | 活跃 |
| Ren'Py | ~8% | 原生跨平台 | 不需要 Wine |
| Majiro | ~5% | 无 | 缺失 |
| CatSystem2 | ~5% | 无 | 缺失 |

**优势：**
- 原生性能最好：Metal 渲染、CoreAudio 音频，零翻译开销
- 社区基础好（部分引擎）

**劣势：**
- 不 scale：每个引擎都要单独投入大量精力
- BGI、Majiro、CatSystem2 等缺少开源重实现，需从头逆向
- 实际经验：曾尝试 KiriKiri 重实现，投入大量努力后放弃，覆盖面太窄

**Gala 集成思路：**
- 在引擎检测层（EngineDetector）自动选择运行方式
- 有原生重实现的引擎走原生 runner
- 没有的继续走 Wine
- 定位从"Wine 前端"升级为"智能运行时选择器"

**工作量：** 大（每个引擎数月）
**覆盖面：** 仅限已实现的引擎
**风险：** 高（投入产出比不确定）

---

## 方案四：自建 Win32 兼容层（不推荐）

**思路：** 完全替代 Wine，自建 PE Loader + Win32 API Shim + 图形/音频层。

**架构：**
```
游戏 .exe (PE 格式)
    ↓
自建 PE Loader + Win32 API Shim
    ↓
macOS 原生 (POSIX / CoreGraphics / CoreAudio / Metal)
```

**严重问题：**

1. **Rosetta 2 不能直接翻译 PE 二进制。** Rosetta 2 翻译的是 Mach-O 格式，不是 PE。Wine 能在 Apple Silicon 上运行 x86 Windows 代码是利用了 Rosetta 运行时对 x86 代码页的动态翻译机制（未公开接口）。自建 PE Loader 要解决这个问题本身就是大型工程。

2. **API 数量严重低估。** 表面看 80-120 个，实际需要：
   - CRT（C 运行时）：malloc、fopen、sprintf、setlocale... 几百个函数
   - COM 基础设施：vtable 布局兼容、QueryInterface、AddRef/Release
   - SEH（结构化异常处理）：Windows PE 依赖的异常机制
   - TLS（线程局部存储）：PE 格式的 TLS directory
   - 编码转换：MultiByteToWideChar、WideCharToMultiByte
   - 真实数字在 500-800 个函数，很多不能 stub

3. **参考项目的误导性：**
   - loadlibrary：只能加载 DLL 调用单个函数，不能运行完整 .exe
   - box86/box64：团队开发多年，Linux 内核语义比 macOS 更接近 Windows
   - FEX-Emu：主要解决指令翻译，不是 API 兼容

4. **本质上就是重写 Wine，** 只是目标窄一些。但基础设施层（PE 加载、内存管理、线程、异常处理）需要完整实现，窄目标帮不了多少。

**工作量：** 极大（1-2 年，一个人可能做不完）
**覆盖面：** 理论上广，实际取决于完成度
**风险：** 极高

---

## 推荐路线

```
优先级 1: Wine 配置调优（立即可做，低风险）
    ↓
优先级 2: Wine DLL Override（核心投入方向）
    ↓  先用 WINEDEBUG=+relay 跑 BGI 游戏
    ↓  分析实际 API 调用热点
    ↓  从 DirectDraw/DirectSound override 开始
    ↓
优先级 3: 引擎原生集成（选择性）
    ↓  对已有成熟重实现的引擎（onscripter 等）直接集成
    ↓  不投入从头重写
```

## 下一步行动

1. 用 `WINEDEBUG=+relay` 跑一个 BGI 游戏，获取完整 API 调用日志
2. 分析调用频率和热点函数
3. 确定 DLL Override 的优先实现范围
