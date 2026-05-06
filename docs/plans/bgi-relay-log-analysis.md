# BGI 引擎 Relay Log 分析

## 测试环境
- 游戏：秽翼的尤斯蒂娅（汉化版）
- 引擎：BGI (Ethornell)，PE32 x86
- Wine：wine-staging 11.4 (Gcenx)
- 平台：macOS 26 / Apple M1 Pro / Rosetta 2 (WoW64)

## 第二次采集（通过 Gala 启动，游戏实际运行）

日志规模：91 万行，55MB
Debug channels: `+loaddll,+seh,+graphics,+gdi,+bitmap,+dib,+dsound,+wave,+winmm`

### Trace Channel 分布

| Channel | 行数 | 占比 |
|---------|------|------|
| gdi | 825,949 | 90.8% |
| dsound | 71,054 | 7.8% |
| seh | 8,827 | 1.0% |
| dib | 3,397 | 0.4% |
| bitmap | 319 | <0.1% |
| loaddll | 254 | <0.1% |
| winmm | 2 | <0.1% |

## 关键发现

### 1. 渲染：纯 GDI，无 DirectX

BGI 引擎完全不使用 DirectDraw / Direct3D。渲染链路：

```
游戏逻辑
  → GDI 对象管理 (alloc/free GDI handles)
    → DIB 操作 (CreateDIBSection, PutImage, GetImage)
      → 位图绘制 (StretchDIBits, BlendImage, PatBlt)
        → Wine macOS 驱动 → Core Graphics
```

**GDI 调用热点（合计 82.5 万次）：**

| 函数 | 次数 | 说明 |
|------|------|------|
| NtGdiExtGetObjectW | 413,472 | 获取 GDI 对象属性（字体、画笔等） |
| alloc_gdi_handle | 137,580 | 分配 GDI 句柄 |
| NtGdiDeleteObjectApp | 137,309 | 删除 GDI 对象 |
| free_gdi_handle | 137,283 | 释放 GDI 句柄 |

**大量 GDI 对象反复创建和销毁**——每帧可能都在重新创建字体、画笔等 GDI 对象，这是典型的低效模式。Wine 的 GDI 句柄管理有全局锁，频繁 alloc/free 会成为瓶颈。

**DIB（位图渲染）操作：**

| 函数 | 次数 | 说明 |
|------|------|------|
| dibdrv_SelectBrush | 696 | 选择画刷 |
| dibdrv_SetDeviceClipping | 630 | 设置裁剪区域 |
| dibdrv_SelectPen | 617 | 选择画笔 |
| add_cached_font | 616 | 缓存字体 |
| dibdrv_SelectBitmap | 394 | 选择位图 |
| dibdrv_DeleteDC | 187 | 删除设备上下文 |
| dibdrv_PutImage | 152 | **绘制图像到屏幕** |
| dibdrv_GetImage | 63 | 从屏幕读取图像 |
| dibdrv_BlendImage | 9 | **Alpha 混合** |
| dibdrv_PatBlt | 7 | 图案填充 |
| stretch_bitmapinfo | 4 | 拉伸位图 |

**Bitmap 操作：**

| 函数 | 次数 | 说明 |
|------|------|------|
| NtGdiCreateBitmap | 115 | 创建位图 |
| nulldrv_StretchDIBits | 71 | **StretchDIBits（核心绘图函数）** |
| NtGdiCreateCompatibleBitmap | 70 | 创建兼容位图 |
| NtGdiCreateDIBSection | 50 | **创建 DIB 内存区** |

### 2. 音频：DirectSound

BGI 使用 **DirectSound** 做音频，不是 waveOut。

| 函数 | 次数 | 说明 |
|------|------|------|
| DSOUND_MixToPrimary | 29,240 | 混音到主缓冲区（**最热**） |
| DSOUND_MixOne | 13,962 | 混合单个声音 |
| DSOUND_MixInBuffer | 9,308 | 混入缓冲区 |
| DSOUND_MixerVol | 8,342 | 音量混合 |
| mixieee32 | 4,171 | IEEE 浮点混音 |
| DSOUND_PerformMix | 2,446 | 执行混音 |
| DSOUND_CheckEvent | 2,112 | 检查通知事件 |
| IDirectSoundBufferImpl_Lock | 651 | 锁定缓冲区 |
| IDirectSoundBufferImpl_Unlock | 217 | 解锁缓冲区 |
| CreateSoundBuffer | 83 | 创建声音缓冲区 |
| SetVolume | 65 | 设置音量 |
| Play | 14 | 播放 |

