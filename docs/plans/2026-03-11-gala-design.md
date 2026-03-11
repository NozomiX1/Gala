# Gala - macOS Galgame Launcher Design

## Overview

Gala is a macOS-native galgame (visual novel) launcher that wraps GPTK Wine to provide a Steam-like game library management experience. It targets both casual players (one-click launch) and power users (full Wine configuration access).

## Tech Stack

| Layer | Choice |
|-------|--------|
| Language | Swift |
| UI | SwiftUI (macOS 14+) |
| Architecture | MVVM, core logic in separate Swift Package (GalaKit) |
| Persistence | JSON files + Codable |
| Wine Integration | Foundation.Process |
| Metadata | VNDB API v2 (Kana) |
| Image Cache | Local file cache in Application Support |
| Distribution | DMG + Notarization |

## Data Model

```
Game
├── id: UUID
├── title: String
├── originalTitle: String?
├── vndbId: String?
├── executablePath: String
├── coverImagePath: String?
├── engine: Engine?
├── totalPlayTime: TimeInterval
├── lastPlayedAt: Date?
├── addedAt: Date
├── rating: Double?
├── developer: String?
├── releasedAt: String?
├── description: String?
├── tags: [String]
├── status: GameStatus              (backlog/playing/completed/dropped)
└── bottleConfig: BottleConfig

BottleConfig (embedded in Game)
├── prefixPath: String
├── windowsVersion: WinVersion
├── dllOverrides: [String: String]
├── environment: [String: String]
├── launchArguments: [String]
├── locale: String                  (default "ja_JP.UTF-8")
└── winetricksComponents: [String]

Engine (enum)
├── kirikiri, nscripter, renpy, rpgMaker, unity
├── bgi, catSystem2, siglusEngine, artemis, yuris
├── majiro, advHD, realLive, qlie, unknown
```

Storage: `~/Library/Application Support/Gala/library.json`

## Project Structure

```
Gala/
├── Gala/                           # SwiftUI app (UI layer)
│   ├── GalaApp.swift
│   ├── Views/
│   │   ├── ContentView.swift       # NavigationSplitView layout
│   │   ├── Library/
│   │   │   ├── GameGridView.swift
│   │   │   ├── GameListView.swift
│   │   │   └── GameCoverCard.swift
│   │   ├── Detail/
│   │   │   ├── GameDetailView.swift
│   │   │   └── GameSettingsView.swift
│   │   ├── Setup/
│   │   │   ├── AddGameView.swift
│   │   │   └── VNDBSearchView.swift
│   │   └── Settings/
│   │       └── AppSettingsView.swift
│   └── ViewModels/
│       ├── LibraryViewModel.swift
│       └── GameViewModel.swift
│
├── GalaKit/                        # Core logic (Swift Package)
│   └── Sources/GalaKit/
│       ├── Wine/
│       │   ├── WineManager.swift
│       │   ├── WineProcess.swift
│       │   └── BottleManager.swift
│       ├── Engine/
│       │   └── EngineDetector.swift
│       ├── VNDB/
│       │   └── VNDBClient.swift
│       ├── Library/
│       │   ├── LibraryStore.swift
│       │   └── ImageCache.swift
│       └── Models/
│           ├── Game.swift
│           ├── BottleConfig.swift
│           └── Engine.swift
└── Gala.xcodeproj
```

## File System Layout

```
~/Library/Application Support/Gala/
├── Wine/
│   ├── active -> wine-gptk-2.0/    # Symlink to active version
│   ├── wine-gptk-2.0/
│   │   ├── bin/wine64
│   │   ├── lib/
│   │   └── share/
│   └── wine-gptk-3.0/              # Multiple versions supported
├── Bottles/
│   ├── <game-uuid-1>/              # Per-game Wine Prefix
│   │   ├── drive_c/
│   │   ├── system.reg
│   │   └── user.reg
│   └── <game-uuid-2>/
├── Cache/
│   └── covers/
│       ├── v11.jpg
│       └── v17.jpg
└── library.json
```

## Core Components

### WineManager

Manages GPTK Wine binary download and versioning.

- `checkInstallation()` - detect existing Wine
- `downloadWine(version:)` - download pre-compiled GPTK Wine from remote (with progress)
- `listVersions()` - list installed Wine versions
- `setActiveVersion()` - switch active version (update symlink)
- `getWineBinary()` - return path to wine64

