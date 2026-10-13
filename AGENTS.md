# AGENTS.md

## Project Snapshot
- Gala is a macOS SwiftUI galgame launcher. Core logic lives in the `GalaKit` Swift package, which has no third-party dependencies. The app target has one: Sparkle, for updates, pinned to an exact version in `project.yml`.
- Runtime is app-managed Wine Staging 11.6.
- Wine prefixes (bottles) are shared, not created per game: one per profile that installs something, used by every profile built on it that does not. A game's prefix is the path stored on the game, not one derived from its profile.
- App data lives in `~/Library/Application Support/Gala`.
- `gala-cli` (`GalaKit/Sources/gala-cli`) exposes the library and diagnostics on the command line. It is built twice from the same sources: as a SwiftPM product for `swift run gala-cli`, and as an Xcode tool target copied into the app bundle. `--home <dir>` points it at another data directory.

## Rules
- Keep SwiftUI app code in `Gala/`; keep Wine, engine detection, VNDB, library, and model logic in `GalaKit/`.
- Route Wine work through `WineManager`, `BottleManager`, `WineProcess`, and `WineLaunchConfig`. The steps from a library entry to a running game (configure, launch checks, media overlay) live in `GameRuntime`; the app and `gala-cli` both call it, so do not reimplement them in either. Both also pass the library through `RuntimeProfileMigration.migrate` after loading it.
- Local engine signatures outrank VNDB. VNDB release metadata is only a conservative fallback and must not force a special profile without local evidence.
- Never modify, patch, or delete files inside the user's game directories. Use Gala-owned caches, overlays, or symlinks.
- Do not introduce or require GPTK, Whisky, CrossOver, Homebrew Wine, or Homebrew winetricks.
- Runtime profiles are JSON files in `GalaKit/Sources/GalaKit/Resources/Profiles/`, one per profile; `ProfileStore` folds each file's `base` chain into a recipe. Users add their own in `Profiles/` under the data directory, and a game can be pointed at any profile by hand (`Game.profileID`). Always ask `ProfileStore.recipe(for: game)` (through `WineManager.profiles` or `GameRuntime.recipe(for:)`) what a game runs with; never decide from `game.engine` alone, or a hand-picked profile is ignored. Do not make `common` absorb special-profile DLL overrides: add a file with `"base": "common"` instead.
- Detection from files is only the first guess: packers hide imports, launchers have none, VNDB can name another release. Every launch records which DLLs Wine loaded, and `LaunchObservation` reads from that log what the game really used; `GameRuntime.advice(for:)` turns it, plus the profile's own `advice` text, into things the user can try. Add a rule there when a failure can be recognised from loaded modules, rather than adding a per-game special case. Advice only suggests; it never changes a setting or a game file.
- Profiles come in from outside through `ProfileImport` only: pasted text or a dropped file. It refuses unknown fields rather than dropping them, never lets a pasted id replace a bundled profile, and resolves the file before anything is saved; the sheet shows `ProfileDetail` so the user sees every component and registry value first. Keep it that way: a profile can write anything into a prefix, and a prefix can reach the user's files. An import built on another import is folded flat (`ProfileFile.folded`) so that imports depend only on bundled profiles and an earlier attempt can be deleted; its prefix is seeded from that attempt's (`BottleManager.seedPrefix`) at import time, since afterwards the file no longer names it. Files placed in the folder by hand keep their chains. The help request (`Diagnostics.helpRequest`) documents the same fields for assistants; change both together.
- Per-game switches are defined once, in `LaunchSwitch`; the run settings panel and `gala-cli guide` are generated from that list. A switch must take effect at launch and leave the prefix alone, and is added only after a real game has shown that it does (record the check in `docs/runtime-lessons.md`). `WineManager.usesDXMTWine(for:)`, `Game.launchDLLOverrides`, and `Game.launchLocale` are where switches meet the launch; bottle creation and the prefix marker follow the profile only.
- A profile has two halves. What goes into the prefix: `components`, `registry`, `registryDelete`. What is passed at every launch and never written into the prefix: `wine`, `dllOverrides`, `environment`, `launchArguments`, `locale`. Both are inherited along `base`. Only the first half decides the prefix: `RuntimeRecipe.bottleID` is the nearest profile in the chain that has one, so a profile that only changes the launch half runs in its base's prefix and needs no building. The prefix carries its owner's marker.
- A new prefix is cloned from the nearest ancestor prefix that is already built (`BottleManager.cloneSource`), then the profile's own components and registry values are applied; winetricks skips what the copy already has. A root (no `base`) is built from scratch. Never clone to refresh an existing prefix: games keep saves in them. Components can only be added along a chain; a profile that must not have one cannot be based on a profile that installs it, which is why `artemis-mf-d3d11` is a root.
- winetricks writes a component's own DLL overrides into the prefix when it installs it. Those stay there as part of the component, so `common` lists none. Do not write a profile's `dllOverrides` into a prefix again: prefixes made by 2.0 and 2.1 have them, are still accepted, and are not used as clone sources when they do.
- Editing the prefix half of a profile file changes its fingerprint, which makes existing prefixes of that profile reconfigure in place; editing the launch half changes nothing in any prefix and takes effect at the next launch. Markers from before format 2 carry a fingerprint that cannot be compared; they are judged by profile and version and rewritten when found current. To force a reconfigure regardless, raise `version` only to force that when the recipe itself reads the same. If a change moves games to a different profile, add a migration with tests for existing library entries.
- Do not read or write the real `~/Library/Application Support/Gala` in tests or experiments. Use temporary directories and remove them afterward, including temporary prefixes and copied game assets.

