# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### 更新摘要
- 运行设置里多了「文字区域」开关：想玩日文原版游戏时选日文，相当于转区。
- 吉里吉里（KiriKiri）游戏和较新的 Artemis 游戏现在和其他游戏共用同一个运行环境，新添加游戏时少建环境、少占空间。已经配置好的游戏不受影响。
- 修复：甜蜜女友 3 这类游戏配置后第一次启动会黑屏并自动退出。
- 修复：游戏页面的「···」按钮比旁边的按钮小。
- 封面右键菜单里可以直接「复制求助信息…」；求助信息会提示引擎是否认得不准、启动文件是否加了壳。

### Added
- A third per-game switch in run settings, 文字区域: start the game in a Japanese locale, for Japanese originals that fail, show mojibake, or cannot find their files under the Chinese one. It takes effect at the next launch without reconfiguring. `gala-cli` takes it as `--switch locale=ja`.
- 复制求助信息… is also in the cover's right-click menu on the library wall.
- Diagnostics say when the engine label was taken from VNDB because nothing in the game folder identified it, and when the launch file looks like it was wrapped by a protector. The second is a hint for reading a crash; it does not stop a launch.

### Changed
- KiriKiri games now run in the `common` environment, and `artemis-d3d11` shares `common`'s Wine prefix instead of building its own. A library with BGI, KiriKiri, and Artemis D3D11 games needs one prefix where it needed three. Games already configured are left exactly where they are: KiriKiri ones stay on the old environment, now listed as "KiriKiri（旧）".

### Fixed
- The ··· button on the game page was drawn smaller than the buttons beside it in the released build (and square on macOS 15). It now uses the same button as the others.
- The first launch of a Media Foundation Artemis game (アマカノ3) after configuring showed a black window for most of a minute and then quit. The video component's plugin index is now built before the game starts, which takes a few seconds.
- A game whose releases use different engines (an original and a re-release on another engine) is no longer labelled with one of them by guesswork when nothing in its folder identifies the engine. It is added as unknown and runs in `common`.

## [2.0.0] - 2026-10-13

### Added
- User runtime profiles: a JSON file dropped into `Profiles/` in Gala's data directory becomes a selectable runtime environment, building on a bundled one through `base`. A broken file is skipped and reported instead of stopping the app.
- A game can be pointed at any profile by hand. `gala-cli profiles` lists them, `gala-cli use <game> <profile>` switches and saves, and `--profile` tries one for a single run.
- Run settings on the game page (the sliders button next to launch): pick the runtime profile, set the two switches, and fill in custom DLL overrides, environment variables, and launch arguments. "把当前配置导出为文件…" writes the result as a profile file someone else can use.
- Two per-game switches that take effect at the next launch without reconfiguring: 视频播放方式 (automatic, Windows original, or Wine's own DirectShow) and 图形渲染 (automatic, DXMT, or Wine's own). `gala-cli` accepts them as `--switch video=builtin` and lists them in `guide`.
- "复制求助信息…" on the game page (in the ··· menu and on a failed launch): previews, then copies, a self-contained text with the diagnostics, the settings that can be changed, and how to phrase an answer, ready to paste into an AI assistant or an issue. "导出诊断信息…" saves the diagnostics as a text file.
- A failed launch opens a sheet once with Wine's error lines, "换个运行环境试试" (opens the run settings) and "复制求助信息…". Afterwards the status line keeps a "查看原因" link; the page itself no longer shifts.
- `gala-cli`, a command-line tool inside the app bundle (`Gala.app/Contents/MacOS/gala-cli`): `list`, `diagnose`, `configure`, `launch`, and `guide`, with `--json` output. `configure` and `launch` accept one-off `--profile`, `--dll`, `--env`, and `--locale` options for trying a change without saving it.
- Diagnostics report for a game: versions, engine detection candidates with scores and reasons, runtime profile and state, launch settings, the game directory listing, and an excerpt of the last Wine log. Paths under the home directory are shortened to `~`.
- Wine output of the last three launches of each game is kept under `Logs/` in Gala's data directory.
- In-app updates through Sparkle: Gala checks for new versions, shows the release notes, and downloads and installs the update. Updates are verified against Gala's own signing key.