Wine 的 DirectSound 实现是**软件混音器**，在 CPU 上做混音，然后输出到 CoreAudio。7 万次混音调用说明这是一个持续的 CPU 开销。

### 3. SEH（结构化异常处理）

8,827 次 SEH trace，说明游戏或引擎运行时有大量异常处理流程。这在 WoW64 (32-bit on 64-bit) 环境下开销尤其大。

## BGI 引擎渲染架构总结

```
BGI.exe
├── 渲染层：GDI
│   ├── 创建 DC + DIBSection (内存位图)
│   ├── 在内存中绘制场景（CPU 软渲染）
│   ├── StretchDIBits / PutImage → 提交到窗口
│   └── 大量 GDI 对象创建/销毁（字体、画刷、画笔）
├── 音频层：DirectSound
│   ├── CreateSoundBuffer → BGM/SE/Voice 各一路
│   ├── Lock/Unlock 写入 PCM 数据
│   └── Wine 软件混音器（CPU 密集）
└── 计时：winmm.timeGetTime
```

## 对优化方案的影响

### Wine DLL Override 目标确认

| 目标 DLL | 优化方向 | 预期效果 |
|----------|---------|---------|
| **gdi32 / win32u** | GDI → Core Graphics/Metal 快速路径 | 减少 GDI 对象管理开销，加速 DIB 渲染 |
| **dsound** | DirectSound → CoreAudio 直通 | 消除软件混音 CPU 开销 |

### 具体优化点

1. **GDI 对象池化**：alloc/free 各 13.7 万次，引擎每帧重建 GDI 对象。如果能在 Wine 层做对象缓存/池化，可大幅减少开销。

2. **DIB 渲染直通**：`dibdrv_PutImage`(152次) + `nulldrv_StretchDIBits`(71次) 是实际上屏的关键函数。可以将 DIBSection 直接映射为 Metal texture，跳过 Wine 的 DIB 驱动层。

3. **DirectSound 硬件混音**：用 CoreAudio 的混音能力替代 Wine 的软件混音器（2.9 万次 MixToPrimary），减少 CPU 占用。

4. **GDI handle 查询优化**：`NtGdiExtGetObjectW` 41 万次调用，可能是每次绘制前都要查询对象属性。如果能缓存这些属性，可以大幅减少调用。

### 这些发现对"自建兼容层"方案的意义

BGI 引擎的 API 调用面确实比较收敛：
- 渲染只用 GDI（不用 DirectX 图形）
- 音频只用 DirectSound（接口简单）
- 窗口管理极简

但即使如此，通过 Wine DLL Override 优化仍然是更高效的路径，因为不需要重建 PE loader、CRT、COM 等基础设施。

---

## 第三次采集：启动阶段耗时 Profile

通过 Gala 启动游戏，stderr 经 perl 加毫秒级时间戳。
Debug channels: `+loaddll,+process,+thread,+dsound,+timestamp`

### 启动时间线（总耗时 ~70s）

```
T+0.0s ─── Wine 基础设施启动 ──────────────────────── 2.0s
│  wineboot.exe           0.2s
│  services.exe           0.1s
│  winedevice.exe ×2      1.2s
│  plugplay.exe           0.3s
│  svchost.exe            0.1s
│
T+1.5s ─── 汉化启动器 ────────────────────────────── 0.3s
│  秽翼的尤斯蒂娅.exe → spawn BGI.exe
│
T+1.9s ─── BGI.exe 加载 DLL ─────────────────────── 14.3s ★★★
│  加载 kernel32/user32/gdi32/ole32 等
│  ⚠ 3.3s gap：shell32.dll 加载后阻塞
│  ⚠ 2.3s gap：NtSetInformationThread 循环
│  ⚠ 多次 1-2s 的间歇性等待
│
T+16.2s ── explorer.exe 启动 ────────────────────── 17.2s ★★★★
│  ⚠ 8.2s gap：最大单次等待
│  ⚠ 1.8s gap
│  explorer 初始化 Shell、DDE、Tray 窗口
│  rpcss.exe 启动
│
T+33.4s ── DirectSound 初始化 ───────────────────── 4.7s ★★
│  大量 CreateSoundBuffer（83 个缓冲区）
│  每个缓冲区创建耗时 ~0.5-0.7s
│
T+38.1s ── 游戏运行中 ──────────────────────────── 32.0s
│  DirectSound 持续混音
│  ⚠ 11.9s gap at T+50s（加载新资源？）
│  ⚠ 多次 2-3s gap（场景切换？）
│
T+70.1s ── 游戏退出
```

