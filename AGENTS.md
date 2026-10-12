# AGENTS.md

## Project Snapshot
- Gala is a macOS SwiftUI galgame launcher. Core logic lives in the `GalaKit` Swift package, which has no third-party dependencies.
- Runtime is app-managed Wine Staging 11.6.
- Wine prefixes (bottles) are shared by runtime profile, not created per game.
- App data lives in `~/Library/Application Support/Gala`.

## Rules
- Keep SwiftUI app code in `Gala/`; keep Wine, engine detection, VNDB, library, and model logic in `GalaKit/`.
- Route Wine work through `WineManager`, `BottleManager`, `WineProcess`, and `WineLaunchConfig`.
- Local engine signatures outrank VNDB. VNDB release metadata is only a conservative fallback and must not force a special profile without local evidence.
- Never modify, patch, or delete files inside the user's game directories. Use Gala-owned caches, overlays, or symlinks.
- Do not introduce or require GPTK, Whisky, CrossOver, Homebrew Wine, or Homebrew winetricks.
- Do not make `common` absorb special-profile DLL overrides.
- If a change creates or alters a profile, bump `Engine.runtimeConfigVersion` for it, and add a migration with tests for existing library entries.
- Do not read or write the real `~/Library/Application Support/Gala` in tests or experiments. Use temporary directories and remove them afterward, including temporary prefixes and copied game assets.

## Runtime Profiles
| Profile | Engines / Games | Key Runtime Notes |
| --- | --- | --- |
| `common` | BGI, legacy Artemis, NScripter, YU-RIS, RealLive, Majiro, AdvHD, QLIE, Unknown | DirectShow stack: `quartz`, `amstream`, `lavfilters`; LAV WMA registry switches |
| `kirikiri` | KiriKiri | Common video components with `quartz=native` |
| `leaf` | Leaf/AQUAPLUS, WHITE ALBUM2 | Builtin DirectShow, disabled Wine WMA/WMV codecs, LAV RGB output |
| `do-kizunar` | 家族計画 追憶 | Builtin `quartz`, `G:\` game mapping, D.O. registry install paths |
| `artemis-d3d11` | DirectShow-oriented Artemis/iarsys D3D11, e.g. ハミダシクリエイティブ凸 | DXMT v0.80 Wine variant, native `d3dcompiler_47`, DirectShow/LAV video chain |
| `artemis-mf-d3d11` | Media Foundation Artemis/iarsys D3D11, e.g. 甜蜜女友3 / アマカノ3 | Separate DXMT profile for MF/WMV routing; no DirectShow/LAV preset; Gala MF Runtime plus per-game WMV audio overlay |
| `cat-system2` | CatSystem2 | Unverified, no tested game: common video components plus `dotnet40`, `vcrun2015` |
| `siglus-engine` | SiglusEngine | Unverified, no tested game: common video components plus `xact`, `xinput`, `vcrun2019`, native `xaudio2_7`/`xactengine3_7` |

Ren'Py, RPG Maker, and Unity games also run in `common`. That is unverified: no game on those engines has been tested.

## Diagnosis
Read `docs/runtime-lessons.md` before changing a profile or debugging playback, rendering, font, or path problems. It holds the diagnosis order, the failure taxonomy, and the table of known bugs and their fixes. Add to it when a bug teaches a reusable rule.

## Dependencies
- Gala-managed dependencies download from Gala GitHub release assets, never directly from upstream. Upload the asset first, then reference its URL and sha256 in `WineManager`.
- `deps-v1`: Wine Staging 11.6, Source Han Sans SC, winetricks, cabextract.
- `deps-v2`: DXMT v0.80 builtin.
- `deps-v3`: Gala MF Runtime for `artemis-mf-d3d11` GStreamer/FFmpeg media handling.

## Conventions
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- `Gala.xcodeproj` is generated and not committed. Edit `project.yml`, which also holds the version number, then run `xcodegen generate`.
- Commit messages use a `feat:`, `fix:`, `perf:`, `docs:`, or `chore:` prefix.
- Record user-visible changes under `## [Unreleased]` in `CHANGELOG.md`.
- UI strings and `README.md` are Chinese. Code, comments, commit messages, and the other docs are English.

## Verification
- `swift test --package-path GalaKit`
- `xcodegen generate && xcodebuild -project Gala.xcodeproj -scheme Gala -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/GalaDerivedData build`
- `git diff --check`

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `NozomiX1/Gala`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default Matt Pocock triage label vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context repo. Read root `CONTEXT.md` and `docs/adr/` if present; proceed silently if absent. See `docs/agents/domain.md`.