### Changed
- Runtime profiles are now JSON files bundled with the app instead of Swift code. Prefixes configured by earlier versions stay valid; a prefix configured from here on also remembers a fingerprint of its recipe, so a later change to its profile is noticed automatically.
- New main window: a wall of covers with the filters in the toolbar and no sidebar; clicking a cover opens the game's own page, which uses the cover art as a dark backdrop. Controls use the system glass material on macOS 26 and later and an ordinary material on older systems.
- The runtime environment sheet is now a standard Settings window (⌘,) with General, Runtime, and Data tabs; the two destructive actions sit on their own tab.
- Covers show the original-script title instead of the romanised one.
- The game page shows the Chinese title, the developer and release date, the VNDB rating with its vote count, the average time to finish, whether a Chinese version exists (official, fan translation, or none), and the engine. These are fetched from VNDB when a game is added and stored with it; games added earlier fetch them the first time their page is opened.
- Favourite and completed are icon buttons next to the launch button on the game page.
- Games can be added by dropping a game folder or an .exe anywhere on the window, from the dashed tile at the end of the cover wall, or with File → 添加游戏… (⌘N). The toolbar no longer has an add button.
- Adding a game opens the file picker straight away, then a redesigned sheet for matching it against VNDB.
- Ren'Py, RPG Maker, and Unity games now run through Wine in the `common` profile. Native launch only worked when a `.app` sat next to the selected exe and otherwise left the game unlaunchable. Existing entries on those engines go back to "配置环境".
- The two Artemis D3D11 profiles no longer copy DXMT's DLLs into the prefix or install a native `d3dcompiler_47`: neither had any effect, and the copy replaced the native `quartz` and `amstream` the profile had just installed. A profile now only needs `"wine": "dxmt"`. Prefixes configured by earlier versions stay valid.
- Launches from the app now keep Wine's error lines in the log (`WINEDEBUG=fixme-all` instead of `-all`), so the first failed launch already has something to show. `gala-cli launch` still records more.
- The README now states what is verified to run and how to get other games going; the list of verified games is generated into `docs/compatibility.md` from the profile files. Issue templates ask for the help text.
- `Gala.xcodeproj` is no longer committed; generate it with `xcodegen generate`.
- The bundle build number now equals the version number.

### Fixed
- Games written for Japanese Windows that pick their text font by name (BGI, for one) can switch between Song and Hei typefaces again: 穢翼のユースティア's 宋体/黑体 option used to change nothing. They are drawn in SimSong and STHeiti, which fit the size those games ask for. Both are Apple fonts that macOS downloads on request; Gala asks for them while creating a runtime environment and uses STSong and Arial Unicode MS if that fails. Settings → 运行环境 has a 可选字体 row that shows whether they are installed, downloads them, and applies them to environments that already exist, including ones configured by 1.x.
- VNDB matches now fill in the game description; the search request never asked for it.
- `宋体` and `黑体` font substitutes are registered under their real names instead of literal `\u` escape text.

### Removed
- The manual update check that only opened the latest DMG; Sparkle replaces it.
- Unused game tags, VNDB detail request, and `BottleConfig` `windowsVersion` / `winetricksComponents` fields. Libraries saved by this version cannot be opened by 1.2.1 or earlier.
- Homebrew winetricks fallback; Gala only uses its managed copy.
- Unused `rpg-maker` and `unity` runtime profiles and their untested presets.
- `docs/plans/`. The findings that still hold moved to `docs/runtime-lessons.md`.
- `CLAUDE.md`; `AGENTS.md` is the only agent guide.

## [1.2.1] - 2026-06-05

### Added
- `artemis-mf-d3d11` runtime profile for Artemis/iarsys D3D11 games that use Media Foundation WMV playback, such as 甜蜜女友3 / アマカノ3.
- Gala-owned `deps-v3` Media Foundation runtime dependency for `artemis-mf-d3d11`.
- Per-game Media Foundation movie overlays that keep original game files untouched while preparing compatible WMV audio tracks.

