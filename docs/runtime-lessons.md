# Runtime Lessons

This note captures hard-won Gala runtime diagnosis lessons. Keep it short and update it when a bug teaches a reusable rule.

## Diagnosis Order

1. Capture Wine logs and the exact user-visible symptom before changing profiles.
2. Classify the failure: D3D/rendering, DirectShow, Media Foundation, codec/container, font/codepage, or path/registry.
3. Inspect local files before trusting VNDB: executable imports, DLLs, archive types, movie files, and fake extensions.
4. Probe media files with `ffprobe` when OP/logo/movie playback is involved.
5. Change one variable per experiment and record what changed: Wine variant, DXMT, DirectShow/LAV, Media Foundation, codec/container, locale.
6. Validate risky runtime changes in a temporary prefix before changing shared profile code.

## Playback Failure Taxonomy

- D3D/rendering failures usually show black screen, shader/device errors, or audio with no visuals. Check D3D11/DXGI/DXMT before touching media filters.
- DirectShow failures usually affect OP/logo/movie clips while the game itself can still run. Check `quartz`, `amstream`, LAV filters, ASF/WMV signatures, and fake `.dat` extensions.
- Media Foundation failures are separate from DirectShow. Look for `MFStartup`, `MFCreateMediaSession`, `MFPlat`, Wine GStreamer logs, and WMV/WMA behavior.
- Codec/container failures require inspecting the actual file, not just the extension. WMV video with WMA/WMA Lossless audio can need a different fix than WMV video itself.
- Font/codepage failures show boxes or mojibake and should not be conflated with playback or rendering issues.

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

## Known Bugs And Fixes

| Symptom | Root Cause | Current Handling |
| --- | --- | --- |
| BGI/AUGUST OP black screen or skipped OP | Missing legacy DirectShow/LAV path | `common` profile installs `quartz`, `amstream`, `lavfilters` and enables LAV WMA formats |
| WHITE ALBUM2 OP/video failure | Leaf needs stricter media routing than `common` | `leaf` profile uses builtin DirectShow, disables Wine WMA/WMV codecs, forces LAV RGB output |
| 家族計画 path/registry/media issues | Game expects D.O. install registry and `G:\` paths | `do-kizunar` profile writes install paths to `G:\` and uses builtin `quartz` |
| Win32 dialog CJK text shows squares | Wine lacks usable CJK UI fonts and mappings | Install Source Han Sans SC, register it, set font substitutes/window metrics, use zh_CN codepage where needed |
| 甜蜜女友3 / アマカノ3 black screen with audio | Main D3D11 rendering issue, not OP/DirectShow | DXMT v0.80 builtin and `d3dcompiler_47=native,builtin` |
| Hamidashi Creative Totsu OP/WMV clips white-flash or skip | DXMT profile lacked DirectShow/LAV media components; Wine 11.6 ignores `Media Type\\Extensions` Source Filter values and `.dat` ASF files can hit `File Source (Async.)` | `artemis-d3d11` config v4 adds `quartz`, `amstream`, `lavfilters`, LAV WMA switches, deletes legacy `.dat` extension keys, and maps the ASF header signature to LAV Splitter Source without overriding `d3d11`/`dxgi` |
| 甜蜜女友3 / アマカノ3 WMV clips skip or OP white screen | Game uses Media Foundation WMV; Wine MF can decode the video path with the FFmpeg backend, but WMA/WMA Lossless audio can stall playback | `artemis-mf-d3d11` config v2 installs Gala MF Runtime, sets `DisableGstByteStreamHandler=1`, injects GStreamer env only for this profile, and launches from a per-game overlay where `movie/*.wmv` keeps video unchanged but converts audio to PCM |
| 甜蜜女友3 first OP has audio before video | First launch can generate the GStreamer registry after the movie overlay already exists, delaying video pipeline startup | Treat as a one-time warmup artifact when the second launch is synchronized; consider a future MF prewarm step before changing runtime routing |
| 汉化 Artemis D3D11 game detected as KiriKiri | Patch XP3 overrode real engine files | Engine detection scores multiple local signatures; `iarsys + .pfs + D3D11/D3DCompile` beats XP3 |

## BGI/Ethornell Engine Notes

Measured on Wine Staging 11.4 with 穢翼のユースティア; recheck before relying on them for a newer Wine.

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
