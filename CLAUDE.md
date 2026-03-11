# Gala - Project Guide

## What is this?
macOS-native galgame launcher wrapping GPTK Wine. SwiftUI app + GalaKit Swift Package.

## Tech Stack
- Swift / SwiftUI (macOS 14+)
- MVVM architecture
- JSON file persistence (Codable)
- Foundation.Process for Wine integration
- VNDB API v2 for metadata

## Project Structure
- `Gala/` - SwiftUI app (Views, ViewModels)
- `GalaKit/` - Core logic Swift Package (Wine, Engine, VNDB, Library, Models)
- `docs/plans/` - Design documents

## Key Decisions
- Game-centric UI (not Bottle-centric like Whisky) - users see games, not Wine prefixes
- Each game gets its own isolated Wine prefix
- Engine detection via file signatures + VNDB cross-validation
- GPTK Wine auto-downloaded on first launch (not bundled)
- Reference Whisky's architecture patterns but independent implementation (Whisky is GPL-3.0)

## Conventions
- Use SwiftUI previews for UI development
- Keep GalaKit free of UI dependencies
- JSON files for persistence, no database
- All Wine operations go through WineManager/BottleManager/WineProcess
