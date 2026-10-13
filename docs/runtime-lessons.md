# Runtime Lessons

This note captures hard-won Gala runtime diagnosis lessons. Keep it short and update it when a bug teaches a reusable rule.

## Diagnosis Order

1. Capture Wine logs and the exact user-visible symptom before changing profiles.
2. Establish which copy it is before trying to reproduce: get the diagnostics (they list the game folder and the launch file) and compare with the copy being tested. One title can ship as unrelated programs: an original and a re-release on another engine, with or without a fan-translation executable. "Works here" about a different copy says nothing.
3. Classify the failure: D3D/rendering, DirectShow, Media Foundation, codec/container, font/codepage, or path/registry.
4. Inspect local files before trusting VNDB: executable imports, DLLs, archive types, movie files, and fake extensions.
5. Probe media files with `ffprobe` when OP/logo/movie playback is involved.
6. Change one variable per experiment and record what changed: Wine variant, DXMT, DirectShow/LAV, Media Foundation, codec/container, locale.
7. Validate risky runtime changes in a temporary prefix before changing shared profile code.

## Playback Failure Taxonomy

- D3D/rendering failures usually show black screen, shader/device errors, or audio with no visuals. Check D3D11/DXGI/DXMT before touching media filters.
- DirectShow failures usually affect OP/logo/movie clips while the game itself can still run. Check `quartz`, `amstream`, LAV filters, ASF/WMV signatures, and fake `.dat` extensions.
- Media Foundation failures are separate from DirectShow. Look for `MFStartup`, `MFCreateMediaSession`, `MFPlat`, Wine GStreamer logs, and WMV/WMA behavior.
- Codec/container failures require inspecting the actual file, not just the extension. WMV video with WMA/WMA Lossless audio can need a different fix than WMV video itself.
- Font/codepage failures show boxes or mojibake and should not be conflated with playback or rendering issues.
- A dialog in mojibake is still a message. Do not read it off a screenshot: find the original string in the executable (search for a decodable fragment in Shift-JIS) or rerun under the program's own locale. The dialog on screen when a game dies is not necessarily why it died.

## Runtime Profile Lessons

- Engine brand is not a runtime profile. Hamidashi and Amakano3 are both Artemis/iarsys D3D11 but need different media stacks.
- Local signatures outrank VNDB. VNDB can match the wrong game, wrong release, port, or patch.
- Shared bottles must be scoped by runtime compatibility, not by broad engine family.
- Every profile fix should ask whether it pollutes other games using that profile.
- Dependencies that are essential to a Gala profile should be hosted in Gala GitHub release assets.
- Never patch original game directories. Use Gala-owned caches, overlays, symlinks, or generated files.
- Treat first-run media cache generation as a possible warmup artifact if a second launch is synchronized.
- Runtime migrations should be repeatable and skippable. If scanning is expensive, persist a marker and rerun only when rules or selected executable change.

## Launch-Time Overrides

Checked on Wine Staging 11.6 on 2026-10-13 by loading `quartz.dll` in real prefixes with `WINEDEBUG=+loaddll`.

- `WINEDLLOVERRIDES` set for one launch wins over the prefix's registry `DllOverrides`, in both directions. A DLL choice can therefore be a per-game, per-launch setting; it does not need its own prefix.
- `quartz=native` (the `kirikiri` profile) and `quartz=native,builtin` (`common`) load the same native DLL as long as it is installed, which it is in both. 千恋＊万花 starts and runs normally in `common`. The two profiles differ only if the native DLL fails to load; in-game video playback was not exercised in this check.
- A native-only override on a prefix where the native DLL was never installed makes the load fail outright. Offer "native" only where the component is installed, or write it as `native,builtin`.

## DXMT Is Chosen By The Wine Build

Checked on 2026-10-13 with ハミダシクリエイティブ凸 (64-bit, D3D11) and 千恋＊万花 (32-bit, D3D9), reading `WINEDEBUG=+loaddll` and the title screen.

