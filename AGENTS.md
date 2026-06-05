# AGENTS.md

## Project Snapshot
- Gala is a macOS SwiftUI galgame launcher with core logic in the `GalaKit` Swift package.
- Current runtime is app-managed Wine Staging 11.6. Do not introduce GPTK, Whisky, CrossOver, or Homebrew-only dependencies.
- Wine prefixes are shared by runtime profile, not by individual game.

## Architecture Rules
- Keep SwiftUI app code in `Gala/`; keep Wine, engine detection, VNDB, library, and model logic in `GalaKit/`.
- Route Wine work through `WineManager`, `BottleManager`, `WineProcess`, and `WineLaunchConfig`.
- Local engine signatures outrank VNDB. VNDB release metadata is only a conservative fallback.
- Runtime dependencies must download from Gala GitHub release assets, not directly from upstream projects.
- Never modify, patch, or delete files inside the user's game directories.

## Runtime Profiles
| Profile | Engines / Games | Key Runtime Notes |
| --- | --- | --- |
| `common` | BGI, legacy Artemis, NScripter, YU-RIS, RealLive, Majiro, AdvHD, QLIE, Unknown | DirectShow stack: `quartz`, `amstream`, `lavfilters`; LAV WMA registry switches |
| `kirikiri` | KiriKiri | Common video components with `quartz=native` |
| `leaf` | Leaf/AQUAPLUS, WHITE ALBUM2 | Builtin DirectShow, disabled Wine WMA/WMV codecs, LAV RGB output |
| `do-kizunar` | 家族計画 追憶 | Builtin `quartz`, `G:\` game mapping, D.O. registry install paths |
| `artemis-d3d11` | DirectShow-oriented Artemis/iarsys D3D11, e.g. ハミダシクリエイティブ凸 | DXMT v0.80 Wine variant, native `d3dcompiler_47`, DirectShow/LAV video chain |
| `artemis-mf-d3d11` | Media Foundation Artemis/iarsys D3D11, e.g. 甜蜜女友3 / アマカノ3 | Separate DXMT profile for MF/WMV routing; no DirectShow/LAV preset; Gala MF Runtime plus per-game WMV audio overlay |

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
| 汉化 Artemis D3D11 game detected as KiriKiri | Patch XP3 overrode real engine files | Engine detection scores multiple local signatures; `iarsys + .pfs + D3D11/D3DCompile` beats XP3 |

## Diagnosis Playbook
- First classify the failure: startup crash, black screen with audio, OP/video issue, font/codepage issue, or path issue.
- Inspect local files before trusting VNDB. Broad VNDB labels must not force a special profile without local evidence.
- Validate risky runtime ideas in a temporary prefix before changing profile code.
- If a fix creates or changes a profile, add migration and tests for existing library entries.

## Dependency Policy
- `deps-v1`: Wine Staging 11.6, Source Han Sans SC, winetricks, cabextract.
- `deps-v2`: DXMT v0.80 builtin.
- `deps-v3`: Gala MF Runtime for `artemis-mf-d3d11` GStreamer/FFmpeg media handling.
- DXMT archive sha256: `8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d`.
- Upload new dependency assets to Gala releases first, then reference those Gala-owned URLs in code.

## Verification
- `swift test --package-path GalaKit`
- `xcodebuild -project Gala.xcodeproj -scheme Gala -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/GalaDerivedData build`
- `git diff --check`

## Do Not
- Do not make `common` absorb special-profile DLL overrides.
- Do not let VNDB override high-confidence local detection.
- Do not require users to install Whisky, GPTK, CrossOver, Homebrew Wine, or Homebrew winetricks.
- Do not leave temporary prefixes or copied game assets outside clearly marked temp paths.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `NozomiX1/Gala`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default Matt Pocock triage label vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context repo. Read root `CONTEXT.md` and `docs/adr/` if present; proceed silently if absent. See `docs/agents/domain.md`.