### Changed
- App version metadata is synchronized to `1.2.1` / build `6`.
- Gala now shows a lightweight startup loading view and loads the library, runtime migrations, and runtime status asynchronously after the window appears.
- Runtime-profile migrations now mark each game with the migration rules version and selected executable path so already-current entries skip future engine scans until the rules or executable change.
- Adding a game now runs local engine detection in the background instead of blocking the file-selection flow.
- `artemis-d3d11` runtime profile version is now `4` so existing configured prefixes can be flagged for one-time reconfiguration.
- `artemis-mf-d3d11` runtime profile version is now `2` so existing configured prefixes can install the Media Foundation runtime and registry changes.
- Artemis/iarsys D3D11 detection now splits DirectShow-style games from Media Foundation-style games by scanning local executable imports instead of putting all iarsys/D3D11 games in one bottle.
- Existing Media Foundation Artemis D3D11 library entries migrate from `artemis-d3d11` to `artemis-mf-d3d11` and require runtime reconfiguration.
- Runtime configuration now uses profile markers to skip repeated preset installation for new games sharing an already-current prefix.

### Fixed
- DirectShow-style Artemis/iarsys D3D11 WMV clips and OP movies now use the DirectShow/LAV video chain, including `.dat` files that contain ASF/WMV video, while keeping DXMT rendering isolated from `d3d11`/`dxgi` overrides.
- Wine 11.6 DirectShow no longer gets stuck on `File Source (Async.)` for ASF/WMV clips disguised as `.dat`; Gala now removes the bad `.dat` extension mapping and routes ASF content signatures to LAV Splitter Source.
- Media Foundation Artemis D3D11 games such as 甜蜜女友3 / アマカノ3 no longer share the DirectShow-focused `artemis-d3d11` bottle used by Hamidashi-style games.
- 甜蜜女友3 / アマカノ3 Media Foundation WMV playback now uses a Gala media compatibility layer: Wine MF is routed through the FFmpeg backend, GStreamer/FFmpeg runtime paths are injected only for this profile, and WMA audio inside `movie/*.wmv` is converted to PCM in a cached overlay.

## [1.2.0] - 2026-06-05

### Added
- Manual update checks backed by GitHub Releases, with release notes and links to the latest DMG or release page.
- Versioned `library.json` document format while keeping compatibility with the legacy top-level array format.
- Migration-safe library saves that create a backup before runtime profile migrations overwrite `library.json`.
- Runtime profile markers for configured Wine prefixes so future versions can detect outdated profile configurations without deleting bottles.
- Library load failure UI that prevents Gala from silently treating a broken library as an empty library.

### Changed
- App version metadata is synchronized to `1.2.0` / build `5` so update comparisons can use the bundle version reliably.
- Runtime profile migrations now write through the migration-safe save path.

### Fixed
- Manual update checks now ignore Gala dependency-bundle releases such as `deps-v2` and select the latest App version release instead.

## [1.1.2] - 2026-06-05

### Added
- `artemis-d3d11` runtime profile for modern Artemis/iarsys D3D11 games such as 甜蜜女友3 / アマカノ3.
- Gala-managed DXMT v0.80 builtin dependency, downloaded from Gala release assets only when the `artemis-d3d11` profile is configured.
- Local engine detection scoring for mixed file sets, so iarsys/PFS/D3D11 signatures can override XP3 patch archives.

### Changed
- Artemis/iarsys D3D11 games now launch with a DXMT Wine variant instead of the default Wine runtime.
- Existing misdetected Artemis D3D11 library entries in KiriKiri/Artemis/unknown profiles migrate to `artemis-d3d11` and require runtime reconfiguration.

### Fixed
- Black screen with audio in 甜蜜女友3 / アマカノ3 under the common/KiriKiri Wine profiles.

## [1.1.1] - 2026-05-06

