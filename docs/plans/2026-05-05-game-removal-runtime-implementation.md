# Game Removal Runtime Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split game runtime removal from library record removal so play history can be preserved while Wine configuration is cleaned safely.

**Architecture:** Add a per-game runtime configured marker, centralize shared Wine prefix deletion decisions in GalaKit, and update SwiftUI actions so environment setup is explicit before launch. Library operations use the shared policy to delete a prefix only when the current game is its last configured user.

**Tech Stack:** Swift 5.10, SwiftUI, Swift Testing, GalaKit, Wine prefix management.

---

### Task 1: Runtime State Model

**Files:**
- Modify: `GalaKit/Sources/GalaKit/Models/Game.swift`
- Modify: `GalaKit/Tests/GalaKitTests/ModelsTests.swift`

**Step 1: Write failing tests**

Add tests that verify:

- New games default to `isRuntimeConfigured == false`.
- Encoded games round-trip the runtime marker.
- Old JSON without `isRuntimeConfigured` decodes as configured when `bottleConfig.prefixPath` is non-empty.
- Old JSON without `isRuntimeConfigured` decodes as not configured when the prefix path is empty.

**Step 2: Run tests to verify failure**

Run: `swift test --package-path GalaKit --filter ModelsTests`

Expected: failures because `Game.isRuntimeConfigured` does not exist.

**Step 3: Implement model field**

Add `public var isRuntimeConfigured: Bool` to `Game`.

Add an init parameter:

```swift
isRuntimeConfigured: Bool = false
```

In `init(from:)`, decode `bottleConfig` first, then:

```swift
isRuntimeConfigured = try container.decodeIfPresent(Bool.self, forKey: .isRuntimeConfigured)
    ?? !bottleConfig.prefixPath.isEmpty
```

**Step 4: Run tests**

Run: `swift test --package-path GalaKit --filter ModelsTests`

Expected: all model tests pass.

### Task 2: Shared Prefix Deletion Policy

**Files:**
- Create: `GalaKit/Sources/GalaKit/Library/RuntimeConfigurationPolicy.swift`
- Create: `GalaKit/Tests/GalaKitTests/RuntimeConfigurationPolicyTests.swift`

**Step 1: Write failing tests**

Cover these cases:

- Last configured Wine user returns `true`.
- Shared configured Wine user returns `false`.
- Unconfigured game returns `false`.
- Native engine returns `false`.
- Empty prefix returns `false`.

**Step 2: Run tests to verify failure**

Run: `swift test --package-path GalaKit --filter RuntimeConfigurationPolicyTests`

Expected: failure because the policy type does not exist.

**Step 3: Implement policy**

Create:

```swift
public enum RuntimeConfigurationPolicy {
    public static func shouldDeleteRuntimeConfiguration(for game: Game, in games: [Game]) -> Bool
}
```

Rules:

- Return `false` if the game is not runtime configured.
- Return `false` for native-launch engines.
- Return `false` for empty prefix paths.
- Return `true` only when no other configured non-native game has the same prefix path.

**Step 4: Run tests**

Run: `swift test --package-path GalaKit --filter RuntimeConfigurationPolicyTests`

Expected: policy tests pass.

### Task 3: Library Operations

**Files:**
- Modify: `Gala/ViewModels/LibraryViewModel.swift`
- Modify: `Gala/Views/ContentView.swift`

**Step 1: Add view-model operations**

Add methods:

```swift
func markRuntimeConfigured(for game: Game)
func removeRuntime(for game: Game)
func removeFromLibrary(_ game: Game)
func markWineRuntimesUnconfigured()
```

`removeRuntime` and `removeFromLibrary` use `RuntimeConfigurationPolicy` and `BottleManager.deleteBottle(for:)` when the game is the last configured user.

`removeFromLibrary` also deletes cover cache and removes the game record.

**Step 2: Replace old deletion call sites**

Update `ContentView` to call:

- `removeRuntime(for:)` for "移除运行环境"
- `removeFromLibrary(_:)` for "从库中移除"

### Task 4: Explicit Configure-Then-Launch Flow

**Files:**
- Modify: `Gala/ViewModels/GameViewModel.swift`
- Modify: `Gala/Views/Detail/GameDetailView.swift`
- Modify: `Gala/Views/Library/GameGridView.swift`
- Modify: `Gala/Views/Library/GameCoverCard.swift`
- Modify: `Gala/Views/Setup/AddGameView.swift`

**Step 1: Update GameViewModel**

Add:

```swift
func configureRuntime(for game: Game, viewModel: LibraryViewModel)
```

Move Wine bottle creation and engine preset setup out of `launchGame` into this method.

Make `launchGame` require `game.isRuntimeConfigured == true`; if false, set an error and do not configure automatically.

**Step 2: Update AddGameView**

Adding a game should save the record with `isRuntimeConfigured: false` and should not create the prefix directory.

**Step 3: Update detail button**

Display:

- `配置环境` when `game.isRuntimeConfigured == false`
- `启动` when configured
- `正在配置...` while configuring
- `运行中...` while running

**Step 4: Update card context menu**

Replace "删除游戏" with:

- `移除运行环境` when configured
- `从库中移除`

Show `配置环境` instead of `启动游戏` for unconfigured games.

### Task 5: Runtime Environment Page Integration

**Files:**
- Modify: `Gala/Views/RuntimeEnvironmentView.swift`
- Modify: `Gala/Views/ContentView.swift`

**Step 1: Add environment change type**

Make `RuntimeEnvironmentView` report whether the change is:

- Dependencies repaired
- Wine configuration reset
- All application data reset

**Step 2: Update parent response**

When Wine configuration is reset, call `markWineRuntimesUnconfigured()` so all Wine games show `配置环境`.

When all app data is reset, reload the library and clear selection.

### Task 6: Verification

**Files:**
- Modify docs only if behavior text needs a small README adjustment.

**Step 1: Run GalaKit tests**

Run: `swift test --package-path GalaKit`

Expected: all tests pass.

**Step 2: Build app**

Run:

```bash
xcodebuild -project Gala.xcodeproj -scheme Gala -destination 'platform=macOS' -derivedDataPath /tmp/GalaDerivedData build
```

Expected: `BUILD SUCCEEDED`.

**Step 3: Manual smoke path**

Run the app from Xcode or built `.app` and verify:

- Added game shows `配置环境`.
- Configuring changes the button to `启动`.
- Removing runtime keeps the record and play time.
- Removing from library removes the record.