- The DXMT Wine variant and the plain one differ only in `d3d11`, `dxgi`, `d3d10core`, `winemetal` (plus `nvapi64`, `nvngx`) in Wine's own `lib/wine`. They share the same `wine.inf`, so alternating between them on one prefix does not trigger a prefix update.
- Which one renders is decided by the Wine binary alone. DXMT Wine against the plain `common` prefix: ハミダシ reaches its title screen. Plain Wine against the `artemis-d3d11` prefix: black window and `CreateVertexShader ... failed (0x80070057)`. Rendering can therefore be a per-game, per-launch choice.
- A D3D9 game never loads those DLLs: 千恋＊万花 runs the same under the DXMT variant.
- Until 2.0, configuring a DXMT profile also copied every DLL from the variant's `lib/wine` into the prefix. The copies were builtin-marked, so Wine loaded its own `lib/wine` files regardless, and the copy overwrote what winetricks had installed just before: in those prefixes `quartz`, `amstream`, and `d3dcompiler_47` were Wine's builtin files and loaded as builtin, whatever the profile's overrides said. The copy is gone. `"wine": "dxmt"` in a profile is all DXMT needs, and it implies the download.
- ハミダシ plays its logo and movies in both states: builtin `quartz` (an old `artemis-d3d11` prefix) and native `quartz` (the `common` prefix), each through LAV Splitter/Video and EVR. `d3dcompiler_47` loaded as builtin in every run, so the two Artemis D3D11 profiles no longer install the native one. アマカノ3 was not re-run; its prefix contents are unchanged by this, since the native DLL never survived the copy.

## One Title, Two Programs; A Packed Executable That Crashes

Checked on 2026-10-13 with the copy of ノラと皇女と野良猫ハート from issue #5: the 2016 original (Whale engine, D3D9, `arc*.dat`, `script.dat`) with a fan translation, in a clone of the `kirikiri` prefix. The 2019 re-release of the same title is a KiriKiri program and shares nothing with it.

- The engine runs. The unpacked Japanese `ノラと皇女と野良猫ハート.exe` (2.6 MB) reaches the game with text and graphics once the locale is Japanese.
- Locale is a launch-level setting. Under `zh_CN.UTF-8` that executable stops with `loadLabel script.dat No such file or directory`; with only `LANG`/`LC_ALL` set to `ja_JP.UTF-8` and the prefix untouched, it starts.
- The dialog `Software が使えないので Hardware で起動します。(このエラーはゲームの動作には影響ありません)` is the engine's own notice about vertical sync and is harmless. Under the Chinese code page it shows as mojibake, which makes it look like the failure.
- `err:d3d:wined3d_check_gl_call GL_INVALID_FRAMEBUFFER_OPERATION from glClear` appears in the run that works as well. It is not the cause of anything here.
- The translated executable (`…chs.exe`, the same file as `game.exe`, 83 MB) crashes every time just after its first frame. Its PE sections have blank and random names, and at the crash the process holds dozens of one-page private RWX regions filled with `pushal`/`rdtsc`/`popfl`/jump-over-garbage code. The faulting address is always inside one of those pages, or a wild jump out of one. Every D3D9 call before it succeeds, and reporting Windows 7 changes nothing. So the fault is in the protector's generated code, not in the engine, the profile, or a DLL choice. Why it holds on real Windows and not here was not established.
- How to tell this case apart: check the section names of the executable, look for an unpacked executable beside it and try that one, and attach `winedbg` to the suspended process (`AeDebug\Debugger` pointed at a program that just waits) to see what kind of memory the faulting address is in.
- The engine writes `Information.txt` into the game folder on each start: adapter, modes, and D3D capabilities as it saw them. It is a free device report.

## Known Bugs And Fixes

