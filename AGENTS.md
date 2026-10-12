# AGENTS.md

## Project Snapshot
- Gala is a macOS SwiftUI galgame launcher. Core logic lives in the `GalaKit` Swift package, which has no third-party dependencies. The app target has one: Sparkle, for updates, pinned to an exact version in `project.yml`.
- Runtime is app-managed Wine Staging 11.6.
- Wine prefixes (bottles) are shared by runtime profile, not created per game.
- App data lives in `~/Library/Application Support/Gala`.
- `gala-cli` (`GalaKit/Sources/gala-cli`) exposes the library and diagnostics on the command line. It is built twice from the same sources: as a SwiftPM product for `swift run gala-cli`, and as an Xcode tool target copied into the app bundle. `--home <dir>` points it at another data directory.

## Rules
- Keep SwiftUI app code in `Gala/`; keep Wine, engine detection, VNDB, library, and model logic in `GalaKit/`.
- Route Wine work through `WineManager`, `BottleManager`, `WineProcess`, and `WineLaunchConfig`. The steps from a library entry to a running game (configure, launch checks, media overlay) live in `GameRuntime`; the app and `gala-cli` both call it, so do not reimplement them in either.
- Local engine signatures outrank VNDB. VNDB release metadata is only a conservative fallback and must not force a special profile without local evidence.
- Never modify, patch, or delete files inside the user's game directories. Use Gala-owned caches, overlays, or symlinks.
- Do not introduce or require GPTK, Whisky, CrossOver, Homebrew Wine, or Homebrew winetricks.
- Runtime profiles are JSON files in `GalaKit/Sources/GalaKit/Resources/Profiles/`, one per profile; `ProfileStore` folds each file's `base` chain into a recipe. Users add their own in `Profiles/` under the data directory, and a game can be pointed at any profile by hand (`Game.profileID`). Always ask `ProfileStore.recipe(for: game)` (through `WineManager.profiles` or `GameRuntime.recipe(for:)`) what a game runs with; never decide from `game.engine` alone, or a hand-picked profile is ignored. Do not make `common` absorb special-profile DLL overrides: add a file with `"base": "common"` instead.
- Per-game switches are defined once, in `LaunchSwitch`; the run settings panel and `gala-cli guide` are generated from that list. A switch must take effect at launch and leave the prefix alone, and is added only after a real game has shown that it does (record the check in `docs/runtime-lessons.md`). `WineManager.usesDXMTWine(for:)` and `Game.launchDLLOverrides` are where switches meet the launch; bottle creation and the prefix marker follow the profile only.
- Editing a profile file changes its fingerprint, which makes existing prefixes of that profile reconfigure; raise `version` only to force that when the recipe itself reads the same. If a change moves games to a different profile, add a migration with tests for existing library entries.
- Do not read or write the real `~/Library/Application Support/Gala` in tests or experiments. Use temporary directories and remove them afterward, including temporary prefixes and copied game assets.

## Runtime Profiles
The files are the source of truth; this table is a summary.

| Profile | Engines / Games | Key Runtime Notes |
| --- | --- | --- |
| `common` | BGI, legacy Artemis, NScripter, YU-RIS, RealLive, Majiro, AdvHD, QLIE, Unknown | DirectShow stack: `quartz`, `amstream`, `lavfilters`; LAV WMA registry switches |
| `kirikiri` | KiriKiri | Common video components with `quartz=native` |
| `leaf` | Leaf/AQUAPLUS, WHITE ALBUM2 | Builtin DirectShow, disabled Wine WMA/WMV codecs, LAV RGB output |
| `do-kizunar` | 家族計画 追憶 | Builtin `quartz`, `G:\` game mapping, D.O. registry install paths |
| `artemis-d3d11` | DirectShow-oriented Artemis/iarsys D3D11, e.g. ハミダシクリエイティブ凸 | `common` launched with the DXMT v0.80 Wine variant; nothing DXMT-specific goes into the prefix |
| `artemis-mf-d3d11` | Media Foundation Artemis/iarsys D3D11, e.g. 甜蜜女友3 / アマカノ3 | Separate DXMT profile for MF/WMV routing; no DirectShow/LAV preset; Gala MF Runtime plus per-game WMV audio overlay |
| `cat-system2` | CatSystem2 | Unverified, no tested game: common video components plus `dotnet40`, `vcrun2015` |
| `siglus-engine` | SiglusEngine | Unverified, no tested game: common video components plus `xact`, `xinput`, `vcrun2019`, native `xaudio2_7`/`xactengine3_7` |

Ren'Py, RPG Maker, and Unity games also run in `common`. That is unverified: no game on those engines has been tested.

## Diagnosis
Read `docs/runtime-lessons.md` before changing a profile or debugging playback, rendering, font, or path problems. It holds the diagnosis order, the failure taxonomy, and the table of known bugs and their fixes. Add to it when a bug teaches a reusable rule.

## Dependencies
- Gala-managed dependencies download from Gala GitHub release assets, never directly from upstream. Upload the asset first, then reference its URL and sha256 in `WineManager`.
- Apple's on-demand fonts (SimSong, STHeiti) are the one exception: they cannot be redistributed, so `BottleManager` asks macOS to download them and falls back to fonts every macOS ships.
- `deps-v1`: Wine Staging 11.6, Source Han Sans SC, winetricks, cabextract.
- `deps-v2`: DXMT v0.80 builtin.
- `deps-v3`: Gala MF Runtime for `artemis-mf-d3d11` GStreamer/FFmpeg media handling.

## Conventions
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- `Gala.xcodeproj` is generated and not committed. Edit `project.yml`, which also holds the version number, then run `xcodegen generate`.
- Commit messages use a `feat:`, `fix:`, `perf:`, `docs:`, or `chore:` prefix.
- Record user-visible changes under `## [Unreleased]` in `CHANGELOG.md`.
- `docs/compatibility.md` is generated from the profiles' `verifiedGames`; a test fails when it is stale. Regenerate it with `swift run --package-path GalaKit gala-cli compat > docs/compatibility.md`. When a game is confirmed to run, add its original title to the profile's `verifiedGames`.
- UI strings and `README.md` are Chinese. Code, comments, commit messages, and the other docs are English.

## Releasing
- Set the version in `project.yml` and move the `[Unreleased]` changelog entries under a `## [X.Y.Z] - date` heading.
- `scripts/release.sh` builds `dist/Gala.dmg` and the signed `dist/appcast.xml` locally.
- Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`: it tests, builds, and publishes the DMG and `appcast.xml` with that changelog section as the release notes. The tag must match the version in `project.yml`.
- Installed copies read `releases/latest/download/appcast.xml`, so every release must carry that asset. Keep the `vX.Y.Z` tag format and the `.dmg` asset too: the 1.x update check finds new versions through them.
- Updates are signed with a Sparkle EdDSA key. The private key lives in the maintainer's login keychain (account `gala`) and in the `SPARKLE_PRIVATE_KEY` repository secret; the public key is in `project.yml`. Never replace the key pair: copies already installed would reject every later update.

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
