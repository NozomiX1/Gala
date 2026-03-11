# Gala

macOS-native galgame (visual novel) launcher powered by GPTK Wine.

Add your games, click play. Gala handles Wine prefix setup, Japanese locale configuration, and engine-specific optimizations automatically.

## Features

- **One-click launch** - Auto-configures Wine prefix with Japanese locale, fonts, and codepage
- **Engine detection** - Identifies KiriKiri, SiglusEngine, CatSystem2, BGI, and 10+ engines, applies optimal Wine presets
- **VNDB integration** - Search and match games to pull cover art, descriptions, tags, and ratings
- **Play time tracking** - Automatically records play time and last played timestamp
- **Game library** - Grid view with search, filter, and sort
- **Native engine support** - Ren'Py, RPG Maker MV/MZ, and Unity games launch natively without Wine

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon Mac (M1 or later)

## Building

```bash
open Gala.xcodeproj
# Build and run with Xcode
```

## How It Works

Gala wraps GPTK Wine (Apple's Game Porting Toolkit based Wine build with D3DMetal) to run Windows visual novels on macOS. On first launch, it downloads a pre-compiled GPTK Wine build. Each game gets its own isolated Wine prefix, pre-configured for Japanese games.

## Architecture

- **Gala** - SwiftUI app (UI layer)
- **GalaKit** - Swift Package with core logic (Wine management, engine detection, VNDB client)

See [design doc](docs/plans/2026-03-11-gala-design.md) for full details.

## License

MIT