Download source: pre-compiled GPTK Wine builds hosted on GitHub Releases (reference Whisky's build pipeline).

### BottleManager

Manages per-game Wine Prefixes.

- `createBottle(for:)` - create new Prefix + `wineboot --init`
- `configureLocale()` - set Japanese locale + codepage 932
- `installFonts()` - install CJK fonts into Prefix
- `installComponents([])` - `winetricks -q` install components
- `setDllOverrides([:])` - write DLL overrides to registry
- `applyEnginePreset()` - apply engine-specific configuration
- `deleteBottle()` - delete entire Prefix directory

### Engine Presets

Base layer (all games): Japanese locale, CJK fonts, codepage 932, vcrun2019, d3dx9

Engine-specific additions:

| Engine | Components | DLL Overrides |
|--------|-----------|---------------|
| KiriKiri | quartz, amstream, lavfilters | quartz=native |
| NScripter | (base only) | - |
| BGI | quartz, amstream, lavfilters | - |
| CatSystem2 | dotnet40, quartz, vcrun2015 | - |
| SiglusEngine | quartz, amstream, lavfilters, xact, xinput, vcrun2019 | xaudio2_7=native, xactengine3_7=native |
| RPG Maker | RTP runtime | - |
| Unity | dotnet48, d3dcompiler_47 | - |

### EngineDetector

Waterfall detection strategy:

1. **Unique filenames** (fastest): `data.xp3` -> KiriKiri, `renpy/` -> Ren'Py, etc.
2. **File magic bytes** (read first 64 bytes): XP3 header, RPA header, RGSSAD header, etc.
3. **EXE/DLL filename matching**: `SiglusEngine.exe`, `UnityPlayer.dll`, `RGSS3*.dll`
4. **EXE binary string search**: search for engine name strings in first 2-4 MB

Cross-validated with VNDB Release `engine` field when available.

Coverage: ~85% with layers 1-2, ~95% with all four layers.

### VNDBClient

Interfaces with VNDB API v2 (https://api.vndb.org/kana).

- `searchVN(query:)` - POST /kana/vn with search filter
- `getVNDetail(id:)` - get full VN info (cover, description, tags, rating)
- `getReleases(vnId:)` - get releases (includes engine field)
- `downloadCover(url:)` - download cover image to local cache
- Built-in throttling (200 requests / 5 minutes)
- No authentication required for read-only queries

### WineProcess

Launches and monitors game processes.

```
launch(game) ->
  process.executableURL = wineManager.getWineBinary()
  process.arguments = [game.executablePath]
  process.environment = {
    WINEPREFIX: game.bottleConfig.prefixPath,
    LANG: "ja_JP.UTF-8",
    LC_ALL: "ja_JP.UTF-8",
    ...game.bottleConfig.environment
  }
  record startTime
  process.terminationHandler = {
    duration = now - startTime
    game.totalPlayTime += duration
    game.lastPlayedAt = now
    libraryStore.save()
  }
  process.run()
```

### Native Engine Handling

Some engines don't need Wine:

| Engine | Strategy |
|--------|----------|
| Ren'Py | Detect macOS native binary (.app/.sh), launch directly if found |
| RPG Maker MV/MZ | Detect `www/` + `package.json`, run with NW.js natively |
| Unity | Detect .app bundle, launch directly if found |
| NScripter | Suggest ONScripter (native open-source reimplementation) |

## User Flows

### First Launch

```
App starts -> check Wine installation
  -> Not found -> Welcome screen with one-click Wine download (progress bar)
  -> Found -> Enter game library (empty state with "Add Game" prompt)
```

### Add Game

```
Click "+" -> NSOpenPanel to select .exe
  -> Scan game directory, detect engine
  -> VNDB search dialog (pre-filled with folder name)
    -> User selects matching VN (or skips)
    -> Pull cover, title, description, tags, rating
  -> Background:
    1. Create Wine Prefix (wineboot --init)
    2. Apply base config (locale, fonts, codepage)
    3. Apply engine preset (winetricks components)
  -> Game appears in library
```

### Launch Game

```
Click game cover / launch button
  -> WineProcess assembles command
  -> Record start time, UI shows "running" indicator
  -> terminationHandler: calculate play time, update library.json
  -> UI returns to idle state
```

### Browse Library

```
NavigationSplitView:
  Sidebar: All / Recent / Playing / Backlog / Completed / Dropped
  Content: Game cover grid (searchable, sortable)
  Detail: Selected game info + launch button + settings
```

## Settings

### Per-Game (advanced, collapsed by default)

- Executable path, launch arguments
- Game status (backlog/playing/completed/dropped)
- Wine config: Windows version, DLL overrides, environment variables
- Installed components list + install more
- Prefix path (read-only, open in Finder)
- Reset Prefix (delete and recreate)
- View Wine log

### Global

- Game library scan path
- Check Wine updates on launch
- Active Wine version + switch/update
- Default Windows version
- Bottles storage path
- Cover size (small/medium/large)
- Default view (grid/list)

## MVP Scope (v0.1)

Included:
- Wine auto-download (first launch detection + one-click download)
- Add game (select .exe, create independent Bottle)
- Auto Japanese environment setup (locale + fonts + codepage)
- Engine detection (file signature scan, layers 1-2)
- Engine preset configuration (auto winetricks install)
- Launch game (one-click, Wine process management)
- Play time tracking (auto record, display in library)
- Game library browsing (grid view + search + filter by status)
- VNDB search matching (search + pull cover/metadata on add)
- Ren'Py native launch (detect and launch without Wine)

Deferred to v0.2:
- List view + grid/list toggle
- Game status management
- Advanced Wine settings UI
- Wine multi-version management
- Wine log viewer
- Sort by play time / rating / date added

Deferred to v0.3:
- Tag-based grouping in sidebar
- RPG Maker / Unity native launch
- Save backup/restore
- Custom cover art (drag to replace)
- Sparkle auto-update

Not planned:
- Community compatibility database (needs backend + community)
- In-game overlay
- Cloud save sync
- Full i18n (start with Chinese + English UI)
- Social features

## Key References

- **Whisky** (github.com/Whisky-App/Whisky) - SwiftUI Wine wrapper architecture (GPL-3.0, reference design only, no code reuse)
- **VNDB API** (api.vndb.org/kana) - metadata source
- **GARbro** - engine file signature reference
- **Lutris** - install script YAML format reference
- **Heroic Games Launcher** - Wine/GPTK integration patterns