## Runtime Profiles
The files are the source of truth; this table is a summary.

| Profile | Engines / Games | Key Runtime Notes |
| --- | --- | --- |
| `common` | BGI, KiriKiri, legacy Artemis, NScripter, YU-RIS, RealLive, Majiro, AdvHD, QLIE, Unknown | The shared root: DirectShow stack `quartz`, `amstream`, `lavfilters`; LAV WMA registry switches. No launch settings of its own |
| `kirikiri` | No engine any more; games configured in it earlier stay pinned to it | `common` launched with `quartz=native`; lives in `common`'s prefix |
| `leaf` | Leaf/AQUAPLUS, WHITE ALBUM2 | Clone of `common` with LAV RGB output; launched with builtin DirectShow and Wine's WMA/WMV codecs disabled |
| `do-kizunar` | 家族計画 追憶 | Clone of `common` with D.O. registry install paths; launched with builtin `quartz` and the game folder as `G:\` |
| `artemis-d3d11` | DirectShow-oriented Artemis/iarsys D3D11, e.g. ハミダシクリエイティブ凸 | `common` launched with the DXMT v0.80 Wine variant; lives in `common`'s prefix |
| `artemis-mf-d3d11` | Media Foundation Artemis/iarsys D3D11, e.g. 甜蜜女友3 / アマカノ3 | Separate DXMT profile for MF/WMV routing; no DirectShow/LAV preset; Gala MF Runtime plus per-game WMV audio overlay |
| `cat-system2` | CatSystem2 | Unverified, no tested game: common video components plus `dotnet40`, `vcrun2015` |
| `siglus-engine` | SiglusEngine, e.g. Summer Pockets REFLECTION BLUE | Clone of `common` plus `xact`, `xinput`, `vcrun2019`; launched with builtin `quartz`/`amstream` and native `xaudio2_7`/`xactengine3_7`. The opening movie plays only after the user sets the game to MCI, which the profile's `advice` says |

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
- Tests also run on GitHub's machines (`.github/workflows/test.yml`), which have no login session and three cores. A call that waits on a system service there (CoreText asked about a font macOS could download) never returns, and three blocked tests starve every other one. Keep such calls behind a timeout in the code and out of the tests that run with `CI` set.
- `Gala.xcodeproj` is generated and not committed. Edit `project.yml`, which also holds the version number, then run `xcodegen generate`.
- Commit messages use a `feat:`, `fix:`, `perf:`, `docs:`, or `chore:` prefix.
- Record user-visible changes under `## [Unreleased]` in `CHANGELOG.md`. That section opens with `### 更新摘要`: a few plain Chinese lines for users, since the whole section is shown in the app's update window and on the release page. The detailed entries below it stay English. `scripts/release.sh` refuses a version without the summary.
- `docs/compatibility.md` is generated from the profiles' `verifiedGames`; a test fails when it is stale. Regenerate it with `swift run --package-path GalaKit gala-cli compat > docs/compatibility.md`. When a game is confirmed to run, add its original title to the profile's `verifiedGames`, with the release in parentheses when the title exists as more than one program (an original and a re-release on another engine).
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
