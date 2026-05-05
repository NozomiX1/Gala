# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

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