### 启动瓶颈分析

| 阶段 | 耗时 | 占比 | 原因 |
|------|------|------|------|
| Wine 基础设施 | 2.0s | 3% | wineboot + 系统服务启动 |
| **BGI DLL 加载** | **14.3s** | **20%** | DLL 查找 + WoW64 映射 + 间歇等待 |
| **explorer.exe** | **17.2s** | **25%** | Shell 初始化、DDE、RPC — 游戏其实不需要 |
| DirectSound 初始化 | 4.7s | 7% | 83 个缓冲区逐个创建 |
| 到游戏可玩 | **~38s** | | |

### 关键洞察

1. **explorer.exe 是最大的时间浪费（17.2s）**
   - BGI 游戏不需要 Windows Shell、Tray 窗口、DDE 协议
   - 启动 explorer 是 wineboot 的默认行为
   - **可优化：跳过 explorer.exe 启动，或用 stub 替代**

2. **BGI DLL 加载中的间歇等待（14.3s 但实际加载只需 ~2s）**
   - DLL 文件本身加载很快（<0.5s）
   - 大量时间花在 `NtSetInformationThread` 循环等待上
   - 这可能是 wineserver 同步开销（每次系统调用都要 round-trip 到 wineserver）
   - **可优化：启用 esync/msync 减少 wineserver round-trip**

3. **DirectSound 缓冲区创建太多（83 个）**
   - 每个缓冲区创建耗时 0.5-0.7s
   - 游戏可能预分配了大量 SE 缓冲区
   - **可优化：延迟创建或批量创建**

4. **运行时也有大 gap（11.9s, 2-3s）**
   - 可能是加载新场景资源时阻塞在文件 I/O
   - 或 GDI 对象大量创建/销毁导致 wineserver 压力

### 第四次采集：esync 优化对比

esync 启用后几乎无效果（总启动时间从 ~33s 到 ~33s，差 <0.5s）。

#### 真正的时间消耗分析

DLL 实际加载只需要 ~2s，29s 启动时间中 **~20s 是在等待/阻塞**：

```
实际工作                   等待/阻塞
DLL 加载 ~2s               NtSetInformationThread 循环 ~10s
explorer 创建 ~2s          explorer 就绪等待 ~12.8s (最大单次 gap)
wined3d GPU 检测 ~2s       其他间歇等待 ~2s
DirectSound 初始化 ~0.3s
```

#### 等待的原因

大 gap 前后的上下文全是 `NtSetInformationThread` / `NtQueryInformationThread`，
不是 I/O 等待，不是 CPU 密集计算。这是 **Wine 进程间同步**的表现：
- 游戏进程在等 wineserver 响应
- wineserver 在处理 explorer/其他服务进程的请求
- 所有进程共享一个 wineserver，串行处理

esync 没有帮助，因为瓶颈不在 futex/eventfd 同步原语，
而在 wineserver 的**请求队列串行化**。

#### explorer.exe 不能禁用

测试 `explorer.exe=d` 导致 wined3d 无法创建窗口，DirectSound 初始化失败。
Wine 需要 explorer 来提供桌面窗口上下文。

### 可行的优化方向（更新）

1. ~~跳过 explorer.exe~~ → 不可行
2. ~~esync~~ → 几乎无效果
3. **预热 wineserver + explorer** → 首次启动后保持运行，后续启动跳过 ~15s
4. **使用 virtual desktop 模式** → `wine explorer /desktop=Game,1024x768 game.exe`，可能让 explorer 初始化更快
5. **减少 Wine 服务进程** → 禁用不需要的 plugplay/svchost 等
6. **Patch Wine 的同步等待** → wineserver 请求批处理或异步化（难度大）
