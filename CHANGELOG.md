# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

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