| Symptom | Root Cause | Current Handling |
| --- | --- | --- |
| BGI/AUGUST OP black screen or skipped OP | Missing legacy DirectShow/LAV path | `common` profile installs `quartz`, `amstream`, `lavfilters` and enables LAV WMA formats |
| WHITE ALBUM2 OP/video failure | Leaf needs stricter media routing than `common` | `leaf` profile uses builtin DirectShow, disables Wine WMA/WMV codecs, forces LAV RGB output |
| 家族計画 path/registry/media issues | Game expects D.O. install registry and `G:\` paths | `do-kizunar` profile writes install paths to `G:\` and uses builtin `quartz` |
| Win32 dialog CJK text shows squares | Wine lacks usable CJK UI fonts and mappings | Install Source Han Sans SC, register it, set font substitutes/window metrics, use zh_CN codepage where needed |
| 甜蜜女友3 / アマカノ3 black screen with audio | Main D3D11 rendering issue, not OP/DirectShow | DXMT v0.80 Wine variant |
| Hamidashi Creative Totsu OP/WMV clips white-flash or skip | DXMT profile lacked DirectShow/LAV media components; Wine 11.6 ignores `Media Type\\Extensions` Source Filter values and `.dat` ASF files can hit `File Source (Async.)` | `artemis-d3d11` config v4 adds `quartz`, `amstream`, `lavfilters`, LAV WMA switches, deletes legacy `.dat` extension keys, and maps the ASF header signature to LAV Splitter Source without overriding `d3d11`/`dxgi` |
| 甜蜜女友3 / アマカノ3 WMV clips skip or OP white screen | Game uses Media Foundation WMV; Wine MF can decode the video path with the FFmpeg backend, but WMA/WMA Lossless audio can stall playback | `artemis-mf-d3d11` config v2 installs Gala MF Runtime, sets `DisableGstByteStreamHandler=1`, injects GStreamer env only for this profile, and launches from a per-game overlay where `movie/*.wmv` keeps video unchanged but converts audio to PCM |
| 甜蜜女友3 first OP has audio before video | First launch can generate the GStreamer registry after the movie overlay already exists, delaying video pipeline startup | Treat as a one-time warmup artifact when the second launch is synchronized; consider a future MF prewarm step before changing runtime routing |
| Japanese executable stops with a file-not-found error for a file that is there | Path handling in the program assumes the Shift-JIS code page | Launch with `LANG`/`LC_ALL` set to `ja_JP.UTF-8`; the prefix does not need to change |
| Packed (protector-wrapped) executable crashes at an address outside every module | The protector's own generated code faults under Wine on Apple Silicon | Not fixable from a profile; use an unpacked executable or another release of the game |
| 汉化 Artemis D3D11 game detected as KiriKiri | Patch XP3 overrode real engine files | Engine detection scores multiple local signatures; `iarsys + .pfs + D3D11/D3DCompile` beats XP3 |

## BGI/Ethornell Engine Notes

Measured on Wine Staging 11.4 with 穢翼のユースティア; recheck before relying on them for a newer Wine.

- Font names: a Japanese engine asks for `ＭＳ 明朝` / `ＭＳ ゴシック` by their Shift-JIS bytes through the ANSI API. In a prefix with the Chinese code page those bytes are read as GBK, so the game asks for `俵俽 柧挬` / `俵俽 僑僔僢僋`, no font matches, and every request falls back to one default font: the game's 宋体/黑体 option does nothing. `WINEDEBUG=+font` shows the requested name on the `NtGdiHfontCreate` lines; `font_EnumFonts facename` shows it only after substitution, so trace in a bare prefix to see the raw name. Checked on Wine Staging 11.6 on 2026-10-13.
- Font width: BGI asks for an explicit width (height 48, width 24), and Wine scales glyphs by that width over the font's own average character width. The glyph size likewise follows the font's own line height (`usWinAscent + usWinDescent`), since the requested height is the cell. So a substitute has to match the MS fonts on both: line height 1.0 em, average width 0.5 em. Measured against that (size, width): SimSong 1.00/1.00 and STHeiti 1.00/1.04 fit, and the maintainer judged both good in the game; STSong 1.00/1.23 has touching glyphs; Hiragino Sans GB 0.86/0.92 and Arial Unicode MS 0.75/1.13 are small; Source Han Sans 0.69/0.51 and Heiti SC 1.00/0.50 are squeezed to half width. SimSong and STHeiti are fonts macOS downloads on demand and cannot be redistributed; `BottleManager.downloadOnDemandFonts` asks macOS for them (CoreText matching by PostScript name; a family name matches a fallback and downloads nothing). Read `xAvgCharWidth` and the win metrics before choosing a substitute.
- A multi-weight family is a poor substitute target: asked for Songti SC at weight 400, Wine chose its Black face. Target a single-weight family (STSong).
- BGI renders with plain GDI (CPU drawing into DIB sections) and plays audio through DirectSound. The game made no DirectDraw or Direct3D rendering calls, so check GDI and DirectSound before touching D3D or DXMT settings.
- Enabling esync made no measurable difference to startup time.
- Disabling `explorer.exe` breaks window creation and DirectSound initialization; Wine needs it for the desktop window.

## Anti-Patterns

- Do not start by swapping Wine variants, GPTK, Whisky, or D3DMetal without first classifying the failure.
- Do not assume all OP failures are LAV problems.
- Do not assume all Artemis/iarsys games can share one bottle.
- Do not let a VNDB engine label force a special profile without local evidence.
- Do not run many environment changes at once; it makes the successful variable impossible to identify.
- Do not turn one game's workaround into a shared-profile override unless other games in that profile are known to tolerate it.
