# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

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