### Added
- Runtime-profile selection policy that prefers local engine signatures, then falls back to VNDB release engine metadata.
- VNDB release filtering for engine fallback so non-Windows releases and patch releases do not affect Wine profile selection.
- Ikura GDL / Family Project detection and a separate `do-kizunar` runtime profile for 家族計画 追憶.
- Migration for existing 家族計画 entries that had previously been configured in `common`.

### Changed
- Treat `common` as the shared default Wine profile for unknown and DirectShow-based engines instead of maintaining a separate base/legacy split.
- Keep special VNDB engine aliases guarded by local signatures: `Ikura GDL` only selects the Family Project profile when local Family Project files are present, and `AQUAPLUS Engine` only selects Leaf when local Leaf/WHITE ALBUM2 files are present.
- Add the validated LAV Audio WMA switches (`wma`, `wmapro`, `wmalossless`) to the common DirectShow preset.
- Keep 家族計画's builtin `quartz` and `G:\` registry path requirements isolated from BGI/AUGUST games.

### Fixed
- 家族計画 追憶 now starts and plays its OP through its own Wine profile without contaminating `common`.
- BGI games such as 穢翼のユースティア and 大図書館の羊飼い stay on the native/builtin DirectShow chain in `common`.
- WHITE ALBUM2 keeps its Leaf-specific LAV RGB/WMA configuration in the `leaf` profile instead of sharing those stricter overrides with other games.

## [1.1.0] - 2026-05-05

### Added
- Explicit runtime configuration flow: newly added Wine games now show "配置环境" before they can be launched.
- Separate "移除运行环境" and "从库中移除" actions so play records can be preserved independently from Wine configuration.
- Runtime environment page with dependency checks, one-click repair, Wine configuration cleanup, and full local data cleanup.
- Download and setup progress for Wine, fonts, helper tools, Wine extraction, and per-engine preset components.
- Post-reset recovery screen that lets the user reinstall the runtime environment or quit after clearing all local data.
- App-owned winetricks cache under `~/Library/Application Support/Gala/Cache/winetricks`.

### Changed
- Reuse Wine prefixes by runtime profile instead of creating a separate bottle for every game.
- Delete a Wine prefix by default only when the removed game is its last configured user.
- Download Gala-managed Wine, font, cabextract, and winetricks assets from the Gala release dependency bundle.
- Route winetricks through Gala-managed helper tools and cache paths instead of relying on user-level Homebrew or global caches.

### Fixed
- Wine launcher sessions no longer flip back to idle as soon as a small game launcher spawns the real child process.
- Clearing Wine configuration now marks affected games as needing runtime configuration again.
- Clearing all local data no longer leaves the running app with missing library/cache directories.
- Missing or failed helper-tool downloads can be repaired from the runtime environment page.

## [1.0] - 2026-05-05

### Added
- Project design document
- README and project scaffolding
- Leaf/AQUAPLUS engine detection and preset support for WHITE ALBUM2.
- Legacy DirectShow video preset for Artemis, NScripter, YU-RIS, and RealLive engines.
- Wine launch diagnostics that keep meaningful crash output while suppressing harmless graphics capability noise.

### Changed
- Install Source Han Sans SC Regular into every Wine bottle and map common CJK / legacy Windows UI fonts to it.
- Configure Wine window metric fonts and font smoothing for CJK system dialogs, menus, and message boxes.
- Share the `quartz` / `amstream` / `lavfilters` video component preset across engines that use legacy DirectShow playback.
- Use a stricter Leaf/AQUAPLUS video preset with builtin DirectShow routing and RGB-only LAV output.
- Update README compatibility notes for the verified BGI, Leaf/AQUAPLUS, and KiriKiri test games.

### Fixed
- CJK text rendering as square boxes in Wine-hosted Win32 dialogs and UI chrome.
- WHITE ALBUM2 OP/video playback failures and long black-screen waits during movie startup.
- 秽翼のユースティア OP playback and startup delay caused by an incomplete DirectShow / LAV path.
- False "game quickly exited" errors when Wine emitted harmless MoltenVK / Vulkan warnings such as `EXT_texture_array' is not supported`.
