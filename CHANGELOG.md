# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- `artemis-mf-d3d11` runtime profile for Artemis/iarsys D3D11 games that use Media Foundation WMV playback, such as 甜蜜女友3 / アマカノ3.
- Gala-owned `deps-v3` Media Foundation runtime dependency for `artemis-mf-d3d11`.
- Per-game Media Foundation movie overlays that keep original game files untouched while preparing compatible WMV audio tracks.

### Changed
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
